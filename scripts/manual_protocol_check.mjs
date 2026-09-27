import assert from "node:assert/strict";
import { once } from "node:events";
import WebSocket from "ws";
import { createPromptHeistServer } from "../server/src/server.js";

const service = createPromptHeistServer({ logger: () => {} });
const address = await service.listen();
const url = `ws://127.0.0.1:${address.port}/ws`;

function envelope(type, requestId, payload) {
  return { version: 1, type, request_id: requestId, payload };
}

async function client() {
  const socket = new WebSocket(url);
  const messages = [];
  socket.on("message", (data) => messages.push(JSON.parse(String(data))));
  await once(socket, "open");
  return { socket, messages };
}

async function waitFor(connection, predicate) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const match = connection.messages.find(predicate);
    if (match) return match;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error(`Timed out; received ${JSON.stringify(connection.messages)}`);
}

const ada = await client();
const ben = await client();

try {
  ada.socket.send(JSON.stringify(envelope("create_room", "manual-create", { display_name: "Ada" })));
  const created = await waitFor(ada, (message) => message.type === "command_result");
  const roomCode = created.payload.room_code;

  ben.socket.send(
    JSON.stringify(envelope("join_room", "manual-join", { room_code: roomCode, display_name: "Ben" })),
  );
  const joined = await waitFor(ben, (message) => message.type === "command_result");
  const adaSnapshot = await waitFor(
    ada,
    (message) => message.type === "room_snapshot" && message.payload.player_count === 2,
  );
  const benSnapshot = await waitFor(
    ben,
    (message) => message.type === "room_snapshot" && message.payload.player_count === 2,
  );
  assert.deepEqual(adaSnapshot.payload, benSnapshot.payload);

  ada.socket.send("{");
  assert.equal(
    (await waitFor(ada, (message) => message.payload?.code === "malformed_message")).payload.code,
    "malformed_message",
  );
  ben.socket.send(
    JSON.stringify(
      envelope("join_room", "manual-forged", {
        room_code: roomCode,
        display_name: "Mallory",
        player_id: created.payload.player_id,
      }),
    ),
  );
  assert.equal(
    (await waitFor(ben, (message) => message.request_id === "manual-forged")).payload.code,
    "invalid_message",
  );

  const [adaConnection, benConnection] = service.registry.connectionIdsForRoom(roomCode);
  ada.messages.length = 0;
  ben.messages.length = 0;
  service.sendPrivate(adaConnection, { test_notice: "ada-only" });
  await waitFor(ada, (message) => message.type === "private_message");
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(ben.messages.some((message) => message.type === "private_message"), false);
  service.sendPrivate(benConnection, { test_notice: "ben-only" });
  await waitFor(ben, (message) => message.type === "private_message");
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(ada.messages.filter((message) => message.type === "private_message").length, 1);
  assert.notEqual(created.payload.session_id, joined.payload.session_id);

  console.log(`PASS room=${roomCode} clients=2 shared_snapshot=true malformed_rejected=true forged_rejected=true private_isolated=true`);
} finally {
  ada.socket.close();
  ben.socket.close();
  await Promise.all([once(ada.socket, "close"), once(ben.socket, "close")]);
  await service.close();
}
