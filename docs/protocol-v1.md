# Prompt Heist Room Protocol v1

## Transport

- WebSocket endpoint: `/ws`
- Health endpoint: `GET /healthz`
- Text messages only; each message is one JSON object.
- Maximum encoded message size: 8 KiB.
- The current per-connection limit is 20 commands per 10-second window.

Production and every non-loopback client must use secure WebSockets (`wss`). Unencrypted transport is allowed only for loopback-only local development and tests.

## Envelope

```json
{
  "version": 1,
  "type": "join_room",
  "request_id": "client-generated-id",
  "payload": {}
}
```

`request_id` is required on commands, is limited to 128 safe ASCII characters, and is echoed by direct command responses. Retrying a state-changing command with the same ID on the same connection returns the cached result without applying the command again. Unsolicited broadcasts use `null`.

Unknown envelope or payload properties are rejected.

## Client commands

### `create_room`

```json
{"version":1,"type":"create_room","request_id":"c1","payload":{"display_name":"Ada"}}
```

### `join_room`

```json
{"version":1,"type":"join_room","request_id":"j1","payload":{"room_code":"ABC234","display_name":"Ben"}}
```

Names are Unicode NFKC-normalized, trimmed, 2–18 Unicode characters, and unique after case normalization. Room codes contain six characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Rooms contain at most four players.

Clients that support recovery add `"reconnect":true` to the payload of `create_room` or `join_room`. The field is optional to preserve older protocol-v1 clients. A capable client receives a `reconnect_token` in its direct `command_result` alongside the existing fields. Older clients receive the original four-field result and their seats are removed immediately on disconnect.

Clients that support ordered waiting-room updates add `"sync":true` to `create_room` or `join_room` and, when resuming, to `resume_room`. This opt-in is independent of `reconnect`. It changes only the public `room_snapshot` shape sent to that client; existing protocol-v1 clients continue receiving the four public fields below.

### `resume_room`

```json
{"version":1,"type":"resume_room","request_id":"r1","payload":{"room_code":"ABC234","reconnect_token":"43-character-private-base64url-token"}}
```

The token is a 32-byte cryptographically random bearer credential encoded as 43 URL-safe characters. The room registry stores its SHA-256 digest. The bounded, private per-connection response cache retains the direct result (including the token) for request-ID idempotency until that connection closes or the entry is evicted. A successful resume atomically consumes the old token, rotates the token and `session_id`, and binds the existing `player_id` and seat to the new connection. The response is a private `command_result` with the new token. A stale socket cannot remove or control the replacement session, including by claiming another seat while its close is pending.

If the connection is lost after the server commits a resume but before the client receives the new token, the old token cannot be used on another connection. The seat remains reserved for its normal grace period after the replacement socket closes, then expires. This favors immediate replay protection over recovery from an ambiguous lost reply; the client must not claim recovery succeeded without receiving the direct result. A retry with the same request ID on the *same live connection* can return the cached result. Cross-connection retry of a consumed token is intentionally rejected.

An opted-in seat remains reserved for two minutes after an unplanned disconnect. Resume is permitted only while `now < expires_at`; at `now >= expires_at`, the token is rejected and the seat is released. Reserved seats still count toward the four-player capacity and appear in the public roster until expiry. The service uses a monotonic clock, sweeps expired seats, and checks expiry before processing commands. A process restart loses all rooms and tokens.

### `leave_room`

```json
{"version":1,"type":"leave_room","request_id":"l1","payload":{}}
```

The bound connection alone can leave its current room. The direct result contains `{"command":"leave_room","room_code":"ABC234"}`. Processing Leave immediately removes the seat and invalidates its token; other members receive the updated public snapshot. If the connection closes before the server processes Leave, normal grace semantics apply. If the server processes Leave but its result is lost, the seat is already gone. WebSocket delivery cannot prove that a client received an acknowledgement, so clients must treat an unanswered Leave as an unknown outcome until they reconnect or the reservation expires.

Clients that can play online heists add `"game":true` to `create_room`, `join_room`, and `resume_room`. Only game-capable connections receive `match_snapshot` and `match_private`, and a match starts only when every seat is game-capable.

### Heist commands

Every heist command is answered with a private `command_result` whose payload is exactly `{"command":"<type>","room_code":"ABC234"}`. The acting seat is always the one bound to the sending connection; no command can name another player.

```json
{"version":1,"type":"start_match","request_id":"s1","payload":{}}
{"version":1,"type":"ready","request_id":"r1","payload":{"phase":"role_reveal","round":1}}
{"version":1,"type":"cast_vote","request_id":"v1","payload":{"round":1,"plan_id":"ghost"}}
{"version":1,"type":"cast_vote","request_id":"v2","payload":{"round":1,"plan_id":"ghost","sabotage":true}}
{"version":1,"type":"accuse","request_id":"a1","payload":{"suspect_seat":2}}
```

- `start_match` normally requires three or four seats, all connected and game-capable, and no heist in play or recap open in the room. Any seated member may start. A client can explicitly send `{"drop_disconnected":true}` to remove reserved disconnected seats before starting, provided at least three game-capable players remain connected. This invalidates the removed seats' recovery tokens. Three seats play cooperatively; four seats include one hidden Informant.
- `ready` acknowledges one pacing step: `role_reveal`, `briefing`, `planning`, or `resolution`. The step advances when every seat is ready. Repeating readiness for the current step is accepted without change.
- `ready` with phase `finished` asks to leave the recap (Play Again). When every seat still in the room has asked, the match becomes `closed`: the recap and all private match state are cleared, and the room accepts joins and a new `start_match` with the same room code and seats. Seats that left after the recap do not block the return.
- `cast_vote` is accepted once per seat per round. `sabotage:true` is accepted only from the Informant, once per match, together with that seat's vote. The round resolves when every seat has voted.
- `accuse` is accepted once per crew seat during the accusation. The Informant cannot vote and no seat can accuse itself. The match finishes when every crew seat has voted; a tie identifies nobody.
- Every action names its phase or round. An action for a step that has already passed is rejected with `stale_action` and changes nothing.

## Server messages

`command_result` is private to the requesting connection and contains the server-generated `player_id` and `session_id` for create, join, and resume. These values identify the accepted session but cannot be supplied in a client command. Capable clients also receive `reconnect_token`; it must remain private and is never a public snapshot field.

```json
{
  "version": 1,
  "type": "command_result",
  "request_id": "c1",
  "payload": {
    "command": "create_room",
    "room_code": "ABC234",
    "player_id": "server-generated-uuid",
    "session_id": "server-generated-uuid"
  }
}
```

`room_snapshot` is broadcast to current room members. Its payload is allowlisted to exactly these public fields:

```json
{
  "room_code": "ABC234",
  "player_names": ["Ada", "Ben"],
  "player_count": 2,
  "max_players": 4
}
```

For a client using `"sync":true`, the same snapshot also contains `"revision":1` (a positive integer). The room service increments the revision on create, join, leave, disconnect, resume, and reservation expiry; rejected or duplicate commands do not change it. A client accepts only a snapshot for its active room with a revision greater than the last one it accepted on that connection. Revisions restart with a newly created room and must not be treated as identity or authorization. After a client resumes, the service sends the current full roster. It also rebroadcasts each occupied room's current snapshot every five seconds, allowing a connected client to recover a missed update without inventing room state. Expired seats are swept before the periodic rebroadcast; the maximum normal expiry-display lag is one second.

Clients that additionally send `"presence":true` with create, join, or resume receive a `"connected"` array of booleans alongside the revision. It aligns with `player_names` and updates on disconnect, resume, and removal. Clients without this capability keep the previous snapshot shape. The waiting room uses the array to identify an offline player and offer an explicit start with three connected players.

Room snapshots never contain roles, sabotage choices, votes before reveal, session or reconnect tokens, connection IDs, or server-only game state.

`match_snapshot` is broadcast to every game-capable member. Every member receives the same payload. It contains `room_code`, `revision`, `phase`, `mode` (`cooperative` or `social`), `round`, `total_rounds`, `meters`, `mission`, the current round's `plans` (without hidden success values), `seats`, `progress`, `last_result`, `outcome`, and `notice`. Seats are `{seat, name, connected, ready, acted}` in fixed match order; `acted` reports votes during voting only. During the accusation only the aggregate `progress` count is published, because a per-seat flag would identify the non-voting Informant. `outcome`, with revealed roles, round history, and accusation totals, is present only when `phase` is `finished`. When a seat is permanently lost before the end, `phase` becomes `abandoned`, `notice` explains who left, roles stay hidden, and the room accepts joins and a new start again. After everyone returns from the recap, `phase` becomes `closed` with a `notice` and no outcome. Clients treat both `abandoned` and `closed` as a return to the waiting room. During the recap, `ready` and `progress` report the return to the waiting room, counting only seats still in the room. `tests/fixtures/match_contract.json` contains real examples of every phase.

`match_private` is sent only to the seat's own bound connection: `room_code`, `revision`, `seat`, `role`, `ability`, `sabotage_available`, and that seat's own `vote` and `accusation` for the current step.

Both messages share one per-room match `revision`. It increases on every accepted change, including a seat disconnecting or resuming during a match, and keeps increasing across matches in the same room. Clients accept only a strictly newer revision for their active room. The service sends both messages immediately after a change, after a resume, and in the five-second rebroadcast.

`private_message` is a server-internal delivery primitive addressed using the connection bound to a server-owned session. No client command can select its recipient.

`server_shutdown` warns connected clients before a clean service restart. Clients must still handle an unannounced disconnect.

## Error codes

Errors use the versioned envelope and echo a valid request ID when available:

```json
{"version":1,"type":"error","request_id":"j1","payload":{"code":"unknown_room"}}
```

| Code | Meaning |
| --- | --- |
| `empty_message` | The WebSocket message contains zero bytes. |
| `payload_too_large` | The message exceeds 8 KiB. The transport may close the connection before an error envelope can be sent. |
| `unsupported_message_type` | A binary WebSocket message was sent. |
| `malformed_message` | The text is not valid JSON. |
| `invalid_message` | The envelope or command payload fails its schema. |
| `unsupported_version` | `version` is not `1`. |
| `unsupported_command` | `type` is not a supported client command. |
| `invalid_name` | The normalized name is outside 2–18 characters. |
| `unknown_room` | The normalized room code does not identify a current room. |
| `duplicate_name` | The normalized name already exists in the room. |
| `room_full` | The room already has four seats. |
| `room_code_unavailable` | Secure room-code generation exhausted its collision retries. |
| `connection_already_joined` | This connection already owns a room session. |
| `rate_limited` | The connection exceeded the command window. |
| `invalid_reconnect` | The token is invalid, expired, consumed, or belongs to another room. |
| `not_in_room` | The connection has no seat to leave. |
| `reconnect_token_unavailable` | Secure token generation exhausted its collision retries; no session change was applied. |
| `match_in_progress` | A heist is in play or its recap is open; joins and a second start are rejected. |
| `not_enough_players` | Fewer than three seats are present. |
| `players_disconnected` | A seat is reserved but not connected, so the heist cannot start. |
| `incompatible_client` | A seat did not negotiate `game:true`. |
| `no_active_match` | There is no unfinished heist to act in. |
| `not_in_match` | The caller's seat is not part of the room's heist. |
| `stale_action` | The action targets a phase or round that is not current. |
| `already_acted` | The seat has already voted or accused in this step. |
| `invalid_plan` | The plan is not offered this round. |
| `sabotage_unavailable` | The caller is not the Informant or has already sabotaged. |
| `not_eligible` | The Informant cannot vote in the accusation. |
| `invalid_suspect` | The suspect seat is the caller or outside the match. |
