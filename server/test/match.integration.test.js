import assert from "node:assert/strict";
import test from "node:test";
import { RECONNECT_GRACE_MS } from "../src/constants.js";
import { RoomRegistry } from "../src/room-registry.js";
import { command, connectClient, startTestServer } from "./helpers.js";

// random(n) → 0: deterministic roles; seat 0 (the creator) is the Informant.
const zero = () => 0;
const CAPABILITIES = { reconnect: true, sync: true, game: true };

async function gameRoom(t, count, { registryOptions = {}, serverOptions = {}, presence = false } = {}) {
  const registry = new RoomRegistry({ matchRandom: zero, ...registryOptions });
  const server = await startTestServer({ registry, ...serverOptions });
  t.after(() => server.service.close());
  const names = ["Ada", "Ben", "Cy", "Dee"].slice(0, count);
  const clients = [];
  let roomCode = null;
  for (const name of names) {
    const client = await connectClient(server.websocketUrl);
    t.after(() => client.close());
    const type = roomCode ? "join_room" : "create_room";
    const payload = roomCode ? { room_code: roomCode, display_name: name, ...CAPABILITIES, ...(presence ? { presence: true } : {}) }
      : { display_name: name, ...CAPABILITIES, ...(presence ? { presence: true } : {}) };
    client.send(command(type, `${name}-enter`, payload));
    const result = await client.next((message) => message.request_id === `${name}-enter`);
    assert.equal(result.type, "command_result", JSON.stringify(result));
    roomCode = result.payload.room_code;
    client.name = name;
    client.token = result.payload.reconnect_token;
    client.sessionId = result.payload.session_id;
    client.playerId = result.payload.player_id;
    clients.push(client);
  }
  return { server, registry, clients, roomCode };
}

let requestCounter = 0;
async function send(client, type, payload = {}) {
  const requestId = `${type}-${(requestCounter += 1)}`;
  client.send(command(type, requestId, payload));
  return client.next((message) => message.request_id === requestId);
}

function latest(client, type, predicate = () => true) {
  return client.next((message) => message.type === type && predicate(message.payload));
}

function phaseIs(phase, extra = () => true) {
  return (payload) => payload.phase === phase && extra(payload);
}

async function everyoneReady(clients, phase, round) {
  for (const client of clients) {
    const result = await send(client, "ready", { phase, round });
    assert.equal(result.type, "command_result", JSON.stringify(result));
  }
}

async function allVote(clients, round, planId) {
  for (const client of clients) {
    const result = await send(client, "cast_vote", { round, plan_id: planId });
    assert.equal(result.type, "command_result", JSON.stringify(result));
  }
}

test("a disconnected fourth seat is identified and three connected players may explicitly start", async (t) => {
  const { clients, roomCode, server } = await gameRoom(t, 4, { presence: true });
  const [ada, ben, cy, dee] = clients;
  const token = dee.token;
  await dee.close();
  const offline = await ada.next((message) => message.type === "room_snapshot"
    && message.payload.connected?.join() === "true,true,true,false");
  assert.deepEqual(offline.payload.player_names, ["Ada", "Ben", "Cy", "Dee"]);
  assert.equal((await send(ada, "start_match")).payload.code, "players_disconnected");
  const started = await send(ada, "start_match", { drop_disconnected: true });
  assert.deepEqual(started.payload, { command: "start_match", room_code: roomCode });
  const trimmed = await ada.next((message) => message.type === "room_snapshot"
    && message.payload.player_count === 3 && message.payload.connected?.every(Boolean));
  assert.deepEqual(trimmed.payload.player_names, ["Ada", "Ben", "Cy"]);
  const match = await latest(ben, "match_snapshot", phaseIs("role_reveal"));
  assert.equal(match.payload.mode, "cooperative");
  assert.deepEqual(match.payload.seats.map((seat) => seat.name), ["Ada", "Ben", "Cy"]);
  const retry = await connectClient(server.websocketUrl);
  t.after(() => retry.close());
  retry.send(command("resume_room", "old-token", { room_code: roomCode, reconnect_token: token, sync: true, game: true, presence: true }));
  assert.equal((await retry.next((message) => message.request_id === "old-token")).payload.code, "invalid_reconnect");
});

test("explicit start preserves the room when fewer than three players are connected", async (t) => {
  const { clients, roomCode, registry } = await gameRoom(t, 4, { presence: true });
  await Promise.all([clients[2].close(), clients[3].close()]);
  const rejected = await send(clients[0], "start_match", { drop_disconnected: true });
  assert.equal(rejected.payload.code, "not_enough_players");
  assert.deepEqual(registry.publicSnapshot(roomCode).player_names, ["Ada", "Ben", "Cy", "Dee"]);
  assert.equal(registry.publicMatchSnapshot(roomCode), null);
});

test("four browsers play a complete social match with private roles and a correct accusation", async (t) => {
  const { clients, roomCode, server } = await gameRoom(t, 4);
  const [ada, ben, cy, dee] = clients;

  const start = await send(ben, "start_match");
  assert.deepEqual(start.payload, { command: "start_match", room_code: roomCode });

  const privates = await Promise.all(clients.map((client) => latest(client, "match_private")));
  assert.deepEqual(privates.map((message) => message.payload.seat), [0, 1, 2, 3]);
  assert.equal(privates[0].payload.role, "Informant");
  assert.ok(privates.slice(1).every((message) => message.payload.role !== "Informant"));
  for (const message of privates) {
    assert.deepEqual(Object.keys(message.payload).sort(),
      ["ability", "ability_available", "ability_details", "ability_used", "accusation", "revision", "role", "room_code", "sabotage_available", "seat", "vote"]);
  }

  const publicViews = await Promise.all(clients.map((client) => latest(client, "match_snapshot", phaseIs("role_reveal"))));
  for (const view of publicViews) assert.deepEqual(view.payload, publicViews[0].payload);
  assert.equal(publicViews[0].payload.mode, "social");
  assert.deepEqual(publicViews[0].payload.seats.map((seat) => seat.name), ["Ada", "Ben", "Cy", "Dee"]);

  // No member other than Ada ever receives the Informant's identity.
  for (const client of [ben, cy, dee]) {
    assert.equal(JSON.stringify(client.messages).includes("Informant"), false);
  }

  await everyoneReady(clients, "role_reveal", 1);
  await everyoneReady(clients, "briefing", 1);
  await everyoneReady(clients, "planning", 1);
  await latest(dee, "match_snapshot", phaseIs("voting"));

  assert.equal((await send(cy, "use_ability", { round: 1 })).type, "command_result");
  const clue = await latest(cy, "match_private", (payload) => payload.ability_used === true);
  assert.match(clue.payload.ability_details, /Blackout loses 8 score/);
  assert.equal((await send(cy, "use_ability", { round: 1 })).payload.code, "ability_unavailable");
  assert.equal(ben.messages.some((message) => JSON.stringify(message).includes("Backup lighting")), false,
    "The Inside Agent's clue stays private");

  // The Informant sabotages while voting; only Ada learns it is armed.
  const sabotage = await send(ada, "cast_vote", { round: 1, plan_id: "ghost", sabotage: true });
  assert.equal(sabotage.type, "command_result");
  await latest(ada, "match_private", (payload) => payload.vote === "ghost" && payload.sabotage_available === false);
  for (const client of [ben, cy, dee]) {
    const voting = await latest(client, "match_snapshot", phaseIs("voting", (payload) => payload.progress.done === 1));
    assert.deepEqual(voting.payload.seats.map((seat) => seat.acted), [true, false, false, false]);
  }
  await allVote([ben, cy, dee], 1, "ghost");
  const resolved = await latest(cy, "match_snapshot", phaseIs("resolution", (payload) => payload.round === 1));
  assert.equal(resolved.payload.last_result.sabotage_applied, true);
  assert.equal(resolved.payload.meters.suspicion, 2);

  await everyoneReady(clients, "resolution", 1);
  await everyoneReady(clients, "planning", 2);
  await allVote(clients, 2, "social");
  await everyoneReady(clients, "resolution", 2);
  await everyoneReady(clients, "planning", 3);
  await allVote(clients, 3, "rooftop");
  await everyoneReady(clients, "resolution", 3);

  const accusation = await latest(ben, "match_snapshot", phaseIs("accusation"));
  assert.deepEqual(accusation.payload.progress, { done: 0, needed: 3 });
  assert.equal((await send(ada, "accuse", { suspect_seat: 1 })).payload.code, "not_eligible");
  for (const client of [ben, cy, dee]) {
    assert.equal((await send(client, "accuse", { suspect_seat: 0 })).type, "command_result");
  }
  const finished = await Promise.all(clients.map((client) => latest(client, "match_snapshot", phaseIs("finished"))));
  for (const view of finished) assert.deepEqual(view.payload, finished[0].payload, "Every member sees an identical recap");
  assert.equal(finished[0].payload.outcome.winner, "Crew");
  assert.equal(finished[0].payload.outcome.roles[0].role, "Informant");
  assert.equal(finished[0].payload.outcome.sabotage_used, true);
  assert.deepEqual(server.logs.filter((entry) => entry.event.startsWith("match_")).map((entry) => entry.event),
    ["match_started", "match_finished"]);
  assert.equal(JSON.stringify(server.logs).includes(ada.playerId), false, "Logs carry no player identities");
});

test("public match payloads never carry identities, credentials, or other seats' roles", async (t) => {
  const { clients } = await gameRoom(t, 4);
  await send(clients[2], "start_match");
  await Promise.all(clients.map((client) => latest(client, "match_private")));
  for (const observer of clients) {
    const leaked = observer.messages
      .filter((message) => message.type === "match_snapshot" || message.type === "match_private")
      .map((message) => JSON.stringify(message))
      .join("\n");
    for (const other of clients) {
      for (const secret of [other.playerId, other.sessionId, other.token]) {
        assert.equal(leaked.includes(secret), false, `${observer.name} received another identity`);
      }
    }
    const privateMessages = observer.messages.filter((message) => message.type === "match_private");
    assert.ok(privateMessages.every((message) => message.payload.seat === clients.indexOf(observer)));
  }
});

test("starting is validated by the authority", async (t) => {
  const { clients, roomCode, server } = await gameRoom(t, 2);
  assert.equal((await send(clients[0], "start_match")).payload.code, "not_enough_players");
  assert.equal((await send(clients[0], "ready", { phase: "role_reveal", round: 1 })).payload.code, "no_active_match");

  const legacy = await connectClient(server.websocketUrl);
  t.after(() => legacy.close());
  legacy.send(command("join_room", "legacy", { room_code: roomCode, display_name: "Cy", sync: true }));
  await legacy.next((message) => message.request_id === "legacy");
  assert.equal((await send(clients[0], "start_match")).payload.code, "incompatible_client");
  await legacy.close();
  await clients[0].next((message) => message.type === "room_snapshot" && message.payload.player_count === 2);

  const stranger = await connectClient(server.websocketUrl);
  t.after(() => stranger.close());
  assert.equal((await send(stranger, "start_match")).payload.code, "not_in_room");
  assert.equal((await send(stranger, "accuse", { suspect_seat: 0 })).payload.code, "not_in_room");

  const cy = await connectClient(server.websocketUrl);
  t.after(() => cy.close());
  cy.send(command("join_room", "cy", { room_code: roomCode, display_name: "Cy", ...CAPABILITIES }));
  await cy.next((message) => message.request_id === "cy");
  assert.equal((await send(cy, "start_match")).type, "command_result");
  assert.equal((await send(clients[0], "start_match")).payload.code, "match_in_progress");

  const late = await connectClient(server.websocketUrl);
  t.after(() => late.close());
  late.send(command("join_room", "late", { room_code: roomCode, display_name: "Dee", ...CAPABILITIES }));
  assert.equal((await late.next((message) => message.request_id === "late")).payload.code, "match_in_progress");
});

test("match commands are schema-checked, stale-safe, and idempotent per request ID", async (t) => {
  const { clients, roomCode } = await gameRoom(t, 3);
  const [ada, ben] = clients;
  await send(ada, "start_match");

  for (const payload of [
    { phase: "voting", round: 1 },
    { phase: "role_reveal", round: 0 },
    { phase: "role_reveal", round: 1, player_id: ben.playerId },
  ]) {
    assert.equal((await send(ada, "ready", payload)).payload.code, "invalid_message");
  }
  assert.equal((await send(ada, "cast_vote", { round: 1, plan_id: "Ghost" })).payload.code, "invalid_message");
  assert.equal((await send(ada, "use_ability", { round: 1, target_plan_id: "Ghost" })).payload.code, "invalid_message");
  assert.equal((await send(ada, "accuse", { suspect_seat: 4 })).payload.code, "invalid_message");
  assert.equal((await send(ada, "ready", { phase: "briefing", round: 1 })).payload.code, "stale_action");
  assert.equal((await send(ada, "use_ability", { round: 1 })).payload.code, "stale_action");

  // Replaying the same request ID returns the cached result without acting twice.
  ada.send(command("ready", "same-ready", { phase: "role_reveal", round: 1 }));
  const first = await ada.next((message) => message.request_id === "same-ready");
  const revision = (await latest(ada, "match_snapshot", (payload) => payload.progress.done === 1)).payload.revision;
  ada.clear();
  ada.send(command("ready", "same-ready", { phase: "role_reveal", round: 1 }));
  assert.deepEqual(await ada.next((message) => message.request_id === "same-ready"), first);
  // A fresh request for the same step is accepted but changes nothing.
  assert.equal((await send(ada, "ready", { phase: "role_reveal", round: 1 })).type, "command_result");
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(ada.messages.some((message) => message.type === "match_snapshot"), false, "No-op readiness is not rebroadcast");

  await everyoneReady([ben, clients[2]], "role_reveal", 1);
  const briefing = await latest(ada, "match_snapshot", phaseIs("briefing"));
  assert.ok(briefing.payload.revision > revision);
  assert.equal(briefing.payload.room_code, roomCode);

  await everyoneReady(clients, "briefing", 1);
  await everyoneReady(clients, "planning", 1);
  assert.equal((await send(ben, "cast_vote", { round: 1, plan_id: "ghost", sabotage: true })).payload.code, "sabotage_unavailable",
    "Cooperative matches have no Informant to sabotage");
  assert.equal((await send(ben, "cast_vote", { round: 1, plan_id: "drone" })).payload.code, "invalid_plan");
  assert.equal((await send(ben, "cast_vote", { round: 1, plan_id: "ghost" })).type, "command_result");
  assert.equal((await send(ben, "cast_vote", { round: 1, plan_id: "spoof" })).payload.code, "already_acted");
  assert.equal((await send(ben, "accuse", { suspect_seat: 0 })).payload.code, "stale_action");
});

test("a reserved seat recovers its private role and the current match on resume", async (t) => {
  const { clients, server } = await gameRoom(t, 3);
  const [ada, ben, cy] = clients;
  await send(ada, "start_match");
  const role = (await latest(ben, "match_private")).payload.role;
  await everyoneReady(clients, "role_reveal", 1);

  await ben.close();
  const offline = await latest(ada, "match_snapshot", (payload) => payload.seats[1].connected === false);
  assert.equal(offline.payload.phase, "briefing");
  assert.equal((await send(ada, "start_match")).payload.code, "match_in_progress");

  const resumed = await connectClient(server.websocketUrl);
  t.after(() => resumed.close());
  const result = await send(resumed, "resume_room", { room_code: ada.messages.find((m) => m.type === "room_snapshot").payload.room_code,
    reconnect_token: ben.token, sync: true, game: true });
  assert.equal(result.type, "command_result");
  const restoredPrivate = await latest(resumed, "match_private");
  assert.equal(restoredPrivate.payload.role, role);
  assert.equal(restoredPrivate.payload.seat, 1);
  const restored = await latest(resumed, "match_snapshot", phaseIs("briefing"));
  assert.equal(restored.payload.seats[1].connected, true);
  await latest(cy, "match_snapshot", (payload) => payload.seats[1].connected === true);
  await everyoneReady([ada, resumed, cy], "briefing", 1);
  await latest(resumed, "match_snapshot", phaseIs("planning"));
});

test("a reconnect restores the spent specialist ability and private clue", async (t) => {
  const { clients, roomCode, server } = await gameRoom(t, 3);
  await send(clients[0], "start_match");
  await everyoneReady(clients, "role_reveal", 1);
  await everyoneReady(clients, "briefing", 1);
  await everyoneReady(clients, "planning", 1);
  const voting = await latest(clients[0], "match_snapshot", phaseIs("voting"));
  const privateStates = await Promise.all(clients.map((client) => latest(client, "match_private", (payload) => payload.revision >= voting.payload.revision)));
  const actorIndex = privateStates.findIndex((message) => message.payload.ability_available);
  assert.ok(actorIndex >= 0);
  const actor = clients[actorIndex];
  const role = privateStates[actorIndex].payload.role;
  const payload = { round: 1, ...(role === "Hacker" ? { target_plan_id: "spoof" } : {}) };
  assert.equal((await send(actor, "use_ability", payload)).type, "command_result");
  const spent = await latest(actor, "match_private", (state) => state.ability_used);
  assert.ok(spent.payload.ability_details.length > 0);
  await actor.close();
  await latest(clients[(actorIndex + 1) % 3], "match_snapshot", (state) => !state.seats[actorIndex].connected);

  const resumed = await connectClient(server.websocketUrl);
  t.after(() => resumed.close());
  assert.equal((await send(resumed, "resume_room", { room_code: roomCode, reconnect_token: actor.token,
    sync: true, game: true })).type, "command_result");
  const restored = await latest(resumed, "match_private", (state) => state.ability_used);
  assert.equal(restored.payload.role, role);
  assert.equal(restored.payload.ability_details, spent.payload.ability_details);
  assert.equal(restored.payload.ability_available, false);
  assert.equal((await send(resumed, "use_ability", payload)).payload.code, "ability_unavailable");
});

test("a permanent departure abandons the heist without revealing roles and reopens the room", async (t) => {
  let now = 0;
  const { clients, roomCode, server } = await gameRoom(t, 4, {
    registryOptions: { clock: () => now },
    serverOptions: { sweepIntervalMs: 20 },
  });
  const [ada, ben, cy, dee] = clients;
  await send(ada, "start_match");
  await everyoneReady(clients, "role_reveal", 1);

  await dee.close();
  await latest(ada, "match_snapshot", (payload) => payload.seats[3].connected === false);
  now = RECONNECT_GRACE_MS;
  const abandoned = await Promise.all([ada, ben, cy].map((client) => latest(client, "match_snapshot", phaseIs("abandoned"))));
  for (const view of abandoned) {
    assert.match(view.payload.notice, /Dee left the room/);
    assert.equal(view.payload.outcome, null);
  }
  assert.equal(JSON.stringify(ben.messages).includes("Informant"), false);
  assert.equal((await send(ben, "ready", { phase: "briefing", round: 1 })).payload.code, "no_active_match");

  const eli = await connectClient(server.websocketUrl);
  t.after(() => eli.close());
  eli.send(command("join_room", "eli", { room_code: roomCode, display_name: "Eli", ...CAPABILITIES }));
  assert.equal((await eli.next((message) => message.request_id === "eli")).type, "command_result");
  assert.equal((await send(cy, "start_match")).type, "command_result");
  const fresh = await latest(eli, "match_snapshot", phaseIs("role_reveal"));
  assert.ok(fresh.payload.revision > abandoned[0].payload.revision, "A new match continues the room's revision sequence");

  assert.equal((await send(ben, "leave_room")).type, "command_result");
  const left = await latest(ada, "match_snapshot", (payload) => payload.revision > fresh.payload.revision && payload.phase === "abandoned");
  assert.match(left.payload.notice, /Ben left the room/);
});

test("periodic rebroadcast repairs a missed match update for each member", async (t) => {
  const { clients } = await gameRoom(t, 3, { serverOptions: { sweepIntervalMs: 20 } });
  await send(clients[0], "start_match");
  await latest(clients[1], "match_private");
  clients[1].clear();
  const [repeatedPublic, repeatedPrivate] = await Promise.all([
    latest(clients[1], "match_snapshot", phaseIs("role_reveal")),
    latest(clients[1], "match_private", (payload) => payload.seat === 1),
  ]);
  assert.equal(repeatedPublic.payload.revision, repeatedPrivate.payload.revision);
});

async function playToRecap(clients) {
  await everyoneReady(clients, "role_reveal", 1);
  await everyoneReady(clients, "briefing", 1);
  for (const [round, plan] of [[1, "ghost"], [2, "social"], [3, "rooftop"]]) {
    await everyoneReady(clients, "planning", round);
    await allVote(clients, round, plan);
    await everyoneReady(clients, "resolution", round);
  }
}

test("Play Again returns the room to waiting once everyone remaining leaves the recap", async (t) => {
  const { clients, roomCode, server } = await gameRoom(t, 4);
  const [ada, ben, cy, dee] = clients;
  await send(ada, "start_match");
  await Promise.all(clients.map((client) => latest(client, "match_private")));
  await playToRecap(clients);
  for (const client of [ben, cy, dee]) await send(client, "accuse", { suspect_seat: 0 });
  const recap = await latest(dee, "match_snapshot", phaseIs("finished"));
  assert.deepEqual(recap.payload.progress, { done: 0, needed: 4 });

  const late = await connectClient(server.websocketUrl);
  t.after(() => late.close());
  late.send(command("join_room", "late", { room_code: roomCode, display_name: "Eli", ...CAPABILITIES }));
  assert.equal((await late.next((message) => message.request_id === "late")).payload.code, "match_in_progress",
    "Nobody joins while the recap is open");
  assert.equal((await send(ben, "start_match")).payload.code, "match_in_progress");
  assert.equal((await send(ben, "ready", { phase: "finished", round: 2 })).payload.code, "stale_action");

  assert.equal((await send(ben, "ready", { phase: "finished", round: 3 })).type, "command_result");
  await latest(ada, "match_snapshot", phaseIs("finished", (payload) => payload.progress.done === 1 && payload.seats[1].ready));
  assert.equal((await send(cy, "leave_room")).type, "command_result");
  const afterLeave = await latest(ada, "match_snapshot", phaseIs("finished", (payload) => payload.progress.needed === 3));
  assert.equal(afterLeave.payload.outcome.winner, "Crew", "A departure after the recap does not abandon it");
  await send(dee, "ready", { phase: "finished", round: 3 });
  await send(ada, "ready", { phase: "finished", round: 3 });
  const closed = await Promise.all([ada, ben, dee].map((client) => latest(client, "match_snapshot", phaseIs("closed"))));
  for (const view of closed) {
    assert.equal(view.payload.outcome, null);
    assert.match(view.payload.notice, /back in the waiting room/);
  }

  late.send(command("join_room", "late-2", { room_code: roomCode, display_name: "Eli", ...CAPABILITIES }));
  assert.equal((await late.next((message) => message.request_id === "late-2")).type, "command_result");
  await latest(ada, "room_snapshot", (payload) => payload.player_names.includes("Eli"));
  assert.equal((await send(dee, "start_match")).type, "command_result");
  const fresh = await Promise.all([ada, ben, dee, late].map((client) => latest(client, "match_snapshot",
    phaseIs("role_reveal", (payload) => payload.revision > closed[0].payload.revision))));
  assert.deepEqual(fresh[0].payload.seats.map((seat) => seat.name), ["Ada", "Ben", "Dee", "Eli"]);
  assert.deepEqual(fresh[0].payload.meters.time, 12, "A new heist starts from fresh meters");
  assert.equal(fresh[0].payload.last_result, null);
  const secondPrivate = await latest(late, "match_private", (payload) => payload.revision === fresh[0].payload.revision);
  assert.equal(secondPrivate.payload.seat, 3);
  assert.equal(secondPrivate.payload.vote, null);
});
