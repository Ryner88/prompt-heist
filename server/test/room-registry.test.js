import assert from "node:assert/strict";
import test from "node:test";
import {
  generateRoomCode,
  isValidRoomCode,
  RoomRegistry,
} from "../src/room-registry.js";

function sequence(values) {
  let index = 0;
  return () => values[Math.min(index++, values.length - 1)];
}

test("creates and joins a room with server-generated identity", () => {
  const ids = sequence(["player-a", "session-a", "player-b", "session-b"]);
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234", idGenerator: ids });
  const created = registry.createRoom(" Ada ", "connection-a");
  const joined = registry.joinRoom(" abc234 ", "Ben", "connection-b");

  assert.deepEqual(
    { playerId: created.playerId, sessionId: created.sessionId },
    { playerId: "player-a", sessionId: "session-a" },
  );
  assert.equal(joined.ok, true);
  assert.deepEqual(joined.snapshot.player_names, ["Ada", "Ben"]);
});

test("room codes are six valid characters and collisions retry", () => {
  for (let index = 0; index < 100; index += 1) assert.equal(isValidRoomCode(generateRoomCode()), true);
  const registry = new RoomRegistry({ codeGenerator: sequence(["ABC234", "ABC234", "XYZ789"]) });
  assert.equal(registry.createRoom("Ada", "a").roomCode, "ABC234");
  assert.equal(registry.createRoom("Ben", "b").roomCode, "XYZ789");
});

test("enforces normalized duplicate names and four-seat capacity", () => {
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234" });
  registry.createRoom("Ａｄａ", "a");
  assert.equal(registry.joinRoom("ABC234", " ada ", "duplicate").code, "duplicate_name");
  assert.equal(registry.joinRoom("ABC234", "Ben", "b").snapshot.player_count, 2);
  assert.equal(registry.joinRoom("ABC234", "Cy", "c").snapshot.player_count, 3);
  assert.equal(registry.joinRoom("ABC234", "Dee", "d").snapshot.player_count, 4);
  assert.equal(registry.joinRoom("ABC234", "Eli", "e").code, "room_full");
  assert.equal(registry.publicSnapshot("ABC234").player_count, 4);
});

test("handles unknown rooms, invalid names, and isolated rooms", () => {
  const registry = new RoomRegistry({ codeGenerator: sequence(["ABC234", "XYZ789"]) });
  assert.equal(registry.createRoom("", "empty").code, "invalid_name");
  assert.equal(registry.createRoom("A", "invalid").code, "invalid_name");
  assert.equal(registry.createRoom("1234567890123456789", "over").code, "invalid_name");
  assert.equal(registry.joinRoom("ZZZ999", "Ben", "missing").code, "unknown_room");
  const first = registry.createRoom("Ada", "a");
  const second = registry.createRoom("Ben", "b");
  registry.joinRoom(first.roomCode, "Cy", "c");
  assert.deepEqual(registry.publicSnapshot(second.roomCode).player_names, ["Ben"]);
  assert.equal(
    registry.joinRoom(second.roomCode, "Ada Again", "a").code,
    "connection_already_joined",
  );
});

test("public snapshots are an allowlist with no private values", () => {
  const registry = new RoomRegistry({ codeGenerator: () => "ABC234" });
  const created = registry.createRoom("Ada", "connection-secret");
  assert.deepEqual(Object.keys(created.snapshot).sort(), [
    "max_players",
    "player_count",
    "player_names",
    "room_code",
  ]);
  const serialized = JSON.stringify(created.snapshot);
  for (const privateValue of [created.playerId, created.sessionId, "connection-secret"]) {
    assert.equal(serialized.includes(privateValue), false);
  }
});
