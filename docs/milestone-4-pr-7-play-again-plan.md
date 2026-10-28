# Milestone 4 PR 7: Play Again

Base: Milestone 4 PR 6 (`milestone-4/online-gameplay`). Plan item 6.

## Scope and acceptance

- After the recap, each player can choose **Back to the waiting room**. The recap stays visible to everyone who has not chosen yet, with a count of who is ready.
- When every seat still in the room has chosen, the server closes the match: the recap, roles, votes, sabotage, and accusation state are cleared. The room code and seats remain.
- The reopened room accepts joins and a new start. The next heist deals fresh roles and starts from fresh meters with a higher match revision, so no client can show stale state.
- A player who leaves during the recap neither abandons the finished heist nor blocks the others from returning.
- Joins and a second start remain rejected while a heist is in play or its recap is open.

## Verification

- Node unit: readiness from the recap, progress counting only present seats, closing, and every action rejected after close.
- Node WebSocket: full four-player match, join rejected during the recap, partial return, a departure during the recap, close, a new join, and a second heist with fresh state.
- Contract fixtures for a partially returned recap and a closed match; Godot validators and flow tests for both.
- Real Godot↔Node run: the cooperative heist test returns all three clients to the waiting room and starts a second heist.
