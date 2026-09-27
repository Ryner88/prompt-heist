import assert from "node:assert/strict";
import test from "node:test";
import { MAX_PAYLOAD_BYTES } from "../src/constants.js";
import { decodeClientMessage, recoverRequestId } from "../src/protocol.js";
import { command } from "./helpers.js";

test("accepts valid versioned create and join envelopes", () => {
  assert.equal(
    decodeClientMessage(JSON.stringify(command("create_room", "a", { display_name: "Ada" }))).ok,
    true,
  );
  assert.equal(
    decodeClientMessage(
      JSON.stringify(command("join_room", "b", { room_code: "ABC234", display_name: "Ben" })),
    ).ok,
    true,
  );
});

test("rejects empty, malformed, binary, and oversized messages", () => {
  assert.equal(decodeClientMessage("").response.payload.code, "empty_message");
  assert.equal(decodeClientMessage("{").response.payload.code, "malformed_message");
  assert.equal(decodeClientMessage(Buffer.from("{}"), true).response.payload.code, "unsupported_message_type");
  assert.equal(
    decodeClientMessage(" ".repeat(MAX_PAYLOAD_BYTES)).response.payload.code,
    "malformed_message",
  );
  assert.equal(
    decodeClientMessage("x".repeat(MAX_PAYLOAD_BYTES + 1)).response.payload.code,
    "payload_too_large",
  );
});

test("rejects unsupported versions and commands consistently", () => {
  const old = command("create_room", "old-1", { display_name: "Ada" });
  old.version = 0;
  const versionError = decodeClientMessage(JSON.stringify(old)).response;
  assert.equal(versionError.request_id, "old-1");
  assert.equal(versionError.payload.code, "unsupported_version");

  const commandError = decodeClientMessage(
    JSON.stringify(command("become_host", "bad-1", {})),
  ).response;
  assert.equal(commandError.request_id, "bad-1");
  assert.equal(commandError.payload.code, "unsupported_command");
});

test("rejects non-object envelopes and invalid request identifiers", () => {
  for (const value of ["null", "[]", '"text"']) {
    assert.equal(decodeClientMessage(value).response.payload.code, "invalid_message");
  }
  const invalidId = command("create_room", "valid", { display_name: "Ada" });
  invalidId.request_id = 42;
  const rejected = decodeClientMessage(JSON.stringify(invalidId)).response;
  assert.equal(rejected.request_id, null);
  assert.equal(rejected.payload.code, "invalid_message");
});

test("rejects authoritative and identity fields supplied by a client", () => {
  for (const extra of [
    { player_id: "forged" },
    { session_id: "forged" },
    { max_players: 99 },
    { role: "Informant" },
  ]) {
    const message = command("create_room", "forged-1", { display_name: "Ada", ...extra });
    assert.equal(decodeClientMessage(JSON.stringify(message)).response.payload.code, "invalid_message");
  }
});

test("recovers only a schema-safe request ID for rate-limit correlation", () => {
  assert.equal(recoverRequestId(JSON.stringify({ request_id: "rate-1" })), "rate-1");
  assert.equal(recoverRequestId(JSON.stringify({ request_id: "not safe!" })), null);
  assert.equal(recoverRequestId(JSON.stringify({ request_id: 42 })), null);
  assert.equal(recoverRequestId("{"), null);
  assert.equal(recoverRequestId(Buffer.from("{}"), true), null);
});
