# Milestone 4 PR 5: Waiting-room synchronization — local acceptance

## Identity and scope

- Candidate: `milestone-4/waiting-room-synchronization`, branched from PR #10 merge commit `59b144bef9d7a5e596faeca58c06f481ce202730`.
- Date/tester: 2026-10-07, Codex. WSL 2 Linux, Node.js 24.15.0, Godot 4.7.2 stable, Chromium 147 via Playwright.
- Local endpoints: `http://127.0.0.1:4173/` Web export and `ws://127.0.0.1:3000/ws` room service. Desktop viewport `1280×720`; emulated phone viewport `390×844`. No physical device or deployment.
- Scope: waiting-room roster revisions and convergence only. No online gameplay, persistence, host migration, or Play Again.

## Automated results

| Command/check | Result |
| --- | --- |
| `npm run test:coverage` | 37/37 Node tests passed; 98.65% lines, 92.04% branches, 98.39% functions. |
| `npm audit --audit-level=high` | Passed; zero vulnerabilities. |
| Godot `--headless --path . --script res://tests/run_tests.gd` | 4 registry, 10 game-rule, 6 network-client, and 6 flow cases passed. |
| Real Node service plus Godot `tests/network_integration_test.gd` | Passed create, join, capacity, errors, isolation, privacy, resume, and leave with revisioned snapshots. |
| Godot `--headless --path . --quit-after 2` | Passed. |
| Godot `--headless --path . --export-release Web builds/web/index.html` | Passed; HTML, PCK, JavaScript, and WASM generated. |
| `actionlint .github/workflows/verify.yml` and `git diff --check` | Passed. |

Injected-clock and real-socket tests cover revision increments, unchanged revisions after rejected/no-op commands, old-client four-field compatibility (including a legacy client resuming an opted-in seat), public payload privacy, exact expiry, disconnect and resume, same-revision rebroadcast, and convergence of two connected clients. Godot tests cover rejection of older, duplicate, cross-room, and malformed snapshots.

## Local browser journey

The test used two independent Chromium contexts. Ada created a room on desktop and Ben joined on the phone-sized viewport using a lowercase code. The public WebSocket frames converged at revision 2 with the same ordered `2 / 4` roster; the screenshots show both views. Ada refreshed, resumed with a rotated private token, and both contexts converged at revision 4 with the same roster. Ada then sent Leave and Ben received revision 5 with only Ben at `1 / 4`. State-based waits observed the public snapshots and browser storage transition; the browser token value was compared in memory and never printed. Page and console error counts were zero.

| Evidence | Result |
| --- | --- |
| [Ada at two players](evidence/pr-5/pr11-ada-two.png), [Ben at two players](evidence/pr-5/pr11-ben-two.png) | Both waiting-room views showed Ada and Ben, `2 / 4`. |
| [Ada after refresh](evidence/pr-5/pr11-ada-recovered.png) | Same room and roster after recovery; private token rotated. |
| [Ben after Ada left](evidence/pr-5/pr11-ben-after-leave.png) | Ben saw one remaining player. |

The temporary browser driver was `/tmp/pr11_browser.js`; it is not a repository test. It observed only public snapshot frames and used local screen coordinates to enter the Godot canvas. The automated Node test covers missed-update repair by periodic rebroadcast; this browser journey did not deliberately drop a frame. Screenshots contain no token or session ID.

## Limits and release gate

The expiry sweep may leave a departed reservation visible for up to one second, and a missed push converges on the next five-second rebroadcast. The browser journey used Chromium only and an emulated phone viewport. Physical mobile devices, other browser engines, external networks, HTTPS/WSS, production load, public deployment, and full multiplayer gameplay remain untested. This is a local waiting-room acceptance record, not production release approval. Rollback to the PR #10 merge commit is available by reverting this isolated slice; no deployed rollback was exercised.
