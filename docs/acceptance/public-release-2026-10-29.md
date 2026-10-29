# Public release acceptance, 2026-10-29

## Deployment

The public game is [https://prompt-heist-pni7.onrender.com/](https://prompt-heist-pni7.onrender.com/). Render service `srv-dbhscvflk1mc739rvc20` runs the release branch `Milestone-4-Public-Release-and-Multiplayer-Hardening` as a single Docker Web Service on the Free plan in Virginia. The first deploy, `dep-dbhscvvlk1mc739rvcqg`, went live from merge commit `046543d`. Its health check is `/healthz`, and automatic deploys are set to wait for GitHub CI checks to pass.

The public page returned HTTP 200 over HTTPS. `/healthz` returned `{"status":"ready","protocol_version":2}`. The Godot WebAssembly asset returned HTTP 200 with `application/wasm`. Browser clients connected to `wss://prompt-heist-pni7.onrender.com/ws` and exchanged room and match frames.

## Four-browser match

Four independent Chromium contexts opened the public game: Ada and Ben at 1280×720 desktop size, and Cy and Dee at a 390×844 emulated phone size with touch input. All four joined room `UQJ3WJ` and played through the rendered browser controls. The [desktop lobby](evidence/public-release-2026-10-29/lobby-scrolled-Ada.png) showed the full roster.

| Check | Public result |
| --- | --- |
| Private roles | Ada saw Informant, Ben Mastermind, Cy Inside Agent, and Dee Security Specialist. [Inside Agent phone screen](evidence/public-release-2026-10-29/role-Cy.png). |
| Abilities and sabotage | Ada armed [sabotage](evidence/public-release-2026-10-29/abilities1-Ada.png); Ben privately saw [plan scores](evidence/public-release-2026-10-29/abilities1-Ben.png); Cy privately saw the [hidden complication](evidence/public-release-2026-10-29/abilities1-Cy.png); Dee armed a [suspicion block](evidence/public-release-2026-10-29/abilities1-Dee.png). |
| Three rounds | All four voted Ghost, Drone, then Freight. Each succeeded with scores 85, 79, and 82. The first [resolution](evidence/public-release-2026-10-29/resolution1-Ada.png) explained sabotage's +2 suspicion and the Security Specialist's one-point block. The second [resolution](evidence/public-release-2026-10-29/resolution2-Ada.png) revealed the hidden −8 Drone complication. [Final resolution](evidence/public-release-2026-10-29/resolution3-Ada.png). |
| Reconnect | Cy refreshed during round-two planning, reopened Online, and recovered the same room, seat, Inside Agent role, current round, and spent ability state. [Recovered phone screen](evidence/public-release-2026-10-29/reconnect-recovered-Cy.png). |
| Accusation and recap | The three crew browsers privately accused Ada. The [phone accusation screen](evidence/public-release-2026-10-29/accusation-Cy.png) was readable. The [recap](evidence/public-release-2026-10-29/recap-bottom-Cy.png) showed a 3–0–0–0 tally, the revealed roles, three successful plans, sabotage used, and a Crew win. |
| Play Again | All four used Back to the waiting room; room `UQJ3WJ` and the same roster reopened without refresh. [Waiting room](evidence/public-release-2026-10-29/play-again-lobby-Cy.png). A new match started and dealt fresh roles: Fixer, Driver, Hacker, and Informant. [New role](evidence/public-release-2026-10-29/play-again-new-roles-Cy.png). |

## Invite link and rejected actions

In a separate public room, the desktop Copy invite link button produced `https://prompt-heist-pni7.onrender.com/?room=77QT7T`. A fresh phone-sized browser opened the link with [the code prefilled](evidence/public-release-2026-10-29/prompt-heist-public-invite-prefill.png), entered a name, and [joined the same room](evidence/public-release-2026-10-29/prompt-heist-public-invite-joined.png). Room codes in this record are ephemeral and are not reusable release links.

Direct public WSS checks also received the expected `unknown_room` for an invalid code, `room_full` for a fifth player, and `players_disconnected` when Start was requested after a reconnectable player left and the authority published the disconnected room revision.

## Additional device reports and operating limit

The phone screens above are Chromium touch emulation. The user subsequently reported that checks on a physical phone and in Microsoft Edge passed. The exact flow covered on each device was not specified; these are user-reported results, separate from the independently observed four-browser match above.

Render's Free instance can spin down or restart; rooms live only in process memory, so a restart ends active rooms. The public link can be shared, but players should create a fresh room for each group.
