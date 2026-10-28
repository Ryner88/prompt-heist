# Milestone 4 browser acceptance, 2026-10-28

## Environment and scope

- Baseline: merged milestone 4 branch at `2fb0860` (PR #13), with its CI Web artifact from run `40772842456`.
- Fix under review: `fix/scrollable-game-content`, exported locally with Godot 4.7.2 after the recap clipping was found.
- Local services: Godot Web build at `http://127.0.0.1:8000/` and room authority at `ws://127.0.0.1:3000/ws`.
- Chromium headless sessions at 1280×720, plus a 390×844 emulated phone viewport. Each session had independent browser storage. Screen actions were real canvas clicks through Playwright.
- This is local browser evidence. It does not cover a physical phone, another browser engine, HTTPS/WSS, a public deployment, or production load.

The game requires at least three players to start. Ada and Ben exercised the requested create/join path; Cy was a third independent browser session so a complete cooperative match could run. Dee and Eli were later used to check room capacity.

## Observed flow

| Check | Result | Evidence |
| --- | --- | --- |
| Create/join and start threshold | Ada created `VC6MVM`; Ben joined and both showed the same 2/4 roster. Start stayed disabled until Cy joined, then the room showed 3/4 and Start enabled. | Browser screenshots observed during the run. |
| Rejected joins | A duplicate `Ada` name showed a specific error. A valid but unknown room code showed a readable phone-sized error. Eli was rejected when four seats were occupied. | [Unknown room](evidence/milestone-4-browser-2026-10-28/unknown-room-phone.png), [full room](evidence/milestone-4-browser-2026-10-28/room-full.png). |
| Recovery | Ben refreshed during role reveal. Ada saw Ben as reconnecting, then Ben reentered the same match with his original private role. A later reservation allowed to expire showed the expected expired-seat message and could join again as a new seat. | [Reconnecting](evidence/milestone-4-browser-2026-10-28/reconnecting-seat.png), [recovered role](evidence/milestone-4-browser-2026-10-28/role-recovered.png). |
| Rejected Start | With Cy disconnected, Ben's Start request was rejected with “Everyone must be connected before the heist can start.” The button returned to its enabled “Start heist” state without another room update. | [Rejected Start](evidence/milestone-4-browser-2026-10-28/rejected-start-restored.png). |
| Complete match | Three independent browsers advanced through private roles, briefing, three planning/voting/resolution rounds, and the final result. The selected plans scored 85, 88, and 84; the cooperative outcome was “EVERYONE WINS.” A second complete match assigned fresh roles. | [Recap](evidence/milestone-4-browser-2026-10-28/recap-scrollable.png). |
| Play Again | All three surviving players selected “Back to the waiting room” in the second match. They returned to the same room and roster with Start available, without a refresh at this step. | [Three-player waiting room](evidence/milestone-4-browser-2026-10-28/play-again-three-players.png). |
| Phone entry | Title, mode selection, Create/Join fields, validation, and room errors remained legible at 390×844. | [Phone entry](evidence/milestone-4-browser-2026-10-28/entry-phone.png). |

## Issue found and fix

At 1280×720, the original recap exceeded the canvas height and placed “Back to the waiting room” off-screen. The original `content` container had no scrolling. [Before the fix](evidence/milestone-4-browser-2026-10-28/recap-clipped-before-fix.png), the button was unreachable by a normal click. The fix wraps the game content in a `ScrollContainer` that expands with the viewport and follows focused controls. After a local Web re-export, the recap scrolled to the control, and the complete Play Again flow passed.

## Remaining product checks

- The online screens show the current phase, waiting players, results, and final outcome. There is no dedicated in-game guide covering every role, the three-round sequence, sabotage, and win conditions.
- Six specialist role descriptions promise once-per-match abilities, but `server/src/match-engine.js` only uses those strings for role assignment and display. The online engine has no specialist-ability action. Informant sabotage is implemented. The release instructions must resolve this discrepancy before claiming those abilities are playable.
- The repository has no cover/thumbnail asset, submission blurb, or public game URL. GitHub Pages is not configured and the repository has no deployment records as of this check.
