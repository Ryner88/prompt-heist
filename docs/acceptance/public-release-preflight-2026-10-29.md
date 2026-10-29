# Public release preflight, 2026-10-29

## Scope

The four-player browser run used the CI Web export from release commit `b72179d` (Verify run `40783422273`) and the local Node authority at `http://127.0.0.1:3000/` and `ws://127.0.0.1:3000/ws`. Four independent Chromium contexts represented Ada and Ben at 1280×720 and Cy and Dee at a 390×844 emulated phone viewport with touch input. This is a local check, not a public HTTPS/WSS or physical-device acceptance result.

## Observed results

| Check | Result |
| --- | --- |
| Create and join | Pass. All four contexts showed room `WW64US`, the same four names, and revision 4. [Phone lobby](evidence/public-release-preflight-2026-10-29/lobby-Cy.png). |
| Private roles | Pass. Ada was Fixer, Ben Security Specialist, Cy Informant, and Dee Hacker. Each browser's `match_private` frame carried only its own role. [Phone role](evidence/public-release-preflight-2026-10-29/role-Cy.png). |
| Abilities and sabotage | Pass for the roles present. Fixer restored one resource, Security Specialist blocked one suspicion, Hacker lowered Spoof risk from 2 to 1, and Informant armed sabotage. Round 1 resolved Spoof at score 92 and suspicion 1, with the effects explained publicly after resolution. [Resolution](evidence/public-release-preflight-2026-10-29/resolution-1-Ada.png). |
| Three rounds and hidden complication | Pass for the outcome. Spoof, Drone, and Freight succeeded with scores 92, 87, and 74. Freight's randomly assigned hidden complication lowered its score by eight. An Inside Agent private reveal was not visually exercised because none was dealt in this run. [Round 3 resolution](evidence/public-release-preflight-2026-10-29/resolution-3-Ada.png). |
| Accusation and recap | Pass. The three crew members privately accused Cy; the recap showed a 3–0–0–0 accusation tally, revealed roles, sabotage used, and a Crew win. [Accusation](evidence/public-release-preflight-2026-10-29/accusation-Ada.png), [scrolled recap](evidence/public-release-preflight-2026-10-29/recap-scrolled-Ada.png). |
| Play Again | Pass. All four pressed Back to the waiting room; the same room and roster reopened without a refresh. A second match dealt fresh roles. [Phone waiting room](evidence/public-release-preflight-2026-10-29/play-again-lobby-Cy.png). |
| Reconnect | Pass. Cy refreshed during the second match's role reveal, chose the online flow, and recovered the same private Hacker role and seat. [Recovered role](evidence/public-release-preflight-2026-10-29/role-reconnect-Cy.png). |

## Phone layout correction and invite link

The original phone-sized Informant ballot was too wide: its long sabotage checkbox label expanded the content, clipping plan descriptions. [Before correction](evidence/public-release-preflight-2026-10-29/abilities-sabotage-1-Cy.png). The phone-sized resolution, accusation, and recap also clipped their long subtitles and some text. The deployment branch shortens the sabotage label, wraps the explanation and other text, and resets scroll position when the phase changes.

A fresh local Web export was checked in a 390×844 touch browser with one human-driven Informant and three WebSocket clients. The corrected [ballot](evidence/public-release-preflight-2026-10-29/prompt-heist-corrected-informant-ballot.png) stayed at the top after a one-second settle; a single tap [checked sabotage](evidence/public-release-preflight-2026-10-29/prompt-heist-corrected-sabotage-label-tap.png). The vote resolved with sabotage's +2 suspicion, and the [resolution](evidence/public-release-preflight-2026-10-29/prompt-heist-corrected-resolution.png), [accusation](evidence/public-release-preflight-2026-10-29/prompt-heist-corrected-accusation.png), and [recap](evidence/public-release-preflight-2026-10-29/prompt-heist-corrected-recap-bottom.png) fit the viewport. Three rounds completed and the Crew won after all three crew clients accused the Informant. The bot-driven seats were not visually checked in this follow-up.

A local desktop browser copied `http://127.0.0.1:3000/?room=MRYV3C`; a fresh phone browser opened it, saw the [room code prefilled](evidence/public-release-preflight-2026-10-29/prompt-heist-invite-prefill.png), and [joined the same room](evidence/public-release-preflight-2026-10-29/prompt-heist-invite-joined.png). This verifies the link flow locally, not on a public host.

## Remaining public acceptance

- Deploy the corrected build to a public HTTPS host and verify the page and `wss://HOST/ws` from outside the local network.
- Open a copied `?room=CODE` invite link in a fresh browser context, join with a new name, and complete a four-player round against the public authority.
- Visually check an Inside Agent private reveal when dealt.
- Check a physical phone and a second browser engine if available. The current phone result is Chromium viewport emulation.
- A Render free-instance sleep or restart destroys in-memory rooms; public acceptance should record recovery behavior during a restart and should not promise durable rooms.
