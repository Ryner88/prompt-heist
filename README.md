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

Connect the Godot browser UI to the authoritative room protocol, then add reconnect and departure behavior before public deployment.

## Authoritative room service

PR 2 introduces a Node.js WebSocket service for version 1 of the room protocol. The Godot UI is not connected to it yet. See the [protocol reference](docs/protocol-v1.md) and [architecture decision record](docs/adr/0001-authoritative-room-service.md).

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

Rooms are intentionally process-local and ephemeral. A disconnect currently removes that player's seat, and a restart removes every room. Reconnect grace, durable persistence, browser screens, gameplay synchronization, and public deployment are not part of this slice.

## Tests

Every milestone follows the repository's [testing strategy](docs/testing-strategy.md), including automated, security, boundary, recovery, and checked-in manual acceptance requirements.

Run the public room registry and complete game-rule regression suites with Godot 4.7 or later:

```sh
godot --headless --path . --script res://tests/run_tests.gd
```

The GDScript room registry remains a transport-independent domain reference. The Node service now exposes the authoritative create/join boundary, but the Godot UI is not connected to it yet.
