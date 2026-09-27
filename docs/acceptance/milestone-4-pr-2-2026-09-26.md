# Milestone 4 PR 2 Manual Acceptance Record

## Test identity

- Milestone: Milestone 4, PR 2 — Authoritative Room Protocol
- Build or commit: Pre-PR working tree on `milestone-4/authoritative-room-protocol`, based on merge commit `71e48b877498a14eaea1a6062d73bc92ec55bc28`
- Environment: Local WSL 2 and Docker Desktop
- Deployment URL: Not deployed by design; local ephemeral endpoints only
- Tester: Codex, with command output reviewed in the shared workspace
- Date: 2026-09-26 (America/New_York)

## Test platforms

| Browser and version | Operating system | Device | Network conditions |
| --- | --- | --- | --- |
| Node.js `ws` 8.22.0, two independent clients | WSL 2 on Windows | Local development workstation | Localhost, uninterrupted |
| HTTP client (`curl`) | Docker Desktop Linux container on Windows | Local development workstation | Published localhost container port |

Browser/device verification is deferred to PR 3 because this slice intentionally contains no browser UI or Godot network client.

## Preconditions and test data

- Node.js 24.15.0 for local verification; project minimum and container runtime are Node.js 22.
- Godot 4.7.2 stable for the checked-in headless suites.
- Docker Desktop 29.3.1 with a Linux container engine.
- Fresh in-memory registry for every automated or manual scenario.
- Players `Ada` and `Ben`; generated six-character room code.

## Acceptance results

| ID | Category | Exact steps | Expected result | Actual result | Status | Evidence | Issue |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MT-001 | Manual/integration | Run `npm run verify:manual-protocol`; connect two independent WebSocket clients; create as Ada and join as Ben. | Both clients receive the same two-player public snapshot. | Identical snapshots received. | pass | Command printed `clients=2 shared_snapshot=true`. | None |
| MT-002 | Negative | In the two-client check, send malformed JSON and a join payload with a forged `player_id`. | Both inputs are rejected without changing authoritative state. | `malformed_message` and `invalid_message` returned. | pass | Command printed `malformed_rejected=true forged_rejected=true`. | None |
| MT-003 | Security | Send distinct private notices to the server-owned Ada and Ben connections. | Each notice reaches only its intended client. | Neither client received the other's private notice. | pass | Command printed `private_isolated=true`. | None |
| MT-004 | Recovery | Disconnect one client while another remains, then request `/healthz`. | Remaining room process stays responsive and snapshot removes the disconnected seat. | Integration suite passed. | pass | `disconnecting one client leaves the room process healthy`. | None |
| MT-005 | Regression | Run the checked-in Godot test entry point. | Existing registry tests and complete game-rule regression harness pass. | Registry: 4 cases; game rules: 10 cases. | pass | Godot 4.7.2 headless output. | None |
| MT-006 | Smoke | Launch the Godot project headlessly for two frames. | Project starts without script or scene errors. | Clean exit with no errors. | pass | Godot 4.7.2 headless output. | None |
| MT-007 | Container | Build `prompt-heist-room-service:pr2`, run it on port 18080, call `/healthz`, and inspect Docker health. | Image builds; endpoint returns 200-ready; container becomes healthy. | `{"status":"ready","protocol_version":1}` and Docker `Status: healthy`. | pass | Docker build and health output. | None |
| MT-008 | Dependency security | Run `npm audit`. | No known dependency vulnerabilities. | Zero vulnerabilities reported. | pass | npm audit output. | None |

## Recovery and rollback

- Refresh/disconnect/retry behavior tested: Disconnect cleanup and duplicate-request idempotency are automated. Browser refresh and reconnect grace are deliberately deferred.
- Crash/restart behavior tested: Clean shutdown warns clients and closes connections. All in-memory rooms are expected to disappear after restart.
- Rollback procedure exercised: Container startup and shutdown were exercised. No production deployment exists to roll back in this slice.
- Rollback result and evidence: The temporary container stopped cleanly and was automatically removed. The previous milestone remains represented by merge commit `71e48b8`.

## Findings

- Critical security findings and resolution: Initial dependency installation identified one high and one moderate advisory; `ws` and `ajv` were upgraded to patched versions and the final audit is clean.
- Known non-blocking issues: Render cold starts/restarts erase rooms; no reconnect grace; no browser client; no persistence; no public deployment.
- Blocked tests and reason: Real browsers, mobile devices, external networks, Render TLS, and deployed rollback are outside PR 2's explicit scope.

## Release recommendation

- Recommendation: Ready to open PR 2; do not treat this as a public production release.
- Rationale: The authoritative boundary, security/boundary cases, regressions, two-client isolation check, and local container health gate pass. Deferred browser, reconnect, persistence, and deployment behavior is explicitly documented.
- Tester sign-off: Codex, 2026-09-26
