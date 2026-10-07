# ADR 0002: Ephemeral reconnect reservations

- Status: Accepted for Milestone 4 PR 4
- Date: 2026-10-07

## Context

ADR 0001 removes a seat as soon as its WebSocket closes. That is safe but makes a brief network interruption or browser refresh lose the waiting-room place. The room service is still process-local and has no deployed persistent store.

## Decision

- A client explicitly opts into recovery with `reconnect: true` on create or join. A legacy protocol-v1 client keeps the original response shape and immediate disconnect cleanup.
- The server issues a random 256-bit bearer token privately; the room registry stores only its digest and binds it to one room seat. The bounded per-connection response cache retains the direct result for request-ID idempotency until close or eviction. The token is never accepted as a player ID, session ID, room snapshot field, or log field.
- An unplanned close reserves the seat for 30 seconds. The deadline uses an injected monotonic clock; the comparison is strict: `now < expires_at` succeeds, `now >= expires_at` expires the seat.
- A resume rotates both token and session ID and replaces the bound socket atomically. Closing the stale socket cannot remove the replacement.
- The replaced socket is retired immediately and cannot claim another seat before its close completes.
- Explicit `leave_room` immediately releases the seat and invalidates the token. The client waits for acknowledgement before treating leave as complete.
- Godot holds the token in memory; Web builds also use same-tab `sessionStorage` so refresh can recover. The stored token is cleared after acknowledged leave, invalid resume, or announced authority restart. Same-origin script access to browser storage remains a security consideration for later public deployment review.
- Server restart discards all rooms and credentials. No durable persistence, host migration, or gameplay synchronization is introduced.

## Consequences

Reserved seats count toward capacity and remain listed by name during grace. Other members see removal when the deadline passes. A stolen token could take over one waiting-room seat until it is rotated or expires, so the token must remain private, high entropy, and accepted only on a secure public WebSocket endpoint. The existing per-connection rate limit applies to resume attempts. A room code alone cannot resume a seat.

Token rotation makes a committed resume unrecoverable across connections if its direct result is lost before the client receives the replacement token. Allowing the consumed token to recover again would weaken replay protection. Likewise, Leave commits when the server processes the command; an acknowledgement lost in transit cannot undo it. The client presents unanswered commands as uncertain outcomes. Browser refresh recovery depends on available same-tab `sessionStorage`.
