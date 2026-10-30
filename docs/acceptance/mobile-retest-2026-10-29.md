# Mobile release retest, 2026-10-29

## Deployment and scope

Render service `srv-dbhscvflk1mc739rvc20` reported release merge `1235b71` live as deploy `dep-dbhvdeivcj2c73f9fhqg` at 2026-10-30 01:46 UTC (2026-10-29 21:46 EDT). The checks below ran after that deployment, on 2026-10-29 about 21:47–22:04 EDT. This includes PR #19 (`4971bdc`), the mobile dialog and keyboard correction in [PR #20](https://github.com/Ryner88/prompt-heist/pull/20), and automatic seat recovery with duplicate-tab protection in [PR #21](https://github.com/Ryner88/prompt-heist/pull/21). The public game is [https://prompt-heist-pni7.onrender.com/](https://prompt-heist-pni7.onrender.com/).

The public full match used a Firefox browser at a `390×844` viewport for Ivy and three Node WebSocket clients for Ben, Cy, and Dee. The browser rendered the game over HTTPS and connected to the public WSS endpoint. Repetitive ready and some vote actions were sent through the protocol; browser controls were used for room creation, one plan vote, the Driver ability, hidden-complication acknowledgement, accusation confirmation, and Back to the waiting room. This is a four-seat integration and one-browser visual test, not a four-human or physical-iPhone test.

| Check | Observed result |
| --- | --- |
| Mobile privacy | In an earlier public room on the same deploy, press-and-hold showed the private role and releasing hid it again; [role reveal](evidence/mobile-retest-2026-10-29/role-revealed.png) and [privacy cover](evidence/mobile-retest-2026-10-29/privacy-cover.png) rendered in Firefox. |
| Reconnect | Refresh during planning automatically restored Ivy's same room, seat, Hacker role, and phase without selecting Online. [Recovered planning screen](evidence/mobile-retest-2026-10-29/reconnected-planning-r1.png). A local Firefox duplicate-tab check left the original socket open and held the duplicate at [entry with an explanation](evidence/mobile-retest-2026-10-29/duplicate-tab-protected.png). |
| Full match | In room `6PAS7P`, four seats played Ghost, Drone, and Freight. All three succeeded with scores 77, 83, and 78. Cy's private Informant sabotage applied in round 1. The [hidden-complication overlay](evidence/mobile-retest-2026-10-29/complication-r1.png) wrapped its text and had a visible Acknowledge button. |
| Action controls | Ivy's [round-one ballot](evidence/mobile-retest-2026-10-29/voting-r1.png) submitted Ghost through the visible button. The Driver ability was used through its button in round 3; the [post-use screen](evidence/mobile-retest-2026-10-29/driver-ability-used.png) shows the charge spent and private escape protection. |
| Accusation and outcome | The [confirmation prompt](evidence/mobile-retest-2026-10-29/accusation-confirmation.png) named Cy before Ivy submitted. All three crew seats accused Cy; the [recap](evidence/mobile-retest-2026-10-29/final-outcome.png) showed a Crew win, the revealed roles, sabotage, and a 3–0 accusation result for Cy. |
| Play Again | All four seats chose Back to the waiting room; [the same code and roster returned](evidence/mobile-retest-2026-10-29/waiting-room-reset.png). Ben started a second match without a browser refresh. Ivy received a [fresh Hacker role](evidence/mobile-retest-2026-10-29/play-again-new-role.png), with round reset to 1 and previous outcome cleared. |
| Rejected action | A vote sent during the second match's role reveal returned `stale_action`; the match stayed in role reveal with no vote recorded. |

## Keyboard reachability

The current public build was loaded in Firefox and Chromium at `390×844`, then the viewport was shortened to `390×480` to approximate keyboard occlusion. The room-code field and Join/Create controls remained reachable after scrolling on both engines: [Firefox landing](evidence/mobile-retest-2026-10-29/firefox-landing-scrolled.png), [Firefox entry](evidence/mobile-retest-2026-10-29/firefox-entry-scrolled.png), [Chromium landing](evidence/mobile-retest-2026-10-29/chromium-landing-scrolled.png), and [Chromium entry](evidence/mobile-retest-2026-10-29/chromium-entry-scrolled.png). Neither browser reported a page error. A desktop viewport reduction does not reproduce the iPhone's native keyboard, visual viewport, or Safari scrolling behavior.

## Remaining physical-device acceptance

The iPhone scrolling bug needs a fresh physical check on this deploy: focus the landing room-code field and the online entry name field with the native keyboard open; verify that each field, Join, and Create can be reached and tapped by scrolling. The current run also does not establish four-human visual acceptance, Safari behavior, or a new invite-link check on this deploy. Earlier public invite-link and physical-phone reports are in [the prior acceptance record](public-release-2026-10-29.md), but they predate these controls.
