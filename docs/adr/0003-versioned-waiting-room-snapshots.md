# ADR 0003: Versioned waiting-room snapshots

- Status: Proposed for Milestone 4 PR 5
- Date: 2026-10-07

## Context

PR #10 provides server-owned seats and recovery, but a connected browser can miss a roster update and an older snapshot could overwrite a newer one. Existing protocol-v1 clients expect exactly four public snapshot fields, so adding a required field to every snapshot would break them.

## Decision

- `sync: true` opts a create, join, or resume command into a fifth public snapshot field: a positive room `revision`. The original four-field snapshot remains available to older clients in the same room. No private identifier or token enters either shape.
- The room registry increments the revision only on an accepted lifecycle transition: create, join, leave, disconnect, resume, or expiry. The server owns both the revision and the complete roster.
- The Godot waiting-room client opts in and accepts only strictly newer revisions for its active room and connection generation. A successful resume waits for a fresh full snapshot before presenting the roster.
- The server pushes changes immediately and rebroadcasts the latest roster every five seconds. Its one-second expiry sweep bounds the normal removal lag. No client command can request another room's roster.

## Consequences

Connected clients converge after a missed update even when no further player action occurs. A duplicate or reordered snapshot cannot roll back the Godot lobby. The periodic rebroadcast costs one small public message per connected member every five seconds; load and public deployment behavior remain future release gates. A server restart still loses all rooms and resets revision history along with them.
