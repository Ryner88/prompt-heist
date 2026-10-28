# Milestone 4 PR 6: Server-authoritative online match

Base: PR #11 (`milestone-4/waiting-room-synchronization`, `2372aa3`). This slice moves the complete heist online. It is the gameplay half of plan item 5 (action and idempotency hardening); Play Again, the mobile pass, deployment, and release validation follow.

## Scope and acceptance

- Three or four connected, game-capable members can start a heist from the waiting room. Three players play cooperatively; four add one hidden Informant.
- Each player sees only their own role. Every member receives the same public heist view at each step.
- Role reveal, briefing, planning, and resolution advance when every seat is ready. Votes stay hidden until all seats vote; the server resolves the round with the same rules as the local game.
- The Informant can sabotage once, privately, while voting. Crew members cannot.
- After a successful mission with an Informant, the crew votes privately; the Informant cannot vote. Ties fail. Mission collapse skips the accusation.
- Every member sees an identical recap with revealed roles, round results, and accusation totals.
- A refresh or brief disconnect restores the seat, role, and current step. A permanent departure ends the heist for everyone without revealing roles and reopens the room.

## Threat and failure cases

- A client cannot pick roles, seats, or another player's identity: commands carry only phase, round, plan ID, the sabotage flag, or a suspect seat, and the server resolves the acting seat from the bound connection.
- Duplicated, delayed, or reordered actions cannot double-count or apply to a later step: request IDs are cached per connection, and every action names the phase and round it targets.
- Public payloads and logs never contain player IDs, session IDs, tokens, roles before the end, other seats' votes, or pending sabotage. Accusation progress is aggregate-only so the non-voting Informant is not singled out.
- Older protocol-v1 clients cannot be dealt into a match they cannot display.

## Verification

- `server/test/match-engine.test.js`: rules parity with `tests/game_state_regression_test.gd`, scoring and penalty arithmetic, thresholds, sabotage, all 27 unanimous plan sequences, accusation outcomes, public-view secrecy, abandonment.
- `server/test/match.integration.test.js`: four real WebSocket clients play a full social match; privacy sweep for identities and roles; start validation; schema, stale, and idempotent replay handling; resume mid-match; abandonment by expiry and by Leave; periodic rebroadcast.
- `server/test/match-contract.test.js` plus the Godot client tests: both sides check `tests/fixtures/match_contract.json`.
- Godot client and flow tests for match message validation, revision ordering, command envelopes, and screen-state transitions.
- Still required before merge: the Godot suites and real Godot↔Node integration in CI, and a manual multi-browser acceptance record for a full four-player match.
