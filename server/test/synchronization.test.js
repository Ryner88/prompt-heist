import assert from "node:assert/strict";
import test from "node:test";
import { RoomRegistry } from "../src/room-registry.js";
import { command, connectClient, startTestServer } from "./helpers.js";

test("room revisions advance on authoritative transitions and not on rejected commands", () => {
  let now = 0;
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", clock: () => now });
  const ada = registry.createRoom("Ada", "a", { reconnect: true, sync: true });
  const snapshot = () => registry.publicSnapshot(ada.roomCode, { revision: true });
  assert.equal(snapshot().revision, 1);
  assert.equal(registry.publicSnapshot(ada.roomCode).revision, undefined);
  assert.equal(registry.joinRoom(ada.roomCode, "Ada", "duplicate").code, "duplicate_name");
  assert.equal(snapshot().revision, 1);
  registry.joinRoom(ada.roomCode, "Ben", "b", { sync: true });
  assert.equal(snapshot().revision, 2);
  registry.removeConnection("a");
  assert.equal(snapshot().revision, 3);
  assert.deepEqual(snapshot().player_names, ["Ada", "Ben"]);
  const resumed = registry.resumeRoom(ada.roomCode, ada.reconnectToken, "a2", { sync: true });
  assert.equal(resumed.ok, true);
  assert.equal(snapshot().revision, 4);
  assert.equal(registry.removeConnection("a"), null);
  assert.equal(snapshot().revision, 4);
  registry.leaveRoom("a2");
  assert.equal(snapshot().revision, 5);
  registry.removeConnection("b");
  assert.equal(registry.publicSnapshot(ada.roomCode), null);
  assert.equal(registry.roomCount(), 0);

  const next = registry.createRoom("Cy", "c", { reconnect: true, sync: true });
  registry.removeConnection("c");
  now = 29_999;
  assert.equal(registry.publicSnapshot(next.roomCode, { revision: true }).revision, 2);
  now = 30_000;
  assert.deepEqual(registry.expireReservations(), [next.roomCode]);
  assert.equal(registry.publicSnapshot(next.roomCode), null);
});

test("snapshot capability follows the resumed connection, not the reserved seat", () => {
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234" });
  const created = registry.createRoom("Ada", "original", { reconnect: true, sync: true });
  registry.removeConnection("original");
  const resumed = registry.resumeRoom(created.roomCode, created.reconnectToken, "legacy");
  assert.equal(resumed.ok, true);
  assert.equal(registry.sessionForConnection("legacy").sync, false);
  assert.equal(registry.publicSnapshot(created.roomCode).revision, undefined);
});

test("revisioned members converge while legacy snapshots stay compatible", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  const ben = await connectClient(server.websocketUrl);
  const legacy = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([ada.close(), ben.close(), legacy.close()]));
  ada.send(command("create_room", "create", { display_name: "Ada", reconnect: true, sync: true }));
  const created = await ada.next((message) => message.request_id === "create");
  const code = created.payload.room_code;
  assert.equal((await ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 1)).payload.player_count, 1);
  ben.send(command("join_room", "ben", { room_code: code, display_name: "Ben", reconnect: true, sync: true }));
  await ben.next((message) => message.request_id === "ben");
  const [adaTwo, benTwo] = await Promise.all([
    ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 2),
    ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 2),
  ]);
  assert.deepEqual(adaTwo.payload, benTwo.payload);
  ben.clear();
  ben.send(command("join_room", "ben", { room_code: code, display_name: "Ben", reconnect: true, sync: true }));
  assert.equal((await ben.next((message) => message.request_id === "ben")).type, "command_result");
  assert.equal(server.service.registry.publicSnapshot(code, { revision: true }).revision, 2);
  legacy.send(command("join_room", "legacy", { room_code: code, display_name: "Cy" }));
  await legacy.next((message) => message.request_id === "legacy");
  const [adaThree, benThree, legacyThree] = await Promise.all([
    ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 3),
    ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 3),
    legacy.next((message) => message.type === "room_snapshot" && message.payload.player_count === 3),
  ]);
  assert.deepEqual(adaThree.payload, benThree.payload);
  assert.deepEqual(Object.keys(legacyThree.payload).sort(), ["max_players", "player_count", "player_names", "room_code"]);
  assert.deepEqual(Object.keys(adaThree.payload).sort(), ["max_players", "player_count", "player_names", "revision", "room_code"]);
  assert.equal(JSON.stringify(adaThree).includes(created.payload.reconnect_token), false);
  assert.equal(JSON.stringify(benThree).includes(created.payload.session_id), false);
  await legacy.close();
  const [adaFour, benFour] = await Promise.all([
    ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 4),
    ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 4),
  ]);
  assert.deepEqual(adaFour.payload, benFour.payload);
});

test("periodic authoritative rebroadcast repairs a missed room update", async (t) => {
  const server = await startTestServer({ sweepIntervalMs: 20 });
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  t.after(() => ada.close());
  ada.send(command("create_room", "create", { display_name: "Ada", sync: true }));
  await ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 1);
  ada.clear();
  const repeated = await ada.next((message) => message.type === "room_snapshot" && message.payload.revision === 1, 500);
  assert.deepEqual(repeated.payload.player_names, ["Ada"]);
  assert.equal(server.service.registry.publicSnapshot(repeated.payload.room_code, { revision: true }).revision, 1);
});

test("disconnect, resume, and exact expiry converge on one authoritative revision", async (t) => {
  let now = 0;
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", clock: () => now });
  const server = await startTestServer({ registry, sweepIntervalMs: 20 });
  t.after(() => server.service.close());
  const ada = await connectClient(server.websocketUrl);
  const ben = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([ada.close(), ben.close()]));
  ada.send(command("create_room", "create", { display_name: "Ada", reconnect: true, sync: true }));
  const created = await ada.next((message) => message.request_id === "create");
  const code = created.payload.room_code;
  ben.send(command("join_room", "join", { room_code: code, display_name: "Ben", sync: true }));
  await ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 2);
  await ada.close();
  const reserved = await ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 3);
  assert.deepEqual(reserved.payload.player_names, ["Ada", "Ben"]);
  now = 29_999;
  const resumed = await connectClient(server.websocketUrl);
  t.after(() => resumed.close());
  resumed.send(command("resume_room", "resume", { room_code: code, reconnect_token: created.payload.reconnect_token, sync: true }));
  await resumed.next((message) => message.request_id === "resume");
  const [benRecovered, adaRecovered] = await Promise.all([
    ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 4),
    resumed.next((message) => message.type === "room_snapshot" && message.payload.revision === 4),
  ]);
  assert.deepEqual(benRecovered.payload, adaRecovered.payload);
  await resumed.close();
  await ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 5);
  now = 59_998;
  assert.equal(registry.publicSnapshot(code, { revision: true }).revision, 5);
  now = 59_999;
  const expired = await ben.next((message) => message.type === "room_snapshot" && message.payload.revision === 6, 500);
  assert.deepEqual(expired.payload.player_names, ["Ben"]);
  assert.equal(expired.payload.player_count, 1);
});
