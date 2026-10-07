# Milestone 4 PR 4: Reconnect and Departures

Base: Milestone 4 merge commit `b70ccb61bf4a3fbdd076b6a8bd7259a7e3082460` (PR #9). This PR remains at the authoritative waiting-room boundary.

## Scope and compatibility

- Add an opt-in `reconnect: true` capability to protocol-v1 create/join commands. Legacy clients omit it and retain immediate disconnect cleanup and their four-field result shape. Capable clients receive a private reconnect token in their direct result. No token enters a snapshot, log, UI signal, or room code.
- Add `resume_room` and `leave_room` commands. The server alone maps a token to a reserved seat. Successful resume rotates the token and session ID, atomically binds a new socket, and makes the prior socket stale. Explicit leave invalidates the token and releases the seat immediately.
- A transient close reserves an opted-in seat for 30 seconds. Resume succeeds only when `now < expires_at`; at `now >= expires_at`, the token is invalid and the seat is released. Expiry and room deletion run on an injected clock so boundary tests are deterministic.
- Reserved seats continue to count toward the four-seat cap and remain in the public roster until expiry or explicit leave. Restart discards all process-local rooms and tokens. No persistence is introduced.
- Update the Godot waiting-room client and UI to retain the private token in memory and, for Web builds, same-tab `sessionStorage` across refresh. Attempt resume after an unplanned disconnect or refresh, and offer explicit Leave. The local pass-and-play path remains untouched. The browser token is scoped to its origin and tab; it is cleared on acknowledged leave, invalid resume, or announced authority restart.

## Acceptance criteria and threats

1. Resume succeeds just before expiry; at and after expiry it fails and cleanup frees the seat. An empty room is deleted.
2. A successful resume consumes the previous token and issues a fresh token and session ID. Concurrent resumes yield one winner; replay of either a consumed token or a cached stale response cannot reclaim the seat.
3. Closing or sending from the replaced socket cannot remove, mutate, or receive private data for the resumed seat.
4. Explicit leave removes the seat immediately and invalidates its token. Network loss reserves it until grace expires. A room with four occupied or reserved seats rejects a fifth join.
5. Malformed, cross-room, guessed, and expired tokens fail with safe errors. Tokens never appear in public snapshots, other clients' events, logs, or UI text. Request IDs correlate all direct responses; retrying one command ID on one connection remains idempotent.
6. A server restart invalidates every token and room, and the Godot client returns to a safe create/join state. Legacy clients continue to work with their previous disconnect behavior.

## Test plan

- Registry tests with a fake clock for immediately before, exactly at, and after 30 seconds; reserved capacity; leave; empty-room cleanup; stale connection; token rotation; and concurrent/replayed resume.
- Protocol tests for strict new schemas, forged identity fields, malformed tokens, request ID correlation, privacy allowlists, and legacy compatibility.
- Real WebSocket integration for disconnect/resume, replacement socket races, explicit leave, full rooms, restart, and private data isolation.
- Godot client and flow tests for token privacy, stale responses, reconnect state, leave acknowledgement, and retry failure. Run the real Node ↔ Godot integration.
- Local browser acceptance at desktop and phone viewports: transient interruption and recovery, same-tab refresh recovery, explicit leave, full reserved room, expiry, and authority restart. Record actual environment and limitations without claiming physical-device, cross-browser, TLS, external-network, or production testing.

Networked gameplay, role/sabotage/voting synchronization, host migration, Play Again, and public deployment are outside this PR.
