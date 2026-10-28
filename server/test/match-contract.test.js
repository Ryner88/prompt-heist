import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import test from "node:test";
import { response } from "../src/protocol.js";
import { RoomRegistry } from "../src/room-registry.js";

// tests/fixtures/match_contract.json is the cross-language contract: this test
// regenerates real server payloads and fails if the file drifts, and the Godot
// suite validates every payload in it. Regenerate with:
//   UPDATE_MATCH_FIXTURES=1 node --test server/test/match-contract.test.js
const FIXTURE = new URL("../../tests/fixtures/match_contract.json", import.meta.url);

function buildContract() {
  let id = 0;
  const contract = { valid_public: {}, valid_private: {} };
  const capture = (registry, label) => {
    contract.valid_public[label] = response("match_snapshot", registry.publicMatchSnapshot("ABC234"));
  };
  const seats = (count, registry) => {
    const connections = ["a", "b", "c", "d"].slice(0, count);
    registry.createRoom("Ada", "a", { reconnect: true, game: true });
    ["Ben", "Cy", "Dee"].slice(0, count - 1).forEach((name, index) => {
      registry.joinRoom("ABC234", name, connections[index + 1], { reconnect: true, game: true });
    });
    assert.equal(registry.startMatch("b").ok, true);
    return connections;
  };
  const act = (registry, connections, fn) => {
    for (const connection of connections) assert.equal(registry.matchAction(connection, fn).ok, true);
  };
  const ready = (registry, connections, phase, round) => act(registry, connections, (match, player) => match.ready(player, phase, round));
  const vote = (registry, connections, round, plan) => act(registry, connections, (match, player) => match.castVote(player, round, plan));
  const makeRegistry = () => new RoomRegistry({
    codeGenerator: () => "ABC234",
    idGenerator: () => `id-${(id += 1)}`,
    tokenGenerator: () => `${"T".repeat(37)}${String((id += 1)).padStart(6, "0")}`,
    matchRandom: () => 0,
  });

  const social = makeRegistry();
  const four = seats(4, social);
  capture(social, "social_role_reveal");
  contract.valid_private.informant = response("match_private", social.privateMatchState("a"));
  contract.valid_private.crew = response("match_private", social.privateMatchState("b"));
  ready(social, four, "role_reveal", 1);
  ready(social, four, "briefing", 1);
  ready(social, four, "planning", 1);
  assert.equal(social.matchAction("a", (match, player) => match.castVote(player, 1, "ghost", { sabotage: true })).ok, true);
  capture(social, "social_voting");
  contract.valid_private.informant_voted = response("match_private", social.privateMatchState("a"));
  vote(social, four.slice(1), 1, "ghost");
  capture(social, "social_resolution_sabotaged");
  ready(social, four, "resolution", 1);
  ready(social, four, "planning", 2);
  vote(social, four, 2, "social");
  ready(social, four, "resolution", 2);
  ready(social, four, "planning", 3);
  vote(social, four, 3, "rooftop");
  ready(social, four, "resolution", 3);
  social.matchAction("b", (match, player) => match.accuse(player, 0));
  capture(social, "social_accusation");
  contract.valid_private.crew_accused = response("match_private", social.privateMatchState("b"));
  social.matchAction("c", (match, player) => match.accuse(player, 0));
  social.matchAction("d", (match, player) => match.accuse(player, 0));
  capture(social, "social_finished_crew_wins");
  assert.equal(social.matchAction("b", (match, player) => match.ready(player, "finished", 3)).ok, true);
  capture(social, "social_finished_rematch_pending");
  ready(social, ["a", "c", "d"], "finished", 3);
  capture(social, "closed");

  const cooperative = makeRegistry();
  const three = seats(3, cooperative);
  ready(cooperative, three, "role_reveal", 1);
  ready(cooperative, three, "briefing", 1);
  ready(cooperative, three, "planning", 1);
  cooperative.removeConnection("c");
  capture(cooperative, "cooperative_voting_seat_offline");

  const failed = makeRegistry();
  const crew = seats(3, failed);
  ready(failed, crew, "role_reveal", 1);
  ready(failed, crew, "briefing", 1);
  ready(failed, crew, "planning", 1);
  vote(failed, crew, 1, "blackout");
  ready(failed, crew, "resolution", 1);
  ready(failed, crew, "planning", 2);
  vote(failed, crew, 2, "decoy");
  ready(failed, crew, "resolution", 2);
  ready(failed, crew, "planning", 3);
  vote(failed, crew, 3, "motorcade");
  capture(failed, "cooperative_resolution_failed");
  ready(failed, crew, "resolution", 3);
  capture(failed, "cooperative_finished_no_accusation");

  const abandoned = makeRegistry();
  seats(3, abandoned);
  abandoned.leaveRoom("c");
  capture(abandoned, "abandoned");
  return contract;
}

test("checked-in match contract fixtures equal the payloads the server sends", () => {
  const contract = buildContract();
  const serialized = `${JSON.stringify(contract, null, 2)}\n`;
  if (process.env.UPDATE_MATCH_FIXTURES === "1") writeFileSync(FIXTURE, serialized);
  assert.equal(readFileSync(FIXTURE, "utf8"), serialized,
    "Match payloads changed; update the Godot validators and regenerate tests/fixtures/match_contract.json");
  assert.equal(contract.valid_public.cooperative_finished_no_accusation.payload.outcome.winner, "Nobody");
  assert.equal(contract.valid_public.cooperative_resolution_failed.payload.last_result.mission_failed, true);
  assert.equal(contract.valid_public.social_finished_crew_wins.payload.outcome.winner, "Crew");
  assert.deepEqual(contract.valid_public.social_finished_rematch_pending.payload.progress, { done: 1, needed: 4 });
  assert.equal(contract.valid_public.closed.payload.phase, "closed");
});
