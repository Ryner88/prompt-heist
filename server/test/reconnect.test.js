import assert from "node:assert/strict";
import test from "node:test";
import { RoomRegistry } from "../src/room-registry.js";
import { command, connectClient, startTestServer } from "./helpers.js";

test("grace cutoff is exclusive and releases reserved seats at the exact deadline", () => {
  let now = 0;
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", clock: () => now });
  const created = registry.createRoom("Ada", "old", { reconnect: true });
  registry.removeConnection("old");
  assert.equal(registry.publicSnapshot("ABC234").player_count, 1);
  now = 29_999;
  const resumed = registry.resumeRoom("ABC234", created.reconnectToken, "new");
  assert.equal(resumed.ok, true);
  assert.equal(resumed.playerId, created.playerId);
  assert.notEqual(resumed.sessionId, created.sessionId);
  assert.notEqual(resumed.reconnectToken, created.reconnectToken);
  assert.equal(registry.resumeRoom("ABC234", created.reconnectToken, "replay").code, "invalid_reconnect");
  assert.equal(registry.removeConnection("old"), null);
  assert.equal(registry.sessionForConnection("new").playerId, created.playerId);
  registry.removeConnection("new");
  now = 59_999;
  assert.equal(registry.resumeRoom("ABC234", resumed.reconnectToken, "boundary").code, "invalid_reconnect");
  assert.equal(registry.publicSnapshot("ABC234"), null);
  assert.equal(registry.roomCount(), 0);
});

test("reserved seats count toward capacity; explicit leave and legacy close release immediately", () => {
  let now = 0;
  const codes = ["ABC234", "DEF234"];
  const registry = new RoomRegistry({ codeGenerator: () => codes.shift(), clock: () => now });
  const ada = registry.createRoom("Ada", "a", { reconnect: true });
  for (const [name, id] of [["Ben", "b"], ["Cy", "c"], ["Dee", "d"]]) {
    registry.joinRoom(ada.roomCode, name, id, { reconnect: true });
  }
  registry.removeConnection("a");
  assert.equal(registry.joinRoom(ada.roomCode, "Eli", "e").code, "room_full");
  const resumed = registry.resumeRoom(ada.roomCode, ada.reconnectToken, "a2");
  assert.equal(registry.leaveRoom("a2").ok, true);
  assert.equal(registry.resumeRoom(ada.roomCode, resumed.reconnectToken, "a3").code, "invalid_reconnect");
  assert.equal(registry.joinRoom(ada.roomCode, "Eli", "e").ok, true);
  registry.removeConnection("e");
  assert.equal(registry.publicSnapshot(ada.roomCode).player_count, 3);
  now = 30_000;
  assert.deepEqual(registry.expireReservations(), []);
});

test("a full room accepts a new seat exactly when a reservation expires", () => {
  let now = 0;
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", clock: () => now });
  const created = registry.createRoom("Ada", "a", { reconnect: true });
  for (const [name, id] of [["Ben", "b"], ["Cy", "c"], ["Dee", "d"]]) {
    registry.joinRoom(created.roomCode, name, id);
  }
  registry.removeConnection("a");
  now = 29_999;
  assert.equal(registry.joinRoom(created.roomCode, "Eli", "e").code, "room_full");
  now = 30_000;
  assert.equal(registry.joinRoom(created.roomCode, "Eli", "e").ok, true);
  assert.deepEqual(registry.publicSnapshot(created.roomCode).player_names, ["Ben", "Cy", "Dee", "Eli"]);
});

test("token is a private bearer credential and survives neither expiry nor authority restart", () => {
  let now = 0;
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", clock: () => now });
  const created = registry.createRoom("Ada", "a", { reconnect: true });
  assert.match(created.reconnectToken, /^[A-Za-z0-9_-]{43}$/);
  assert.deepEqual(Object.keys(created.snapshot).sort(), ["max_players", "player_count", "player_names", "room_code"]);
  assert.equal(JSON.stringify(created.snapshot).includes(created.reconnectToken), false);
  assert.equal(registry.resumeRoom("DEF234", created.reconnectToken, "wrong").code, "invalid_reconnect");
  assert.equal(new RoomRegistry().resumeRoom("ABC234", created.reconnectToken, "after-restart").code, "invalid_reconnect");
  registry.removeConnection("a");
  now = 30_000;
  assert.deepEqual(registry.expireReservations(), ["ABC234"]);
  assert.equal(registry.publicSnapshot("ABC234"), null);
  assert.equal(registry.resumeRoom("ABC234", created.reconnectToken, "late").code, "invalid_reconnect");
});

test("token generation failure preserves the old session and credential", () => {
  let issueCount = 0;
  const originalToken = "A".repeat(43);
  const registry = new RoomRegistry({
    codeGenerator: () => "ABC234",
    tokenGenerator: () => (++issueCount <= 9 ? originalToken : "B".repeat(43)),
  });
  const created = registry.createRoom("Ada", "old", { reconnect: true });
  assert.equal(created.reconnectToken, originalToken);
  assert.equal(registry.resumeRoom("ABC234", originalToken, "new").code, "reconnect_token_unavailable");
  assert.equal(registry.sessionForConnection("old").playerId, created.playerId);
  assert.equal(registry.sessionForConnection("new"), null);
  const recovered = registry.resumeRoom("ABC234", originalToken, "new");
  assert.equal(recovered.ok, true);
  assert.equal(recovered.reconnectToken, "B".repeat(43));
  const unavailable = new RoomRegistry({ codeGenerator: () => "DEF234", tokenGenerator: () => "bad" });
  assert.equal(unavailable.createRoom("Ben", "invalid", { reconnect: true }).code, "reconnect_token_unavailable");
  assert.equal(unavailable.roomCount(), 0);
});

test("a replaced socket cannot claim another seat before its close completes", () => {
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234" });
  const created = registry.createRoom("Ada", "old", { reconnect: true });
  const resumed = registry.resumeRoom(created.roomCode, created.reconnectToken, "replacement");
  assert.equal(resumed.ok, true);
  assert.equal(registry.createRoom("Ghost", "old").code, "connection_already_joined");
  assert.equal(registry.joinRoom(created.roomCode, "Ghost", "old").code, "connection_already_joined");
  assert.equal(registry.resumeRoom(created.roomCode, resumed.reconnectToken, "old").code, "connection_already_joined");
  assert.equal(registry.publicSnapshot(created.roomCode).player_count, 1);
  assert.equal(registry.roomCount(), 1);
  registry.removeConnection("old");
  assert.equal(registry.sessionForConnection("replacement").playerId, created.playerId);
});

test("real sockets rotate credentials and stale close cannot evict a resumed seat", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const old = await connectClient(server.websocketUrl);
  const observer = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([old.close(), observer.close()]));
  old.send(command("create_room", "create", { display_name: "Ada", reconnect: true }));
  const created = await old.next((message) => message.request_id === "create");
  const code = created.payload.room_code;
  const firstToken = created.payload.reconnect_token;
  const staleConnectionId = server.service.registry.connectionIdsForRoom(code)[0];
  observer.send(command("join_room", "join", { room_code: code, display_name: "Ben", reconnect: true }));
  await observer.next((message) => message.request_id === "join");
  const replacement = await connectClient(server.websocketUrl);
  const replay = await connectClient(server.websocketUrl);
  t.after(() => Promise.all([replacement.close(), replay.close()]));
  replacement.send(command("resume_room", "resume", { room_code: code, reconnect_token: firstToken }));
  const resumed = await replacement.next((message) => message.request_id === "resume");
  assert.equal(resumed.type, "command_result");
  assert.notEqual(resumed.payload.reconnect_token, firstToken);
  assert.notEqual(resumed.payload.session_id, created.payload.session_id);
  assert.equal(server.service.sendPrivate(staleConnectionId, { hidden: "stale" }), false);
  replay.send(command("resume_room", "replay", { room_code: code, reconnect_token: firstToken }));
  assert.equal((await replay.next((message) => message.request_id === "replay")).payload.code, "invalid_reconnect");
  await old.close();
  assert.equal(server.service.registry.publicSnapshot(code).player_count, 2);
  assert.equal(JSON.stringify(observer.messages).includes(firstToken), false);
  assert.equal(JSON.stringify(server.logs).includes(firstToken), false);
  replacement.send(command("leave_room", "leave", {}));
  assert.equal((await replacement.next((message) => message.request_id === "leave")).payload.command, "leave_room");
  assert.equal(server.service.registry.publicSnapshot(code).player_count, 1);
  replay.send(command("resume_room", "left", { room_code: code, reconnect_token: resumed.payload.reconnect_token }));
  assert.equal((await replay.next((message) => message.request_id === "left")).payload.code, "invalid_reconnect");
});

test("simultaneous resumes have one winner and cannot leak a private token", async (t) => {
  const server = await startTestServer();
  t.after(() => server.service.close());
  const original = await connectClient(server.websocketUrl);
  t.after(() => original.close());
  original.send(command("create_room", "create", { display_name: "Ada", reconnect: true }));
  const created = await original.next((message) => message.request_id === "create");
  const { room_code: roomCode, reconnect_token: token } = created.payload;
  await original.close();
  const candidates = await Promise.all([connectClient(server.websocketUrl), connectClient(server.websocketUrl)]);
  t.after(() => Promise.all(candidates.map((client) => client.close())));
  candidates[0].send(command("resume_room", "first", { room_code: roomCode, reconnect_token: token }));
  candidates[1].send(command("resume_room", "second", { room_code: roomCode, reconnect_token: token }));
  const results = await Promise.all([
    candidates[0].next((message) => message.request_id === "first"),
    candidates[1].next((message) => message.request_id === "second"),
  ]);
  assert.deepEqual(results.map((message) => message.type).sort(), ["command_result", "error"]);
  assert.equal(results.find((message) => message.type === "error").payload.code, "invalid_reconnect");
  assert.equal(server.service.registry.publicSnapshot(roomCode).player_count, 1);
  const winnerToken = results.find((message) => message.type === "command_result").payload.reconnect_token;
  assert.equal(JSON.stringify(server.logs).includes(winnerToken), false);
  assert.equal(JSON.stringify(candidates.find((client, index) => results[index].type === "error").messages).includes(winnerToken), false);
});
