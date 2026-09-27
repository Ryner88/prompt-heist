# Prompt Heist Testing Strategy

This policy applies to every milestone. A milestone is complete only when its automated checks pass, critical security findings are resolved, required boundary cases are covered, its checked-in manual acceptance record passes, and the release has a tested rollback path.

## Required test categories

Every milestone must address each category below. If a category does not apply, the milestone acceptance record must explain why.

| Category | What it must prove |
| --- | --- |
| Unit | Individual rules and functions behave correctly. |
| Integration | Scenes, game state, registry, server, and transport work together. |
| End-to-end | A group can complete the relevant user journey. |
| Regression | Previously released milestone behavior still works. |
| Boundary | Minimums, maximums, empty values, thresholds, and off-by-one cases work. |
| Negative | Invalid and unauthorized actions are safely rejected. |
| Security | Clients cannot access secrets or control authoritative state. |
| Coverage | Important rules, branches, and failure paths are exercised. |
| Manual | Real browsers, devices, networks, and deployment behavior work. |
| Recovery | Refreshes, disconnects, retries, crashes, and restarts behave predictably. |

## Future milestone test plan

### Networking implementation

Automated tests must:

- Create and join rooms through the real network boundary.
- Verify server-authoritative state.
- Exercise duplicated, delayed, reordered, and stale messages.
- Exercise simultaneous joins and simultaneous actions.
- Confirm one client cannot modify another player.
- Confirm private roles and actions are sent only to their owner.
- Verify request identifiers prevent double processing.
- Validate reconnect tokens and state recovery.

Boundary tests must cover:

- Zero connected players.
- The minimum and maximum supported player counts.
- Exactly one slot remaining and one connection beyond room capacity.
- A message at the maximum accepted size and one byte beyond it.
- Reconnect immediately before, exactly at, and immediately after timeout.
- An action submitted exactly at a phase transition.

Security checks must cover:

- Malformed-message fuzzing and schema validation on every client message.
- Rate limits for room creation, joins, reconnects, and actions.
- Errors that expose neither secrets nor internal stack traces.
- Secure WebSockets and HTTPS in production.
- Origin validation where appropriate.
- Dependency and secret scanning.

Manual tests must include:

- Two-, three-, and four-browser sessions.
- Mixed desktop and mobile clients.
- Wi-Fi interruption and reconnection.
- Browser refresh during every phase.
- An incognito player joining an existing room.
- Two rooms running concurrently.

### Lobby and room lifecycle

Automated tests must:

- Cover host creation, player joining, leaving, kicking, and readiness.
- Verify only authorized players can perform host actions.
- Prevent a game from beginning with an invalid player count.
- Verify the documented policies for late joins, host transfer or termination, and room-code reuse.
- Expire empty rooms.
- Reject gameplay actions in completed rooms.

Boundary tests must cover:

- Minimum player count minus one, minimum, maximum, and maximum plus one.
- Empty, one-character, maximum-length, and over-limit names.
- Duplicate names differing by case, spaces, or Unicode normalization.
- Room expiration immediately before, exactly at, and immediately after the deadline.
- The maximum number of rooms supported by the server.

Manual tests must include:

- Players repeatedly leaving and rejoining.
- The host closing the browser.
- A join attempt against a full lobby.
- Start-button state as readiness changes.
- The maximum-player lobby with long names.

### Deployment and persistence

Automated tests must:

- Verify the health endpoint reports application and dependency status.
- Fail safely when required production configuration is absent.
- Verify restart behavior against the documented room-persistence policy.
- Verify migrations or state-format changes remain backward compatible when required.
- Verify build artifacts contain no development secrets.
- Run a deployed smoke test that creates and joins a room.

Boundary tests must cover:

- An empty persistence store and corrupt or partial state.
- The maximum expected active-room count.
- Expired-room cleanup at the cutoff time.
- Storage unavailable at startup and during gameplay.

Security checks must cover:

- TLS configuration, security headers, and disabled production debug mode.
- Least-privilege service credentials.
- Dependency vulnerability and source/build-artifact secret scanning.
- Logs for reconnect tokens, private roles, IP addresses, and personal data.
- Backup access and retention if persistence is added.

Manual tests must include:

- A clean deployment and rollback to the previous working version.
- A restart while rooms are active.
- Recovery after an intentionally interrupted deployment.
- A test from a device outside the development network.

### Public release and operational hardening

Automated tests must:

- Complete full games for every supported player count.
- Cover crew victory, adversary victory, sabotage, ties, and every terminal threshold.
- Exercise multiple concurrent rooms and sustained room creation and cleanup.
- Check response latency and memory growth under expected load.
- Check compatibility with the production protocol version.

Security checks must cover:

- Room-code guessing and enumeration resistance.
- Join and action rate limits.
- Replay-attack resistance.
- Session and reconnect-token entropy and expiration.
- Authorization on every state-changing request.
- Denial-of-service protections and input limits.
- Software composition analysis, license review, static analysis, and deployment configuration review.

Manual tests must include:

- The complete new-visitor-to-replay journey.
- Chrome, Edge, Firefox, and Safari.
- Real Android and iPhone devices.
- Slow-network and temporary-offline behavior.
- Keyboard navigation and screen-reader accessibility.
- A production monitoring, logging, alerting, and rollback drill.

## Coverage policy

Coverage percentage is a signal, not the sole definition of adequate testing.

- Win conditions, phase transitions, authorization decisions, role privacy, and meter thresholds require 100% coverage.
- Every validation and error path requires branch coverage.
- Every confirmed bug requires at least one regression test.
- CI must produce coverage reports and retain them as artifacts.
- Coverage must not decrease without an explanation in the pull request.
- Generated code, trivial accessors, and engine glue may be excluded only when the exclusion is documented.
- The general target is at least 80% line coverage; critical game and security logic must be effectively fully covered.

## Boundary-test matrix

Use below/exactly/above tests wherever a limit exists.

| Boundary | Required values |
| --- | --- |
| Player count | `min - 1`, `min`, `max`, `max + 1` |
| Room capacity | `0`, `1`, `capacity - 1`, `capacity`, `capacity + 1` |
| Name length | `0`, `1`, `max`, `max + 1` |
| Message size | Empty, valid small, exact maximum, maximum plus one |
| Meter values | Below threshold, exactly threshold, above threshold |
| Mission count | Before final, final, attempted extra mission |
| Vote count | None, partial, all, duplicate, attempted extra vote |
| Timeout | Just before, exactly at, just after |
| Room lifetime | Active, expiration boundary, expired |
| Retry limit | No retries, final allowed retry, one too many |

## Manual acceptance records

Each milestone must check in a completed copy of [the manual acceptance template](manual-test-record-template.md). The record must identify:

- Build or commit tested.
- Environment and deployment URL.
- Browser, operating system, and device.
- Preconditions and test data.
- Exact steps.
- Expected and actual results.
- Pass, fail, or blocked status.
- Screenshots or logs for important results.
- Discovered issue links.
- Tester and date.
- Final release recommendation.

Store completed records under `docs/acceptance/` using `milestone-<number>-<date>.md`.
