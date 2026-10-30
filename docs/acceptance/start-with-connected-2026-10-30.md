# Starting with a reserved offline seat — 2026-10-30

The reported “Everyone must be connected” message came from a reserved seat whose browser had disconnected. A normal four-player start still waits for that player. [PR #28](https://github.com/Ryner88/prompt-heist/pull/28), merged at `ae79bd7`, now shows each seat's connection status and offers an explicit **Start with 3 connected players** action when a fourth seat is offline. The action removes the disconnected seat and starts a cooperative game; a four-player social game still requires all four players connected.

Validation:

- Node: 65 tests and coverage gates passed. Real WebSocket tests cover the offline status, ordinary start rejection, explicit three-player start, invalidation of the removed seat's recovery token, and refusal to start with only two online players.
- Godot: unit and mobile UI smoke tests passed. Real Node/Godot integration passed for create, join, resume, leave, a complete heist, and Play Again.
- Local browser: a 390×844 Chromium touch viewport displayed the disconnected name and the new button. Tapping it opened the role screen for a three-player cooperative match with no page errors.
- Public browser: after the Render Web build updated, the same 390×844 Chromium flow over HTTPS/WSS started room `KN8FL8` with Ivy, Ben, and Cy after Dee disconnected. The server acknowledged `start_match`; the browser received a `role_reveal` snapshot in cooperative mode with those three seats and no page errors.

The public check used one simulated phone browser and three Node WebSocket clients. Physical phone input and a four-human run remain user checks.
