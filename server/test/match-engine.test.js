import assert from "node:assert/strict";
import test from "node:test";
import {
  FAILURE_SUSPICION,
  HeistMatch,
  MAX_TIME,
  ROUND_PLANS,
  ROLE_TEMPLATES,
  STARTING_RESOURCES,
  STARTING_SUSPICION,
} from "../src/match-engine.js";

// random(n) always returns 0: the role shuffle is deterministic and, with four
// or more players, seat 0 becomes the Informant.
const zero = () => 0;

function players(count) {
  return Array.from({ length: count }, (_, index) => ({ playerId: `p${index}`, name: `Player ${index + 1}` }));
}

function readyAll(match, phase = match.phase) {
  for (let seat = 0; seat < match.seatCount; seat += 1) {
    assert.equal(match.ready(`p${seat}`, phase, match.round).ok, true);
  }
}

function votingMatch(count, options = { random: zero }) {
  const match = new HeistMatch(players(count), options);
  readyAll(match); // role reveal
  readyAll(match); // briefing
  readyAll(match); // planning
  assert.equal(match.phase, "voting");
  return match;
}

function voteAll(match, planId) {
  for (let seat = 0; seat < match.seatCount; seat += 1) {
    assert.equal(match.castVote(`p${seat}`, match.round, planId).ok, true);
  }
  return match.lastResult;
}

function playRounds(match, planIds) {
  for (const planId of planIds) {
    if (match.phase !== "planning" && match.phase !== "voting") return;
    if (match.phase === "planning") readyAll(match);
    voteAll(match, planId);
    readyAll(match, "resolution");
  }
}

test("match size boundaries, starting meters, and cooperative versus social roles", () => {
  assert.throws(() => new HeistMatch(players(2)), RangeError);
  assert.throws(() => new HeistMatch(players(7)), RangeError);
  const cooperative = new HeistMatch(players(3), { random: zero });
  assert.equal(cooperative.mode, "cooperative");
  assert.equal(cooperative.phase, "role_reveal");
  assert.deepEqual([cooperative.timeRemaining, cooperative.suspicion, cooperative.resources], [MAX_TIME, STARTING_SUSPICION, STARTING_RESOURCES]);
  assert.ok([0, 1, 2].every((seat) => cooperative.privateView(`p${seat}`).role !== "Informant"));

  const social = new HeistMatch(players(4), { random: zero });
  assert.equal(social.mode, "social");
  const roles = [0, 1, 2, 3].map((seat) => social.privateView(`p${seat}`).role);
  assert.equal(roles.filter((role) => role === "Informant").length, 1);
  assert.equal(new Set(roles).size, 4, "Every seat receives a distinct role");

  const six = new HeistMatch(players(6));
  assert.equal([0, 1, 2, 3, 4, 5].filter((seat) => six.privateView(`p${seat}`).role === "Informant").length, 1);
});

test("pacing requires every seat and rejects stale or unknown readiness", () => {
  const match = new HeistMatch(players(3), { random: zero });
  assert.equal(match.ready("p0", "briefing", 1).code, "stale_action");
  assert.equal(match.ready("p0", "role_reveal", 2).code, "stale_action");
  assert.equal(match.ready("nobody", "role_reveal", 1).code, "not_in_match");
  assert.deepEqual(match.ready("p0", "role_reveal", 1), { ok: true, changed: true });
  assert.deepEqual(match.ready("p0", "role_reveal", 1), { ok: true, changed: false }, "Repeated readiness is a no-op");
  assert.deepEqual(match.publicView().progress, { done: 1, needed: 3 });
  match.ready("p1", "role_reveal", 1);
  assert.equal(match.phase, "role_reveal");
  match.ready("p2", "role_reveal", 1);
  assert.equal(match.phase, "briefing");
  assert.ok(match.publicView().seats.every((seat) => seat.ready === false), "Readiness resets for the next step");
  assert.equal(match.castVote("p0", 1, "ghost").code, "stale_action", "Voting is not open during briefing");
});

test("vote validation and the lowest-risk tie rule match the local game", () => {
  const match = votingMatch(4);
  assert.equal(match.castVote("p0", 1, "missing").code, "invalid_plan");
  assert.equal(match.castVote("p0", 2, "ghost").code, "stale_action");
  assert.equal(match.castVote("p0", 1, "ghost").ok, true);
  assert.equal(match.castVote("p0", 1, "spoof").code, "already_acted");
  assert.equal(match.privateView("p0").vote, "ghost");
  assert.equal(match.privateView("p1").vote, null);
  match.castVote("p1", 1, "spoof");
  match.castVote("p2", 1, "ghost");
  match.castVote("p3", 1, "spoof");
  const result = match.lastResult;
  assert.equal(result.was_tie, true);
  assert.equal(result.plan_id, "ghost", "A 2–2 tie selects the lower-risk plan");
  assert.deepEqual(result.tallies, { ghost: 2, spoof: 2, blackout: 0 });
  assert.equal(match.phase, "resolution");
  readyAll(match, "resolution");
  assert.equal(match.round, 2);
  assert.equal(match.phase, "planning");
});

test("scoring and meter changes reproduce the GDScript formula", () => {
  // Round 1 ghost: 68 + 7*3 - 1*4 = 85 → success.
  const match = votingMatch(3);
  const ghost = voteAll(match, "ghost");
  assert.equal(ghost.score, 85);
  assert.equal(ghost.success, true);
  assert.deepEqual([match.timeRemaining, match.resources, match.suspicion], [9, 6, 0]);

  // Penalties: short of resources and time, clamped at 5.
  const starved = votingMatch(3);
  starved.resources = 1;
  starved.timeRemaining = 1;
  starved.suspicion = 6;
  const blackout = voteAll(starved, "blackout");
  // The hidden blackout complication subtracts 8 before score clamping.
  assert.equal(blackout.score, 19);
  assert.equal(blackout.success, false);
  assert.equal(starved.missionFailed, true);
  assert.equal(starved.failureReason, "The crew ran out of time.", "Time is checked before suspicion and resources");

  const clamped = votingMatch(3);
  clamped.resources = 0;
  clamped.timeRemaining = 0;
  clamped.suspicion = 10;
  assert.equal(voteAll(clamped, "ghost").score, 5);
});

test("terminal meter thresholds fail immediately", () => {
  const time = votingMatch(3);
  time.timeRemaining = 3;
  voteAll(time, "ghost");
  assert.equal(time.failureReason, "The crew ran out of time.");

  const suspicion = votingMatch(3);
  suspicion.suspicion = FAILURE_SUSPICION - 1;
  voteAll(suspicion, "blackout");
  assert.ok(suspicion.missionFailed && suspicion.suspicion >= FAILURE_SUSPICION);
  assert.equal(suspicion.failureReason, "Security identified the crew.");

  const resources = votingMatch(3);
  resources.resources = 1;
  voteAll(resources, "ghost");
  assert.equal(resources.resources, 0);
  assert.equal(resources.failureReason, "The crew exhausted its operational resources.");
  readyAll(resources, "resolution");
  assert.equal(resources.phase, "finished");
  assert.equal(resources.winner, "Nobody");
});

test("sabotage is Informant-only, single use, private, and adds two suspicion", () => {
  const match = votingMatch(4);
  assert.equal(match.privateView("p0").role, "Informant");
  assert.equal(match.privateView("p0").sabotage_available, true);
  assert.equal(match.privateView("p1").sabotage_available, false);
  assert.equal(match.castVote("p1", 1, "ghost", { sabotage: true }).code, "sabotage_unavailable");
  assert.equal(match.privateView("p1").vote, null, "A rejected sabotage does not cast the vote");
  assert.equal(match.castVote("p0", 1, "ghost", { sabotage: true }).ok, true);
  assert.equal(match.privateView("p0").sabotage_available, false);
  const view = JSON.stringify(match.publicView());
  assert.equal(view.includes("sabotage_used"), false, "Pending sabotage stays out of the public view");
  for (const seat of [1, 2, 3]) match.castVote(`p${seat}`, 1, "ghost");
  assert.equal(match.lastResult.sabotage_applied, true);
  assert.equal(match.suspicion, 2, "Ghost success lowers suspicion to 0, then sabotage adds 2");
  assert.match(match.lastResult.consequence, /raises suspicion by 2/);

  readyAll(match, "resolution");
  readyAll(match);
  assert.equal(match.castVote("p0", 2, "drone", { sabotage: true }).code, "sabotage_unavailable");
});

test("every unanimous three-round plan sequence reaches a deterministic cooperative outcome", () => {
  const outcomes = { Everyone: 0, Nobody: 0 };
  for (const first of ROUND_PLANS[0]) {
    for (const second of ROUND_PLANS[1]) {
      for (const third of ROUND_PLANS[2]) {
        const match = votingMatch(3);
        playRounds(match, [first.id, second.id, third.id]);
        assert.equal(match.phase, "finished");
        outcomes[match.winner] += 1;
        assert.equal(match.publicView().outcome.winner, match.winner);
      }
    }
  }
  assert.equal(outcomes.Everyone + outcomes.Nobody, 27);
  assert.ok(outcomes.Everyone > 0 && outcomes.Nobody > 0, "Both cooperative endings remain reachable (QA issue #3)");
});

test("winning cooperative and social matches end in the right phase", () => {
  const cooperative = votingMatch(3);
  playRounds(cooperative, ["ghost", "social", "rooftop"]);
  assert.equal(cooperative.winner, "Everyone");
  assert.equal(cooperative.publicView().outcome.successful_rounds, 3);

  const social = votingMatch(4);
  playRounds(social, ["ghost", "social", "rooftop"]);
  assert.equal(social.phase, "accusation");
  assert.deepEqual(social.publicView().progress, { done: 0, needed: 3 });
});

test("accusation outcomes, eligibility, and secrecy", () => {
  const caught = votingMatch(4);
  playRounds(caught, ["ghost", "social", "rooftop"]);
  assert.equal(caught.accuse("p0", 1).code, "not_eligible", "The Informant cannot vote");
  assert.equal(caught.accuse("p1", 1).code, "invalid_suspect", "Players cannot accuse themselves");
  assert.equal(caught.accuse("p1", 9).code, "invalid_suspect");
  assert.equal(caught.accuse("p1", 0).ok, true);
  assert.equal(caught.accuse("p1", 2).code, "already_acted");
  const midAccusation = caught.publicView();
  assert.ok(midAccusation.seats.every((seat) => seat.acted === false), "Per-seat accusation progress would expose the Informant");
  assert.equal(midAccusation.outcome, null);
  assert.equal(JSON.stringify(midAccusation).includes("Informant"), false);
  caught.accuse("p2", 0);
  caught.accuse("p3", 0);
  assert.equal(caught.winner, "Crew");
  assert.deepEqual(caught.publicView().outcome.accusation, { totals: [3, 0, 0, 0], tied: false, accused_seat: 0 });
  assert.equal(caught.publicView().outcome.roles[0].role, "Informant", "Roles are revealed only after the match ends");

  const wrong = votingMatch(4);
  playRounds(wrong, ["ghost", "social", "rooftop"]);
  wrong.accuse("p1", 2);
  wrong.accuse("p2", 3);
  wrong.accuse("p3", 2);
  assert.equal(wrong.winner, "Informant");
  assert.equal(wrong.publicView().outcome.accusation.accused_seat, 2);

  const tied = votingMatch(4);
  playRounds(tied, ["ghost", "social", "rooftop"]);
  tied.accuse("p1", 2);
  tied.accuse("p2", 3);
  tied.accuse("p3", 1);
  assert.equal(tied.winner, "Informant", "A three-way tie selects nobody");
  assert.equal(tied.publicView().outcome.accusation.tied, true);
  assert.equal(tied.publicView().outcome.accusation.accused_seat, null);
  assert.equal(tied.accuse("p1", 0).code, "stale_action");
});

test("the public view never carries roles, player IDs, votes, or pending sabotage before the end", () => {
  const match = votingMatch(4);
  match.castVote("p0", 1, "blackout", { sabotage: true });
  const view = match.publicView();
  const serialized = JSON.stringify(view);
  for (const secret of ["\"p0\"", "\"p1\"", "Informant", "Mastermind", "Hacker", "base_success", "sabotage_used", "\"vote\""]) {
    assert.equal(serialized.includes(secret), false, `Public view leaked ${secret}`);
  }
  assert.deepEqual(Object.keys(view.plans[0]).sort(), ["description", "id", "resource_cost", "risk", "time_cost", "title"]);
  assert.deepEqual(view.seats.map((seat) => seat.acted), [true, false, false, false]);
  assert.equal(view.last_result, null, "Plan choices are revealed only as tallies at resolution");
});

test("abandoning ends only an unfinished match and keeps roles secret", () => {
  const match = votingMatch(4);
  match.castVote("p0", 1, "ghost", { sabotage: true });
  assert.equal(match.abandon("Player 2"), true);
  assert.equal(match.phase, "abandoned");
  assert.equal(match.active, false);
  const view = match.publicView();
  assert.equal(view.outcome, null);
  assert.match(view.notice, /Player 2 left/);
  assert.equal(JSON.stringify(view).includes("Informant"), false);
  assert.equal(match.castVote("p1", 1, "ghost").code, "stale_action");
  assert.equal(match.abandon("Player 3"), false);

  const finished = votingMatch(3);
  playRounds(finished, ["ghost", "social", "rooftop"]);
  assert.equal(finished.abandon("Player 1"), false, "A finished recap is preserved");
  assert.equal(finished.phase, "finished");
});

test("after the recap, the match closes once every remaining seat asks to return", () => {
  const match = votingMatch(4);
  assert.equal(match.ready("p1", "finished", 1).code, "stale_action", "Returning is only possible from the recap");
  playRounds(match, ["ghost", "social", "rooftop"]);
  for (const seat of [1, 2, 3]) match.accuse(`p${seat}`, 0);
  assert.equal(match.phase, "finished");
  assert.equal(match.holdsRoom, true);
  const everyone = new Set(["p0", "p1", "p2", "p3"]);
  assert.deepEqual(match.ready("p1", "finished", 3), { ok: true, changed: true });
  assert.deepEqual(match.ready("p1", "finished", 3), { ok: true, changed: false });
  assert.equal(match.closeIfReady(everyone), false);
  const pending = match.publicView({ presentPlayerIds: everyone });
  assert.deepEqual(pending.progress, { done: 1, needed: 4 });
  assert.deepEqual(pending.seats.map((seat) => seat.ready), [false, true, false, false]);
  assert.equal(pending.outcome.winner, "Crew", "The recap stays visible while others finish reading");

  match.ready("p2", "finished", 3);
  const remaining = new Set(["p1", "p2", "p3"]);
  assert.deepEqual(match.publicView({ presentPlayerIds: remaining }).progress, { done: 2, needed: 3 },
    "Seats that left do not count toward the return");
  match.ready("p3", "finished", 3);
  assert.equal(match.closeIfReady(remaining), true);
  assert.equal(match.phase, "closed");
  assert.equal(match.holdsRoom, false);
  const closed = match.publicView({ presentPlayerIds: remaining });
  assert.equal(closed.outcome, null, "Closing clears the recap");
  assert.match(closed.notice, /back in the waiting room/);
  assert.equal(match.ready("p1", "finished", 3).code, "stale_action");
  assert.equal(match.closeIfReady(remaining), false);
  assert.equal(match.abandon("Player 2"), false, "A closed match cannot be abandoned");
});

function abilityMatch(role) {
  const roleSeat = ROLE_TEMPLATES.findIndex((entry) => entry.role === role);
  const informantSeat = roleSeat === 5 ? 0 : 5;
  let calls = 0;
  const random = (n) => (++calls <= 5 ? n - 1 : informantSeat);
  const match = votingMatch(6, { random });
  assert.equal(match.privateView(`p${roleSeat}`).role, role);
  return { match, playerId: `p${roleSeat}` };
}

test("information abilities are private, one-use, and reveal current-round facts", () => {
  const mastermind = abilityMatch("Mastermind");
  assert.equal(mastermind.match.useAbility(mastermind.playerId, 1).ok, true);
  assert.match(mastermind.match.privateView(mastermind.playerId).ability_details, /base success 68\/100/);
  assert.equal(mastermind.match.privateView("p1").ability_details, "");
  assert.doesNotMatch(JSON.stringify(mastermind.match.publicView()), /base_success|Mastermind/);
  assert.equal(mastermind.match.useAbility(mastermind.playerId, 1).code, "ability_unavailable");
  assert.equal(mastermind.match.useAbility("p5", 1).code, "ability_unavailable", "Informant cannot use a crew ability");

  const agent = abilityMatch("Inside Agent");
  assert.equal(agent.match.useAbility(agent.playerId, 1).ok, true);
  assert.match(agent.match.privateView(agent.playerId).ability_details, /Blackout loses 8 score/);
  assert.doesNotMatch(JSON.stringify(agent.match.publicView()), /Backup lighting/);
  const result = voteAll(agent.match, "blackout");
  assert.equal(result.score, 87, "The revealed complication actually changes resolution");
  assert.match(result.consequence, /Backup lighting/);
});

test("Hacker, Fixer, Security Specialist, and Driver change the authoritative outcome", () => {
  const hacker = abilityMatch("Hacker");
  assert.equal(hacker.match.useAbility(hacker.playerId, 1, "ghost").code, "invalid_ability_target");
  assert.equal(hacker.match.useAbility(hacker.playerId, 1, "spoof").ok, true);
  assert.equal(hacker.match.publicView().plans.find((plan) => plan.id === "spoof").risk, 1);
  voteAll(hacker.match, "spoof");
  assert.equal(hacker.match.suspicion, 0);
  assert.equal(hacker.match.publicView().plans.find((plan) => plan.id === "spoof").risk, 2,
    "The risk reduction ends after this round");

  const fixer = abilityMatch("Fixer");
  assert.equal(fixer.match.useAbility(fixer.playerId, 1).ok, true);
  assert.equal(fixer.match.resources, 8);
  assert.equal(voteAll(fixer.match, "ghost").score, 88);
  assert.equal(fixer.match.resources, 7);

  const specialist = abilityMatch("Security Specialist");
  assert.equal(specialist.match.useAbility(specialist.playerId, 1).ok, true);
  for (let seat = 0; seat < 6; seat += 1) {
    assert.equal(specialist.match.castVote(`p${seat}`, 1, "blackout", { sabotage: seat === 5 }).ok, true);
  }
  assert.equal(specialist.match.lastResult.sabotage_applied, true);
  assert.equal(specialist.match.suspicion, 3, "Protection blocks one point after sabotage is added");
  assert.match(specialist.match.lastResult.consequence, /blocked one suspicion/);

  const driver = abilityMatch("Driver");
  assert.equal(driver.match.useAbility(driver.playerId, 1).code, "ability_unavailable");
  playRounds(driver.match, ["ghost", "social"]);
  driver.match.resources = 4;
  driver.match.suspicion = 4;
  readyAll(driver.match, "planning");
  assert.equal(driver.match.useAbility(driver.playerId, 3).ok, true);
  assert.equal(voteAll(driver.match, "motorcade").success, false);
  assert.equal(driver.match.resources, 1, "Driver prevents the extra resource loss on failure");
  assert.match(driver.match.lastResult.consequence, /Driver prevents/);
});
