# Milestone 4 PR 5: Waiting-room synchronization

Base: Milestone 4 merge commit `59b144bef9d7a5e596faeca58c06f481ce202730` (PR #10). This slice remains limited to the waiting room.

## Scope and acceptance

- The Node room registry owns an integer revision for each room. Create, join, explicit leave, disconnect, resume, and reservation expiry advance it exactly once when the public roster changes. A no-op and a duplicate request do not advance it.
- A client can opt into revisioned snapshots without changing the four-field snapshot shape received by existing protocol-v1 clients. The Godot Web client opts in; public snapshots add only `revision` and never contain player/session IDs or reconnect credentials.
- Every connected member receives the same latest revision, names, count, and capacity after a supported transition. Reconnect receives the current authoritative state even if updates were missed while offline.
- The Godot client rejects same-room snapshots older than its accepted revision and ignores duplicates. An explicit server refresh provides recovery if an update is missed without a disconnect; a bounded periodic refresh ensures convergence even if no later roster change occurs.
- A reservation expires at `now >= expires_at`. The server removes it before returning a fresh snapshot or admitting a new member. Active members receive the corrected roster promptly. No client calculates authoritative membership or capacity.

## Threat and failure cases

- Reordered or duplicated snapshots must not roll a lobby back. Cross-room, malformed, privately enriched, or future-protocol messages must be rejected.
- A replaced socket cannot request refresh or claim another seat. A disconnected client cannot use a room code to read a roster; only its bound server session can refresh.
- A token replay, server restart, or expired reservation cannot revive an old roster. A refresh sent during a transition returns a coherent room revision.
- Failed or delayed refresh responses must not leave the UI in a permanent pending state or leak an identity. Existing reconnect and Leave semantics remain in force.

## Verification plan

- Injected-clock registry tests for one revision per transition, no-op behavior, exact expiry, and capacity at the cutoff.
- Node WebSocket tests with two or more clients for join/leave/disconnect/resume/expiry convergence, refresh authorization, duplicate request idempotency, and public payload privacy.
- Godot client and flow tests for out-of-order, duplicate, cross-room, malformed, and missed snapshots, plus a real Node↔Godot integration run.
- Headless Godot suites and launch, Web export, Node coverage gates, npm audit, workflow lint, and `git diff --check`.
- Local two-browser acceptance using state-based waits: verify matching roster and revision after each transition, a missed-update recovery path, and no private identifiers in UI or public events. Record browser, viewport, steps, timing, and any incomplete run. Physical-device, cross-browser, external-network, TLS, and deployment checks remain separate release gates.

Gameplay synchronization, host migration, persistence, Play Again, and public deployment are outside this PR.
