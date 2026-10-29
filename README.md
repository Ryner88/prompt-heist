# Prompt Heist Godot Prototype

This is the first playable foundation for **Prompt Heist: Trust No One**, built for Godot 4 with GDScript.

## Run it

1. Install Godot 4.x.
2. Import `project.godot` from the Godot Project Manager.
3. Press **F6/F5** to run the project.
4. Add at least three players and select **Start heist**.

The current prototype supports a complete three-round local pass-and-play mission. With four or more players, exactly one player becomes the hidden Informant. Three-player matches run in cooperative mode.

## Current milestone

- Responsive 2D project shell
- Validated 3–6 player lobby
- Unique player names
- Deterministic game phases
- Random specialist-role assignment
- Optional hidden Informant
- Private pass-and-play role reveal
- First mission briefing
- Time, suspicion, and resource meters
- Three action plans in each of three rounds
- Private player voting with majority and deterministic tie resolution
- Private once-per-match Informant sabotage
- Six one-use specialist abilities during private voting
- Hidden round complications that the Inside Agent can reveal
- Deterministic success calculations and mission consequences
- Immediate mission failure at zero time, seven suspicion, or zero resources
- Final mission outcome summary
- Private accusation voting with role-dependent endings
- Complete match recap with revealed roles and accusation totals
- New-game reset from the mission summary

## Online heists

Three or four players in an online room can play the complete heist from separate browsers. The Node room authority runs the rules, deals roles privately, and sends every player the same public view at each step. Each player sees only their own role; the Informant's sabotage, specialist information, and every vote stay private until the round resolves. Specialists can use their ability once per match before casting a vote. Each step advances once every player is ready, so a quick player cannot rush anyone past their role. A refresh or brief disconnect keeps the seat for 30 seconds and restores the player's role, ability use, and current step. If a player leaves for good, the heist is called off without revealing roles and the room reopens. After the recap, once everyone still in the room chooses **Back to the waiting room**, the room reopens with the same code for new players and another heist with fresh roles. See [ADR 0004](docs/adr/0004-server-authoritative-online-match.md).

## Release validation

Play the public game at [prompt-heist-pni7.onrender.com](https://prompt-heist-pni7.onrender.com/). The [public acceptance record](docs/acceptance/public-release-2026-10-29.md) covers HTTPS, WSS, a complete four-browser match, reconnect, Play Again, a room-code invite link, and rejected actions. Phone-sized checks used Chromium touch emulation; a physical phone and a second browser engine remain to be checked.

## Authoritative room service

PR 2 introduced the Node.js WebSocket service. Specialist actions changed the strict private match payload, so the current client and server use [protocol version 2](docs/protocol-v2.md). The [version 1 reference](docs/protocol-v1.md) remains as historical documentation. See also the [architecture decision record](docs/adr/0001-authoritative-room-service.md).

Install and run it locally:

```sh
npm ci
npm test
npm start
```

The server listens on `http://0.0.0.0:3000` by default. Readiness is available at `GET /healthz`, and clients connect to `ws://localhost:3000/ws`. Set `PORT` and `HOST` to override the defaults.

Build and check the production container, which exports the Godot Web client and serves it from the same process as the room service:

```sh
docker build -t prompt-heist-room-service .
docker run --rm -p 10000:10000 prompt-heist-room-service
curl --fail http://localhost:10000/healthz
```

The game page is at `http://localhost:10000/`; the room WebSocket is at `ws://localhost:10000/ws`. The server serves only generated `index.*` assets from its static directory. The [Render Blueprint](render.yaml) selects one instance on the release branch and checks `/healthz`. Render supplies HTTPS and WSS at the same public host. The browser client derives its secure WebSocket URL from that host; a local Web build continues to use the project setting. A room's **Copy invite link** button produces `https://HOST/?room=CODE`; opening it pre-fills the Join flow. The room code is a locator, and the new player still enters a display name.

Rooms are intentionally process-local and ephemeral. Current clients reserve a seat for 30 seconds after a transient disconnect. An acknowledged Leave releases it immediately. A restart removes every room and any heist in progress. Version 1 clients are rejected with `unsupported_version` and must update. Render's free instance can sleep or restart, so active rooms are not durable.

## Browser room flow

The Godot start screen keeps local pass-and-play available and adds an online create/join path. Start the authority and client locally in separate terminals:

```sh
npm ci
npm start
godot --path .
```

The client defaults to `ws://127.0.0.1:3000/ws`. Native development can override it with `PROMPT_HEIST_WS_URL`; local Web builds read `network/room_service_url` from `project.godot`. Public Web builds connect to `wss://` on their own host with Godot's default certificate verification.

Build the Web client after installing the Godot 4.7.2 export templates:

```sh
mkdir -p builds/web
godot --headless --path . --export-release Web builds/web/index.html
```

Serve the result over HTTP instead of opening `index.html` from disk:

```sh
python3 -m http.server 8000 --directory builds/web
```

Then open `http://127.0.0.1:8000/`. This standalone local static server still needs the separate room service at port 3000. The Web preset uses single-threaded output, so basic static hosting does not need cross-origin isolation headers.

The lobby shows only server snapshots. Leave sends an authoritative command and clears the private credential after acknowledgement. A transient disconnect keeps the seat reserved for 30 seconds; Retry resumes it with a rotated credential. In a Web build, same-tab refresh can recover through `sessionStorage`. An invalid room response or a command left unanswered for 10 seconds closes the connection so the user can retry from a known state. A service restart clears all rooms and credentials. With three or four players, any member can start the online heist from the waiting room.

## Tests

Every milestone follows the repository's [testing strategy](docs/testing-strategy.md), including automated, security, boundary, recovery, and checked-in manual acceptance requirements.

Run the public room registry, complete game-rule regressions, protocol-client tests, and UI-state tests with Godot 4.7.2:

```sh
godot --headless --path . --script res://tests/run_tests.gd
```

Run the real Godot-to-Node integration test while the room service is running:

```sh
TEST_WS_URL=ws://127.0.0.1:3000/ws godot --headless --path . --script res://tests/network_integration_test.gd
```

After changing a heist payload, regenerate the shared contract fixture that both test suites check:

```sh
UPDATE_MATCH_FIXTURES=1 node --test server/test/match-contract.test.js
```

The GDScript room registry remains a transport-independent domain reference. The Node service is authoritative for online room membership and identity.
