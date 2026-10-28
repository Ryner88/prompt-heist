# Prompt Heist room protocol v2

Version 2 preserves the version 1 room, recovery, voting, and recap rules described in [the original reference](protocol-v1.md). Client and server envelopes now use `"version":2`. A version 1 client receives `unsupported_version` and must refresh to the matching build. The health response reports `"protocol_version":2`.

## Specialist action

During `voting`, a crew seat may send one `use_ability` command per match, before its vote:

```json
{"version":2,"type":"use_ability","request_id":"ability-1","payload":{"round":1}}
```

The Hacker must also send `"target_plan_id"` for a digital plan available this round (`spoof`, `blackout`, or `drone`). Other roles cannot send a target. Driver can act only in round 3; Fixer can act only while resources are below eight. The server validates the sending seat's role, phase, round, target, vote state, and one-use limit. Rejections do not spend the ability. Repeated request IDs return the original cached response.

Every `match_private` payload now adds `ability_available` and `ability_used` booleans plus an `ability_details` string. This information is sent only to the bound seat. The public snapshot never includes a role, owner of an ability, or a private clue. An active Hacker reduction changes the current plan's public risk value for that round. Fixer recovery changes the public resource meter. Resolution text reports applied consequences.

## Rule effects

- Mastermind privately sees the current plans' base success scores.
- Hacker reduces one eligible plan's risk by one for the current round; the reduced risk also participates in tie resolution.
- Driver, in round 3, prevents the extra suspicion and resource loss if the selected escape plan fails. Normal plan costs and risk still apply.
- Inside Agent privately learns the current round's hidden complication. The affected plan loses eight score if selected.
- Security Specialist blocks one point of suspicion gained in the current round, including sabotage suspicion.
- Fixer immediately restores one spent resource before resolution, up to the maximum of eight.

The role text shown to players is the rule summary. The server is authoritative for every effect. The local pass-and-play rules mirror these effects during each player's private vote.
