# Prompt Heist: Trust No One

## Product vision

Prompt Heist is a 3–6 player social-deduction strategy game. Players cooperate to complete a dynamically narrated heist while an optional hidden Informant attempts to raise suspicion and make the mission fail.

## Match structure

1. Lobby and player join
2. Private role assignment
3. Mission briefing
4. Three planning, voting, and resolution rounds
5. Final escape decision
6. Informant accusation
7. Winner determination and narrative recap

## Authoritative rules

The game engine—not the language model—owns room membership, secret roles, timers, votes, resources, success probabilities, suspicion, scoring, and win conditions. AI output is constrained to structured mission content, fictional dialogue, narrative consequences, and the final recap.

## Initial win conditions

- Crew victory: complete the objective, escape before time reaches zero, and keep suspicion below its maximum.
- Informant victory: cause mission failure or avoid identification after the mission.
- Three-player cooperative mode: there is no Informant; all players win or lose together.

## MVP constraints

- One web-playable 2D interface
- 3–6 players
- One match lasting approximately 10–15 minutes
- One reusable deterministic rules engine
- AI failure fallback using bundled mission content
- No voice chat, open player chat, inventory marketplace, or account system in the first release

