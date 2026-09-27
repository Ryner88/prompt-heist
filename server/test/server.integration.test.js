import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import WebSocket from "ws";
import { MAX_PAYLOAD_BYTES } from "../src/constants.js";
import { command, connectClient, createRoom, startTestServer } from "./helpers.js";

test("health endpoint reports readiness", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const response = await fetch(`${server.httpUrl}/healthz`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ready", protocol_version: 1 });
  const missing = await fetch(`${server.httpUrl}/missing`);
  assert.equal(missing.status, 404);
  assert.deepEqual(await missing.json(), { error: "not_found" });
});

test("unknown rooms and a second session on one connection are rejected", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const client = await connectClient(server.websocketUrl);
  t.after(() => client.close());
  client.send(command("join_room", "missing", { room_code: "ZZZ999", display_name: "Ada" }));
  assert.equal((await client.next((message) => message.request_id === "missing")).payload.code, "unknown_room");
  await createRoom(client, "Ada", "first-session");
  client.send(command("create_room", "second-session", { display_name: "Ben" }));
  assert.equal(
    (await client.next((message) => message.request_id === "second-session")).payload.code,
    "connection_already_joined",
  );
  assert.equal(server.service.sendPrivate("missing-connection", { hidden: true }), false);
});

test("clients create and join through WebSocket and receive identical public snapshots", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  const ben = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([ada.close(), ben.close()]));

  const created = await createRoom(ada);
  ada.clear();
  ben.send(command("join_room", "join-1", { room_code: created.payload.room_code, display_name: "Ben" }));
  await ben.next((message) => message.type === "command_result");
  const [adaSnapshot, benSnapshot] = await Promise.all([
    ada.next((message) => message.type === "room_snapshot" && message.payload.player_count === 2),
    ben.next((message) => message.type === "room_snapshot" && message.payload.player_count === 2),
  ]);
  assert.deepEqual(adaSnapshot.payload, benSnapshot.payload);
  assert.deepEqual(adaSnapshot.payload.player_names, ["Ada", "Ben"]);
});

test("duplicate request IDs do not repeat state changes", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const client = await connectClient(server.websocketUrl);
  t.after(() => client.close());
  const create = command("create_room", "same-id", { display_name: "Ada" });
  client.send(create);
  const first = await client.next((message) => message.type === "command_result");
  client.clear();
  client.send(create);
  const replay = await client.next((message) => message.type === "command_result");
  assert.deepEqual(replay, first);
  assert.equal(server.service.registry.roomCount(), 1);
  assert.equal(client.messages.some((message) => message.type === "room_snapshot"), false);
});

test("two simultaneous final-seat joins yield exactly one success", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const clients = await Promise.all(Array.from({ length: 5 }, () => connectClient(server.websocketUrl)));
  t.after(() => Promise.all(clients.map((client) => client.close())));
  const created = await createRoom(clients[0]);
  const roomCode = created.payload.room_code;
  for (const [index, name] of ["Ben", "Cy"].entries()) {
    const client = clients[index + 1];
    client.send(command("join_room", `join-${name}`, { room_code: roomCode, display_name: name }));
    await client.next((message) => message.type === "command_result");
  }
  clients[3].send(command("join_room", "final-a", { room_code: roomCode, display_name: "Dee" }));
  clients[4].send(command("join_room", "final-b", { room_code: roomCode, display_name: "Eli" }));
  const outcomes = await Promise.all([
    clients[3].next((message) => message.request_id === "final-a"),
    clients[4].next((message) => message.request_id === "final-b"),
  ]);
  assert.deepEqual(outcomes.map((message) => message.type).sort(), ["command_result", "error"]);
  assert.equal(outcomes.find((message) => message.type === "error").payload.code, "room_full");
  assert.equal(server.service.registry.publicSnapshot(roomCode).player_count, 4);
});

test("private payload reaches only its intended connection", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  const ben = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([ada.close(), ben.close()]));
  const created = await createRoom(ada);
  ben.send(command("join_room", "join-private", { room_code: created.payload.room_code, display_name: "Ben" }));
  const joined = await ben.next((message) => message.type === "command_result");
  ada.clear();
  ben.clear();

  const benSession = server.service.registry.connectionIdsForRoom(created.payload.room_code)[1];
  assert.equal(server.service.sendPrivate(benSession, { notice: "only-ben" }), true);
  const privateMessage = await ben.next((message) => message.type === "private_message");
  assert.deepEqual(privateMessage.payload, { notice: "only-ben" });
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(ada.messages.some((message) => message.type === "private_message"), false);
  assert.notEqual(joined.payload.session_id, created.payload.session_id);
});

test("invalid and unauthorized commands are rejected without trusting forged identity", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const client = await connectClient(server.websocketUrl);
  t.after(() => client.close());
  client.send("{");
  assert.equal((await client.next()).payload.code, "malformed_message");
  client.clear();
  client.send(command("create_room", "forged", { display_name: "Ada", session_id: "admin" }));
  assert.equal((await client.next()).payload.code, "invalid_message");
  assert.equal(server.service.registry.roomCount(), 0);
});

test("an oversized transport message is closed safely without affecting readiness", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const websocket = new WebSocket(server.websocketUrl);
  await once(websocket, "open");
  const closed = once(websocket, "close");
  websocket.send("x".repeat(MAX_PAYLOAD_BYTES + 1));
  const [code] = await closed;
  assert.equal(code, 1009);
  assert.equal((await fetch(`${server.httpUrl}/healthz`)).status, 200);
});

test("disconnecting one client leaves the room process healthy", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  const ben = await connectClient(server.websocketUrl);
  t.after(() => ada.close());
  const created = await createRoom(ada);
  ben.send(command("join_room", "join-disconnect", { room_code: created.payload.room_code, display_name: "Ben" }));
  await ben.next((message) => message.type === "command_result");
  ada.clear();
  await ben.close();
  const snapshot = await ada.next(
    (message) => message.type === "room_snapshot" && message.payload.player_count === 1,
  );
  assert.deepEqual(snapshot.payload.player_names, ["Ada"]);
  assert.equal((await fetch(`${server.httpUrl}/healthz`)).status, 200);
});

test("rate limiting rejects excess commands and logs contain no private identifiers", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const client = await connectClient(server.websocketUrl);
  t.after(() => client.close());
  const created = await createRoom(client, "Ada", "rate-create");
  client.clear();
  for (let index = 0; index < 19; index += 1) client.send("{");
  client.send(command("create_room", "rate-over-limit", { display_name: "Ben" }));
  const limited = await client.next(
    (message) => message.type === "error" && message.payload.code === "rate_limited",
  );
  assert.equal(limited.payload.code, "rate_limited");
  assert.equal(limited.request_id, "rate-over-limit");
  const logs = JSON.stringify(server.logs);
  assert.equal(logs.includes(created.payload.player_id), false);
  assert.equal(logs.includes(created.payload.session_id), false);
});

test("clean shutdown warns clients and closes the service", async () => {
  const server = await startTestServer();
  const client = await connectClient(server.websocketUrl);
  const warning = client.next((message) => message.type === "server_shutdown");
  await server.service.close();
  assert.deepEqual((await warning).payload, { reason: "service_restart" });
  assert.equal(client.websocket.readyState, client.websocket.CLOSED);
});
