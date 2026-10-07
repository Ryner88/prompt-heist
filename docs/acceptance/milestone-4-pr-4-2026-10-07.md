# Milestone 4 PR 4: Reconnect and Departures — local acceptance

## Test identity

- Candidate: `milestone-4/reconnect-departures` working tree based on Milestone 4 merge commit `b70ccb61bf4a3fbdd076b6a8bd7259a7e3082460`.
- Date/tester: 2026-10-07, Codex.
- Environment: WSL 2 Linux; Node.js 24.15.0; Godot 4.7.2 stable; Chrome for Testing 147.0.7727.15 via Playwright; local Python HTTP server.
- URLs: `http://127.0.0.1:4173/` for the Web export and `ws://127.0.0.1:3000/ws` for the loopback room authority. No public deployment.
- Browser sessions: independent Chromium contexts at desktop `1280×720` and simulated phone `390×844`. The phone viewport is emulation, not a physical device.

## Preconditions and steps

1. Run `npm ci`, start `node server/src/main.js`, export the Godot Web preset with `--export-release Web builds/web/index.html`, and serve `builds/web` at port 4173.
2. In desktop context Ada, choose Online, enter `Ada`, and create a room. Confirm a one-player lobby and a same-tab session-storage record with a six-character room code and 43-character token. Keep the token value out of screenshots and test output.
3. In independent phone-sized context Ben, choose Online, enter `Ben`, join the code in lowercase, and confirm both lobbies show Ada and Ben at `2 / 4`.
4. Refresh Ada's tab, choose Online, and confirm the same room returns with two players. Compare the stored token before and after refresh without printing it; it must change.
5. Press Leave in Ada's lobby. Confirm the browser storage record is removed and Ben's lobby drops to one player.
6. In a separate browser run, create a room, terminate the local authority with SIGKILL, and confirm the disconnected UI retains recovery data. Restart the authority and press Retry. Confirm the expired/unknown reservation message, connected entry state, and cleared browser storage.

## Results

| Case | Expected and actual result | Status | Evidence |
| --- | --- | --- | --- |
| Create and join | Ada created a room; Ben joined using lowercase code. Both showed room `5HKHML`, Ada then Ben, `2 / 4`. | Pass | [Ada created](evidence/pr-4/pr10-ada-created.png), [Ben joined](evidence/pr-4/pr10-ben-joined.png) |
| Same-tab refresh | Ada returned to the same two-player room. The private stored token rotated; the room code remained equal. Browser console errors were empty. | Pass | [Ada recovered](evidence/pr-4/pr10-ada-recovered.png) |
| Explicit leave | The server acknowledged Leave; Ada's browser storage cleared and Ben's lobby showed one player. | Pass | [Ada left](evidence/pr-4/pr10-ada-left.png), [Ben after leave](evidence/pr-4/pr10-ben-after-leave.png) |
| Authority crash/restart | SIGKILL disconnected the client without clearing its token. After a fresh process started, Retry rejected the old token, cleared storage, and returned to connected entry. Browser console errors were empty. | Pass | [Disconnected](evidence/pr-4/pr10-crash-disconnected.png), [entry after retry](evidence/pr-4/pr10-crash-retry.png) |
| Grace cutoff and contention | Injected-clock Node tests cover `29,999 ms` permitted, `30,000 ms` rejected, reserved full-room capacity, one winner from simultaneous resumes, replay rejection, stale-socket safety, and immediate leave. | Pass | `server/test/reconnect.test.js` |
| Real cross-runtime path | Godot clients connected to the real Node service, resumed with token rotation after transport loss, then left and updated the other member's lobby. | Pass | `tests/network_integration_test.gd` |

## Automated candidate checks

| Command or check | Result |
| --- | --- |
| `npm run test:coverage` | 31/31 Node tests passed; 98.55% lines, 90.69% branches, 98.33% functions. The suite includes legacy protocol tests and new recovery tests. |
| `npm audit --audit-level=high` | Passed; 0 vulnerabilities. |
| Godot 4.7.2 `--headless --path . --script res://tests/run_tests.gd` | 4 registry, 10 game-rule, 6 network-client, and 6 flow cases passed. |
| Real Node service plus Godot `tests/network_integration_test.gd` | Passed create, join, capacity, errors, isolation, privacy, resume, and leave. |
| Godot `--headless --path . --quit-after 2` and `--export-release Web builds/web/index.html` | Passed; HTML, PCK, JavaScript, and WASM generated with no export errors. |
| `actionlint .github/workflows/verify.yml` and `git diff --check` | Passed. |

## Security, recovery, and limits

Public snapshots remained restricted to room code, player names, count, and capacity. Node tests checked that tokens are absent from public snapshots, another client's events, and service logs; the Godot client tests checked that UI-facing signals contain only command and room code. Browser screenshots contain no private token or session ID.

The first browser automation attempt missed a responsive control; a later run had no join result by its fixed wait. The successful run used the correct control positions and passed the full two-browser path. The cause of the delayed join was not isolated, so it is not counted as a product pass or failure. No browser console error was observed. The driver was an untracked temporary local script, and screenshots plus exact interaction steps are retained here.

Physical mobile devices, other browser engines, external networks, deployed HTTPS/WSS, and production restart behavior were not tested. No persistence exists; process restart intentionally invalidates rooms and tokens. Browser storage is same-tab only and requires working `sessionStorage`; a browser that blocks storage cannot recover after refresh. A committed resume whose private result is lost with the connection cannot be retried using the consumed token on another connection. A committed Leave whose result is lost still releases the seat. These are transport ambiguity limits, not observed failures in the browser run. Cross-device recovery is outside this PR.

This is a local waiting-room acceptance record, not a public-release sign-off. The rollback baseline is PR #9's merge commit `b70ccb6`; no deployed rollback was exercised because there is no public deployment.

## Final review addendum

Sourcery's final review identified a stale-socket window: after resume replaced a connection, that socket could claim a new seat before its close completed. The candidate now retires the old WebSocket context before closing it, and the room registry rejects create, join, and resume from the retired connection. `server/test/reconnect.test.js` has a regression case for this window. The earlier browser evidence above predates this fix; no new browser run is claimed by this addendum.

After the fix, `npm run test:coverage` passed 32/32 tests with 98.60% line, 91.12% branch, and 98.33% function coverage. `npm audit --audit-level=high` found zero vulnerabilities. Godot 4.7.2 passed the 4 registry, 10 game-rule, 6 network-client, and 6 flow cases; the real Node↔Godot integration passed; headless launch and Web export passed. `actionlint .github/workflows/verify.yml` and `git diff --check` passed. These local results require CI to run again on the amended PR head before merging.
