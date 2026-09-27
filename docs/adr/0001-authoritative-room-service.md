# ADR 0001: Node.js WebSocket Room Authority on Render

- Status: Accepted
- Date: 2026-09-26

## Context

The existing Godot prototype owns all state in one pass-and-play client. Multiplayer needs a single trusted process that validates commands, owns rooms and player identity, separates public and private data, and is reachable by a Godot Web export.

This slice needs a small transport boundary without moving gameplay rules or committing to persistent infrastructure. The initial service is expected to be inexpensive to operate while the protocol and browser flow are still being developed.

## Decision

- Godot remains the game client.
- A Node.js 22 service using the `ws` library is the sole authority for room membership in this slice.
- Clients connect at `/ws`; readiness is reported at `/healthz` on the same public port.
- Every client command uses a versioned JSON envelope and an explicit JSON Schema. Payload objects reject unknown properties so clients cannot inject player IDs, session IDs, roles, capacity, or other authoritative fields.
- The service creates player and session IDs with cryptographically random UUIDs and binds each session to the accepting WebSocket connection.
- State-changing commands use a client-generated `request_id`. A bounded per-connection response cache makes retries idempotent.
- Public room snapshots are constructed from an allowlist. Private delivery targets one server-owned connection ID and is not expressible by a client command.
- Rooms are process-local and intentionally ephemeral. Disconnecting removes the seat; an empty room is deleted.
- The initial hosting target is one Render Free web service running the repository Dockerfile. Deployment itself remains outside PR 2.

## Why Node.js, WebSocket, and Render

Node provides a small event-driven service, mature JSON tooling, a maintained WebSocket implementation, and fast built-in test execution. A persistent WebSocket gives the server one authoritative connection identity and supports later state broadcasts without HTTP polling. Godot supports WebSocket clients in desktop and Web exports.

Render web services accept public WebSocket connections, expose one public port, and provide managed TLS. Public clients must use `wss://`; Render terminates TLS before forwarding traffic to the service. See [Render WebSockets](https://render.com/docs/websocket) and [Render web services](https://render.com/docs/web-services).

## Operational limitations

Render Free is suitable for this development milestone, not a production availability guarantee:

- A free service spins down after 15 minutes with no inbound HTTP requests or WebSocket messages. Inbound messages on an existing WebSocket now count as activity. A new HTTP request or WebSocket connection wakes the service and can incur a cold start.
- Render can restart a free service at any time. Deploys and instance replacement also terminate open WebSocket connections.
- The filesystem is ephemeral. This service deliberately has no persistence, so every restart loses all rooms and sessions.
- Clients must treat disconnects as expected, show a recoverable error, and later use bounded exponential-backoff reconnect behavior. Reconnect grace and durable recovery are deferred to their planned slice.
- A single process is required while rooms live in memory. Horizontal scaling would require a shared room/session store and cross-instance messaging.

These constraints are documented by [Render's Free service limitations](https://render.com/docs/free), [WebSocket lifecycle guidance](https://render.com/docs/websocket), and the [February 2026 WebSocket idle-activity change](https://render.com/changelog/free-web-services-now-remain-active-while-receiving-websocket-messages).

## Security consequences

- TLS is supplied at Render's edge; local development uses plain `ws://` and HTTP.
- The server applies an 8 KiB message limit, strict schemas, a fixed-window per-connection command limit, and non-secret structured logs.
- Room codes are locators rather than authentication. Guessing resistance, origin policy, distributed rate limiting, reconnect-token design, and abuse controls remain required before public release.
- Session IDs are returned only to their owning connection. They are not accepted as client authority in this slice and never appear in snapshots or logs.

## Deferred work

Browser UI, gameplay synchronization, persistent rooms, reconnect grace, host migration, Play Again, and public production deployment are deliberately excluded.
