# ADR 0004: Server-authoritative online match

- Status: Proposed for Milestone 4 PR 6
- Date: 2026-10-28

## Context

PRs 1–5 give every online room a server-owned roster, recovery, and ordered snapshots, but the heist itself still runs only inside one Godot process. Moving play online must not let any client see another seat's role, learn a pending sabotage, submit an action for someone else, or roll another player's screen back. The deterministic rules in `scripts/game_state.gd` must keep producing the same results.

## Decision

- The room authority runs the match. `server/src/match-engine.js` is a line-for-line port of `scripts/game_state.gd`: the same plan cards, scoring formula, clamps, tie rule, meter thresholds, and win conditions. The pass-and-play GDScript engine remains for local mode. Unit tests pin the shared formula cases and every unanimous three-round sequence.
- Seats are fixed at start in roster order. Public payloads refer to players by seat index and display name only. Server player IDs, session IDs, and tokens never appear in match payloads or logs.
- Two message types carry state. `match_snapshot` is identical for every member and contains no roles until the match finishes. `match_private` goes only to the seat's own bound connection and contains that seat's role, sabotage availability, and its own vote or accusation. Both share a per-room match revision that keeps increasing across matches, and clients accept only strictly newer revisions.
- Clients opt in with `game: true` on create, join, or resume. A match starts only when every seat is connected and game-capable, so an older protocol-v1 client in the room cannot silently miss its role.
- Any seated member may start once three or four players are present. The online room cap stays four, so online play has a cooperative three-player mode and a four-player Informant mode. Starting locks the room: later joins receive `match_in_progress`.
- Pacing steps (role reveal, briefing, planning, resolution) advance only when every seat has sent `ready` for that exact phase and round. Voting resolves when every seat has voted; accusation resolves when every crew seat has voted. Phase and round parameters make a late or duplicated action fail safely with `stale_action` instead of affecting a later step.
- Sabotage rides on the Informant's own vote (`sabotage: true`) so arming it and voting are one atomic action with one ordinary acknowledgement. Accusation progress is published only as a count; a per-seat "acted" flag would single out the Informant, who cannot vote.
- A transient disconnect keeps the seat for the existing 30-second reservation and the match pauses on that seat's readiness. A permanent departure (Leave or reservation expiry) abandons an unfinished match without revealing roles, then reopens the room. A finished recap stays open until everyone still in the room returns to the waiting room.

## Consequences

- The client renders every heist screen from authoritative state. It never computes outcomes, so a modified client can at most decline to act.
- A disconnected player stalls the step for up to 30 seconds before the match is abandoned. That trade favours fairness and simplicity over host migration or bot substitution.
- Any member can start a match before others are ready; the role-reveal readiness step keeps anyone from being rushed past their role.
- Play Again (Milestone 4 PR 7) reuses the readiness step: after the recap, each player asks to return to the waiting room. When every seat still in the room has asked, the match closes, all match and private state is cleared, and the room code and seats are kept. No player is pulled off the recap before reading it, and no host role is needed. The audit plan proposed a host-authorized reset; the room has no host concept, and any member can already start, so a unanimous return is used instead.
- Rules now live in two languages. The Node unit suite mirrors the Godot regression suite case by case, and `tests/fixtures/match_contract.json` pins the wire format: Node fails if real payloads drift from it and Godot validates every payload in it.
