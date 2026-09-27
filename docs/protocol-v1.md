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

## Server messages

`command_result` is private to the requesting connection and contains the server-generated `player_id` and `session_id`. These values identify the accepted session but cannot be supplied in a client command.

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

Snapshots never contain roles, sabotage choices, votes before reveal, session or reconnect tokens, connection IDs, or server-only game state.

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
