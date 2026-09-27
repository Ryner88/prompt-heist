# Milestone 4 PR 3 Manual Acceptance Record

## Test identity

- Milestone: Milestone 4, PR 3 — Browser room flow and synchronized lobby
- Build or commit: Uncommitted `milestone-4/browser-room-flow` working tree based on `b952f571271e7e968c8f7c1fcc4a1acb394df466`; final Web `index.pck` SHA-256 `115b51dee2fa9388e521a8d4ee9328ca2d348c8f4f94f3860d8c9a8ebdb58768`
- Environment: Local WSL 2 development environment on Windows; Node.js 24.15.0; Godot 4.7.2 stable; Web export served by Python's HTTP server
- Deployment URL: `http://127.0.0.1:4173/` for the Web client and `ws://127.0.0.1:3000/ws` for the local authority; no public deployment
- Tester: Codex
- Date: 2026-09-27 (America/New_York)

## Test platforms

| Browser and version | Operating system | Device | Network conditions |
| --- | --- | --- | --- |
| Headless Chrome 152.0.0.0, independent browser sessions A–F | Linux under WSL 2 | Desktop viewport `1280×720` and simulated phone viewport `390×844` | Local loopback, normal service, intentional service stop and restart |

The phone check is viewport emulation, not a physical Android or iPhone test. Cross-browser, physical-device, external-network, and deployed TLS checks remain part of the later public-release gate.

## Preconditions and test data

- Run `npm ci` and `npm start` in the repository.
- Export Godot Web with `godot --headless --path . --export-release Web builds/web/index.html`, then serve that directory over HTTP. The final build was also copied to `F:\prompt-heist-build-cache\web` on the USB; its package checksum matches the local build.
- Use independent browser sessions. Room `K7VB3N` was created by Ada; Ben joined using lowercase input, followed by Cy and Dee. Eli attempted the fifth join. A later phone-sized room was created by Eli with code `VWZ6PE`.
- No accounts or persistent room data are used. Restarting the authority intentionally deletes its rooms.

## Acceptance results

| ID | Category | Exact steps | Expected result | Actual result | Status | Evidence | Issue |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MT-001 | Web smoke | Load the exported HTML over HTTP at desktop and phone viewport sizes; inspect browser errors. | Both render the mode chooser without script errors. | Both rendered; browser error output was empty. | pass | [desktop](evidence/pr-3/final-desktop-smoke.png), [phone](evidence/pr-3/final-phone-smoke.png) | None |
| MT-002 | Create and join | In session A, choose Online, enter `Ada`, create a room. In independent session B, enter `Ben`, type `k7vb3n`, and join. | Both show the same code, names, order, `2 / 4` count, and capacity. | Both showed `K7VB3N`, Ada then Ben, `2 / 4`. Lowercase code was normalized. | pass | [A](evidence/pr-3/lobby-two-player-a.png), [B](evidence/pr-3/lobby-two-player-b.png) | None |
| MT-003 | Capacity | Join Cy and Dee in separate browser sessions; then attempt to join Eli as a fifth player. | Four seats fill in snapshot order; fifth stays in entry with `room_full`; existing room remains at four. | A showed Ada, Ben, Cy, Dee at `4 / 4`; Eli saw a readable full-room error. | pass | [four-player lobby](evidence/pr-3/lobby-four-player-a.png), [fifth rejection](evidence/pr-3/fifth-room-full.png) | None |
| MT-004 | Duplicate name | Have Dee leave to free a seat. In Eli's session, submit ` aDa ` to `K7VB3N`. | Duplicate is rejected after case and surrounding-space normalization; other players stay connected. | Entry showed “That name is already in the room.” | pass | [duplicate rejection](evidence/pr-3/duplicate-name.png), [remaining lobby](evidence/pr-3/lobby-after-leave.png) | None |
| MT-005 | Invalid and unknown codes | With a valid name, enter ambiguous code `O12345`; then use syntactically valid `ZZZ999` and submit. | Invalid code keeps Join disabled; unknown code gives a safe not-found message. | Both behaved as expected; no raw protocol payload appeared. | pass | [invalid code](evidence/pr-3/phone-invalid-code.png), [unknown room](evidence/pr-3/unknown-room.png) | None |
| MT-006 | Recovery | While Eli was in a lobby, stop the Node process with SIGINT; inspect the browser. Restart Node and return to Online entry. | Identity and lobby clear; user sees a safe disconnected notice; service can be retried. | Phone UI showed a wrapped restart/disconnect notice and retry/back controls; after restart, connected entry returned. | pass | [disconnected](evidence/pr-3/phone-disconnected-responsive.png), [connected entry](evidence/pr-3/phone-retry-entry.png) | None |
| MT-007 | Responsive layout | At `390×844`, inspect mode chooser, entry, lobby, invalid-code notice, and disconnected state. At `1280×720`, inspect chooser and two-player lobby. | Controls and messages are legible without horizontal clipping. | Final stretch and wrapping changes rendered the checked screens legibly. | pass | [phone entry](evidence/pr-3/phone-entry-responsive.png), [phone lobby](evidence/pr-3/phone-lobby-responsive.png), [desktop](evidence/pr-3/desktop-mode-responsive.png) | None |
| MT-008 | Local regression journey | Choose Local pass-and-play, add Al, Cy, Bo, Dee; reveal and hide all four roles; complete three planning and private-vote rounds; cast three accusations. | Existing four-player mission reaches a final recap. | Three rounds resolved and final Informant-win recap rendered with roles, results, and accusation data. | pass | [local lobby](evidence/pr-3/local-four-player-lobby.png), [private reveal](evidence/pr-3/local-private-role.png), [final recap](evidence/pr-3/local-four-player-complete.png) | None |
| MT-009 | Security/privacy | Inspect public lobby screenshots, browser errors, service logs, and client logging code; run the real-service privacy integration test. | No session identity, private payload, role, or internal connection ID reaches a public lobby or log; one client's private data does not reach another. | Public lobbies displayed only code, names, count, and capacity; browser errors were empty; service logs contained connection counts only; integration privacy assertion passed. | pass | [public lobby](evidence/pr-3/lobby-two-player-a.png), `tests/network_integration_test.gd`, `scripts/room_network_client.gd` | None |
| MT-010 | Automated release gate | Run Godot suites, real-service Godot integration, headless launch, Web export, Node coverage suite, `npm audit`, and `git diff --check`. | All checks pass. | Godot: 4 registry, 10 game-rule, 5 client, 5 flow cases; real integration passed; 23 Node tests passed; Node coverage 98.14% lines and 90.73% branches; zero audit vulnerabilities; export, launch, and diff check passed. | pass | Local command output; CI retains Node coverage and Godot test reports when run on the PR. | None |
| MT-011 | CI configuration | Verify the downloaded official actionlint 1.7.12 archive against its published SHA-256; run actionlint on `.github/workflows/verify.yml`. | Workflow syntax and expressions validate. | Checksum matched and actionlint exited cleanly. | pass | Local command output. | None |
| MT-012 | Copy control | Create a room in the final phone-sized Web build, press Copy room code, leave, reconnect, and paste into the room-code field with Ctrl+V. | The same six-character code appears after a normal browser paste. | Room `R2R2Z6` was copied and pasted into the entry field. Programmatic clipboard read was denied, but user-initiated paste confirmed the value. | pass | [final phone lobby](evidence/pr-3/final-phone-lobby.png), [copy feedback](evidence/pr-3/final-phone-copy-code.png), [pasted code](evidence/pr-3/phone-code-paste.png) | None |

## Critical-path coverage review

Godot does not provide a native line/branch coverage report for these GDScript suites. The focused assertions are checked into `tests/room_network_client_test.gd` and `tests/multiplayer_flow_test.gd`; CI retains their execution report. The review below identifies the security and state branches covered by those tests and the real-service integration test, rather than treating the Node percentage as proof of Godot coverage.

| Critical path | Exercised cases |
| --- | --- |
| Session privacy | Identity stored only after correlated success, omitted from UI-facing signal and public snapshots, never printed, and cleared on disconnect or valid shutdown; another client's session value absent from received events. |
| Response correlation | Unique safe request IDs, unmatched success ignored, matched success accepted, malformed matched success rejected and pending released, correlated errors resolved, null-ID errors do not resolve pending. |
| Stale-event rejection | A prior connection generation's response is ignored; different-room and malformed snapshots are rejected; snapshots with a null request ID are accepted only with the public schema. |
| UI state transitions | Disconnected → Connecting → Entry → Submitting → Lobby → Disconnected, double-submit rejection, authoritative snapshot progression from one to four seats, fifth join without snapshot change, retry/back after disconnect. |
| Endpoint security | Loopback `ws`, production `wss`, missing host, invalid port, lookalike loopback host, malformed shutdown, extra envelope fields, and invalid room-code/name boundaries. |

## Recovery and rollback

- Refresh/disconnect/retry behavior tested: Disconnect and server restart clear room identity; the user can return to entry. Refresh loses the in-memory session by design; reconnect recovery is PR 4 scope.
- Crash/restart behavior tested: Graceful SIGINT was exercised; the browser showed the shutdown/disconnect state and a new connection worked after restart. A process crash and deployed restart were not simulated in this local slice.
- Rollback procedure exercised: Checked out the exact PR 2 merge commit `b952f57` in an isolated temporary worktree and ran its Godot regression entry point.
- Rollback result and evidence: Four registry tests and ten game-rule regressions passed at the rollback commit. No production deployment exists to roll back.

## Findings

- Critical security findings and resolution: The endpoint parser initially accepted lookalike `127.*` hosts; it now requires a numeric loopback address and has regression tests. The Godot close handshake initially failed to remove a seat promptly; continued polling fixed it, and the real-service disconnect assertion passes.
- Known non-blocking issues: Rooms are ephemeral and have no reconnect grace. The local mission recap can extend below a `1280×720` viewport; the terminal result was visible, but replay-button accessibility was not part of this PR's acceptance journey. Network gameplay remains deferred.
- Blocked tests and reason: Physical mobile devices, Safari/Firefox/Edge, external network, production TLS, and deployed rollback cannot be exercised without the later deployment slice. GitHub CI remains to be observed when the PR is opened.

## Release recommendation

- Recommendation: Ready for PR review once CI passes; not a public production release.
- Rationale: Browser room synchronization, capacity and negative paths, privacy checks, local-game regression journey, Godot/Node integration, Web export, dependency audit, and local rollback baseline passed. Public deployment and reconnect are separate slices.
- Tester sign-off: Codex, 2026-09-27
