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

Expand the completed local game loop with real multiplayer rooms, server-authoritative state, and server-side OpenAI narration.
