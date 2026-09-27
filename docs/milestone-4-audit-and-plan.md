# Milestone 4: Public Release and Multiplayer Hardening

## Repository audit

Audit baseline: released `main` at `c8f1e70` (`milestone-3`).

### Current architecture

- **Networking:** none. The project does not create peers, connect sockets, expose network RPCs, or synchronize state.
- **Rooms:** none. The lobby adds players to one in-process `HeistGameState`; there are no room IDs, codes, invitations, or join requests.
- **Authority:** `scripts/main.gd` constructs `HeistGameState` locally. The same client-side object owns membership, roles, mission state, voting, suspicion, outcomes, and recap. All player role dictionaries coexist in that one process for pass-and-play.
- **Reconnect/disconnect:** none. There is no connection identity, seat reservation, persistence, timeout, or leave handling.
- **Deployment/export:** `project.godot` declares a desktop viewport and renderer only. The repository has no `export_presets.cfg`, export automation, static hosting setup, server executable, backend, or CI test workflow.
- **Browser/mobile:** UI is built with Godot controls at runtime. Canvas item stretching is enabled, but layout uses fixed 96-pixel side margins and three side-by-side mission cards. There are no mobile breakpoints, viewport checks, browser tests, or deployed URL checks. Mobile and Web export compatibility have not been verified.
- **Tests:** the released repository had no tracked automated tests. Milestones 2 and 3 were verified with temporary Godot headless scripts and UI-control simulations; those scripts were not part of the repository.
- **Game rules:** the current deterministic rules are contained in `scripts/game_state.gd`. This milestone must keep them unchanged while moving authority to a room host.

## Architecture decisions and blockers

1. The first slice is a transport-independent, process-local room registry. It gives the eventual authoritative service a tested room-code/capacity/name boundary without choosing a hosting vendor, network protocol, persistence layer, or modifying game rules.
2. Room codes use Godot's `Crypto.generate_random_bytes`, six characters from a 32-character alphabet. Godot documents this API as cryptographically secure; the resulting code is a room locator and must not be treated as a substitute for connection authentication or rate limiting. [Godot random generation documentation](https://docs.godotengine.org/en/4.7/tutorials/math/random_number_generation.html)
3. The room registry exposes only names and room metadata in its public snapshot. It stores no roles or game state. Private roles remain outside the public room view by construction.
4. The registry is process-local and ephemeral. Multiple server instances, persistent rooms, reconnects, transport authorization, rate limiting, and deployment remain out of scope for this foundational PR.
5. Before the authoritative transport PR, choose and verify a public hosting target and browser-capable transport. Static HTML hosting alone cannot provide authoritative, reconnectable multiplayer rooms.

## Ordered implementation plan

The release sequence keeps authority and privacy ahead of broad deployment. The public URL is the release gate after the room protocol is operational.

1. **Room domain foundation (this PR):** create/join registry, six-character room codes, case-insensitive duplicate-name rejection, hard four-seat cap, collision retry, and public-only snapshots. Add deterministic unit tests.
2. **Authoritative room protocol:** decide hosting/runtime and browser-compatible transport; add server-owned sessions and validated commands, with private role delivery separated from public snapshots.
3. **Browser room flow:** exportable client UI for create/join by code, waiting/disconnected/full/invalid-code states, and synchronized room lifecycle.
4. **Reconnect and departures:** stable seat identity, reconnect grace, duplicate-session arbitration, explicit departure policy, and room cleanup.
5. **Action/idempotency hardening:** server-side one-vote/one-action checks, replay protection, and secret-data leak tests.
6. **Play Again:** host-authorized room reset that clears all game and private state while keeping the room link and seats.
7. **Mobile and error-state pass:** responsive layouts and mobile-browser verification for lobby, game, reconnect, and recap screens.
8. **Public web deployment:** configure the selected static client and authoritative service at a stable URL with basic privacy-safe operational logging.
9. **Release validation:** four independent browser sessions, fifth-player rejection, correct private roles, refresh recovery, three synchronized rounds, accusation, identical recap, and replay; run the test twice on desktop and phone.

## Pull request boundaries

- PR 1: room registry and focused tests (current branch).
- PR 2: selected server transport, authoritative room process, and protocol tests.
- PR 3: create/join browser UI and synchronized lobby.
- PR 4: reconnect, departure, capacity, and duplicate-action validation.
- PR 5: replay reset and public/private payload audit tests.
- PR 6: responsive browser UI and explicit connection/error states.
- PR 7: stable deployment and twice-run end-to-end release test.

Each PR should keep the existing Godot rule suite green. The current repository lacks a checked-in full game regression harness; PR 1 adds a repeatable headless test entry point for the room domain, and PR 2 should preserve/add a complete rules regression suite before gameplay state moves server-side.

Every PR and milestone is also governed by the repository-wide [testing strategy](testing-strategy.md). A completed [manual acceptance record](manual-test-record-template.md) is a release requirement, not a substitute for the automated suites.

## Current PR limitations

- No network endpoint or game UI integration is added here.
- Rooms disappear when the registry process exits.
- Host selection and browser transport remain an explicit architecture blocker for PR 2.
- The existing pass-and-play game remains unchanged.
