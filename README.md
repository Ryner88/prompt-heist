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
- Deterministic success calculations and mission consequences
- Immediate mission failure at zero time, seven suspicion, or zero resources
- Final mission outcome summary
- Private accusation voting with role-dependent endings
- Complete match recap with revealed roles and accusation totals
- New-game reset from the mission summary

## Next milestone

Add reconnect and departure behavior before public deployment.

## Authoritative room service

PR 2 introduced a Node.js WebSocket service for version 1 of the room protocol. PR 3 connects the Godot browser client to its create/join boundary. See the [protocol reference](docs/protocol-v1.md) and [architecture decision record](docs/adr/0001-authoritative-room-service.md).

Install and run it locally:

```sh
npm ci
npm test
npm start
```

The server listens on `http://0.0.0.0:3000` by default. Readiness is available at `GET /healthz`, and clients connect to `ws://localhost:3000/ws`. Set `PORT` and `HOST` to override the defaults.

Build and check the production container:

```sh
docker build -t prompt-heist-room-service .
docker run --rm -p 10000:10000 prompt-heist-room-service
curl --fail http://localhost:10000/healthz
```

Rooms are intentionally process-local and ephemeral. A disconnect currently removes that player's seat, and a restart removes every room. Reconnect grace, durable persistence, gameplay synchronization, and public deployment are not part of this slice.

## Browser room flow

The Godot start screen keeps local pass-and-play available and adds an online create/join path. Start the authority and client locally in separate terminals:

```sh
npm ci
npm start
godot --path .
```

The client defaults to `ws://127.0.0.1:3000/ws`. Native development can override it with `PROMPT_HEIST_WS_URL`; Web builds read `network/room_service_url` from `project.godot`. Before a public Web build, set that project setting to the deployed `wss://…/ws` endpoint. Every non-loopback endpoint must use `wss://` and Godot's default certificate verification. The public URL is configuration, not gameplay code.

Build the Web client after installing the Godot 4.7.2 export templates:

```sh
mkdir -p builds/web
godot --headless --path . --export-release Web builds/web/index.html
```

Serve the result over HTTP instead of opening `index.html` from disk:

```sh
python3 -m http.server 8000 --directory builds/web
```

Then open `http://127.0.0.1:8000/`. A future deployed HTTPS page must connect to a secure `wss://` room-service endpoint to avoid mixed-content blocking. The Web preset uses single-threaded output, so basic static hosting does not need cross-origin isolation headers. This PR does not deploy either component.

The lobby shows only server snapshots. Leaving closes the connection and clears the in-memory identity. Refreshing, disconnecting, or restarting the service loses the seat; the user must return to entry and create or join again until reconnect support arrives in PR 4. No networked gameplay actions are available yet.

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

The GDScript room registry remains a transport-independent domain reference. The Node service is authoritative for online room membership and identity.
