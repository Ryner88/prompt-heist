import { randomInt } from "node:crypto";

// Server-side port of scripts/game_state.gd. The numbers, plan cards, tie rule,
// scoring formula, and win conditions must stay identical to the local game so
// pass-and-play and online matches resolve the same way.

export const TOTAL_ROUNDS = 3;
export const MAX_TIME = 12;
export const MAX_SUSPICION = 10;
export const FAILURE_SUSPICION = 7;
export const MAX_RESOURCES = 8;
export const STARTING_SUSPICION = 1;
export const STARTING_RESOURCES = 7;
export const MIN_MATCH_PLAYERS = 3;
export const SUCCESS_THRESHOLD = 70;
export const REQUIRED_SUCCESSES = 2;

export const PACING_PHASES = ["role_reveal", "briefing", "planning", "resolution"];

export const MISSION = Object.freeze({
  title: "The Neon Vault",
  objective: "Recover a stolen prototype from a private technology expo.",
  complication: "Security changes its patrol pattern every sixty seconds.",
});

export const ROUND_PLANS = Object.freeze([
  [
    { id: "ghost", title: "Ghost the Service Hall", description: "Slip through staff corridors while the expo changes shifts.", time_cost: 3, resource_cost: 1, base_success: 68, risk: 1 },
    { id: "spoof", title: "Spoof a Vendor Badge", description: "Clone credentials and walk through the front checkpoint.", time_cost: 2, resource_cost: 2, base_success: 72, risk: 2 },
    { id: "blackout", title: "Stage a Blackout", description: "Cut local power and move under emergency lighting.", time_cost: 1, resource_cost: 3, base_success: 78, risk: 3 },
  ],
  [
    { id: "drone", title: "Hijack the Camera Drone", description: "Loop its feed and use it to scout the prototype floor.", time_cost: 2, resource_cost: 2, base_success: 73, risk: 2 },
    { id: "decoy", title: "Trigger a Decoy Alarm", description: "Pull security toward the loading bay before crossing the atrium.", time_cost: 1, resource_cost: 3, base_success: 76, risk: 3 },
    { id: "social", title: "Work the VIP Crowd", description: "Blend in, trade favors, and learn the vault access phrase.", time_cost: 3, resource_cost: 1, base_success: 70, risk: 1 },
  ],
  [
    { id: "freight", title: "Escape via Freight Lift", description: "Move the prototype inside a sealed equipment case.", time_cost: 2, resource_cost: 2, base_success: 74, risk: 2 },
    { id: "rooftop", title: "Take the Rooftop Route", description: "Climb above the patrol grid and cross to the parking tower.", time_cost: 3, resource_cost: 1, base_success: 69, risk: 1 },
    { id: "motorcade", title: "Bluff the Motorcade", description: "Spend the last favors on an official-looking extraction.", time_cost: 1, resource_cost: 3, base_success: 79, risk: 3 },
  ],
].map((plans) => Object.freeze(plans.map((plan) => Object.freeze(plan)))));

export const ROLE_TEMPLATES = Object.freeze([
  { role: "Mastermind", ability: "Once per match, reveal the risk level of every proposed plan." },
  { role: "Hacker", ability: "Once per match, reduce digital-security risk by one level." },
  { role: "Driver", ability: "Once per match, cancel a failed escape consequence." },
  { role: "Inside Agent", ability: "Once per match, reveal one hidden mission complication." },
  { role: "Security Specialist", ability: "Once per match, block one point of suspicion." },
  { role: "Fixer", ability: "Once per match, recover one spent team resource." },
]);

export const INFORMANT_ROLE = Object.freeze({
  role: "Informant",
  ability: "Secretly increase suspicion while appearing to help the crew.",
});

const PUBLIC_PLAN_FIELDS = ["id", "title", "description", "time_cost", "resource_cost", "risk"];

/**
 * One authoritative heist. Seats are fixed at start; seat indexes are the only
 * player references that ever leave the server, so public payloads never carry
 * server player IDs.
 */
export class HeistMatch {
  #seats;
  #informantSeat = -1;
  #votes = new Map();
  #accusations = new Map();
  #ready = new Set();
  #sabotagePending = false;

  constructor(players, { random = randomInt } = {}) {
    if (!Array.isArray(players) || players.length < MIN_MATCH_PLAYERS || players.length > ROLE_TEMPLATES.length) {
      throw new RangeError("A match requires between three and six players.");
    }
    const roles = shuffled(ROLE_TEMPLATES, random);
    this.#seats = players.map((player, seat) => ({
      seat,
      playerId: player.playerId,
      name: player.name,
      role: roles[seat].role,
      ability: roles[seat].ability,
    }));
    // Four or more players creates the social-deduction version of the match.
    if (players.length >= 4) {
      this.#informantSeat = random(players.length);
      Object.assign(this.#seats[this.#informantSeat], INFORMANT_ROLE);
    }
    this.phase = "role_reveal";
    this.round = 1;
    this.timeRemaining = MAX_TIME;
    this.suspicion = STARTING_SUSPICION;
    this.resources = STARTING_RESOURCES;
    this.history = [];
    this.lastResult = null;
    this.sabotageUsed = false;
    this.missionFailed = false;
    this.failureReason = "";
    this.winner = "";
    this.accusationTotals = null;
    this.accusedSeat = null;
    this.accusationTied = false;
    this.notice = null;
  }

  get mode() {
    return this.#informantSeat === -1 ? "cooperative" : "social";
  }

  get seatCount() {
    return this.#seats.length;
  }

  get finished() {
    return this.phase === "finished";
  }

  /** A match that is still being played; finished and abandoned matches only hold a recap. */
  get active() {
    return this.phase !== "finished" && this.phase !== "abandoned";
  }

  /**
   * Ends an unfinished match after a seat is permanently lost. Roles stay
   * secret: the departed player may have been the Informant.
   */
  abandon(departedName) {
    if (!this.active) return false;
    this.phase = "abandoned";
    this.notice = `The heist was called off because ${departedName} left the room.`;
    this.#ready.clear();
    this.#votes.clear();
    this.#accusations.clear();
    this.#sabotagePending = false;
    return true;
  }

  seatFor(playerId) {
    return this.#seats.find((seat) => seat.playerId === playerId) ?? null;
  }

  hasPlayer(playerId) {
    return this.seatFor(playerId) !== null;
  }

  currentPlans() {
    return ROUND_PLANS[this.round - 1];
  }

  ready(playerId, phase, round) {
    const seat = this.seatFor(playerId);
    if (!seat) return failure("not_in_match");
    if (!PACING_PHASES.includes(this.phase)) return failure("stale_action");
    if (phase !== this.phase || round !== this.round) return failure("stale_action");
    if (this.#ready.has(seat.seat)) return { ok: true, changed: false };
    this.#ready.add(seat.seat);
    if (this.#ready.size === this.#seats.length) this.#advancePacing();
    return { ok: true, changed: true };
  }

  castVote(playerId, round, planId, { sabotage = false } = {}) {
    const seat = this.seatFor(playerId);
    if (!seat) return failure("not_in_match");
    if (this.phase !== "voting" || round !== this.round) return failure("stale_action");
    if (this.#votes.has(seat.seat)) return failure("already_acted");
    if (!this.currentPlans().some((plan) => plan.id === planId)) return failure("invalid_plan");
    if (sabotage) {
      if (seat.seat !== this.#informantSeat || this.sabotageUsed) return failure("sabotage_unavailable");
      this.sabotageUsed = true;
      this.#sabotagePending = true;
    }
    this.#votes.set(seat.seat, planId);
    if (this.#votes.size === this.#seats.length) this.#resolveVote();
    return { ok: true, changed: true };
  }

  accuse(playerId, suspectSeat) {
    const seat = this.seatFor(playerId);
    if (!seat) return failure("not_in_match");
    if (this.phase !== "accusation") return failure("stale_action");
    if (seat.seat === this.#informantSeat) return failure("not_eligible");
    if (!Number.isInteger(suspectSeat) || suspectSeat < 0 || suspectSeat >= this.#seats.length
      || suspectSeat === seat.seat) {
      return failure("invalid_suspect");
    }
    if (this.#accusations.has(seat.seat)) return failure("already_acted");
    this.#accusations.set(seat.seat, suspectSeat);
    if (this.#accusations.size === this.#seats.length - 1) this.#resolveAccusation();
    return { ok: true, changed: true };
  }

  /** Public view shared with every member. Contains no roles until the match is finished. */
  publicView({ connectedPlayerIds = null } = {}) {
    return {
      phase: this.phase,
      mode: this.mode,
      round: this.round,
      total_rounds: TOTAL_ROUNDS,
      meters: {
        time: this.timeRemaining,
        max_time: MAX_TIME,
        suspicion: this.suspicion,
        max_suspicion: MAX_SUSPICION,
        failure_suspicion: FAILURE_SUSPICION,
        resources: this.resources,
        max_resources: MAX_RESOURCES,
      },
      mission: { ...MISSION },
      plans: this.currentPlans().map((plan) => pick(plan, PUBLIC_PLAN_FIELDS)),
      seats: this.#seats.map((seat) => ({
        seat: seat.seat,
        name: seat.name,
        connected: connectedPlayerIds ? connectedPlayerIds.has(seat.playerId) : true,
        ready: PACING_PHASES.includes(this.phase) && this.#ready.has(seat.seat),
        // Per-seat accusation progress would single out the Informant, who
        // cannot vote, so that phase reports only the aggregate below.
        acted: this.phase === "voting" && this.#votes.has(seat.seat),
      })),
      progress: this.#progress(),
      last_result: this.lastResult ? structuredClone(this.lastResult) : null,
      outcome: this.finished ? this.#outcome() : null,
      notice: this.notice,
    };
  }

  /** Private view for exactly one seat. */
  privateView(playerId) {
    const seat = this.seatFor(playerId);
    if (!seat) return null;
    const informant = seat.seat === this.#informantSeat;
    return {
      seat: seat.seat,
      role: seat.role,
      ability: seat.ability,
      sabotage_available: informant && this.phase === "voting" && !this.sabotageUsed && !this.#votes.has(seat.seat),
      vote: this.phase === "voting" ? this.#votes.get(seat.seat) ?? null : null,
      accusation: this.phase === "accusation" ? this.#accusations.get(seat.seat) ?? null : null,
    };
  }

  #progress() {
    if (PACING_PHASES.includes(this.phase)) return { done: this.#ready.size, needed: this.#seats.length };
    if (this.phase === "voting") return { done: this.#votes.size, needed: this.#seats.length };
    if (this.phase === "accusation") return { done: this.#accusations.size, needed: this.#seats.length - 1 };
    return { done: 0, needed: 0 };
  }

  #advancePacing() {
    this.#ready.clear();
    if (this.phase === "role_reveal") {
      this.phase = "briefing";
    } else if (this.phase === "briefing") {
      this.phase = "planning";
    } else if (this.phase === "planning") {
      this.#votes.clear();
      this.phase = "voting";
    } else if (this.phase === "resolution") {
      this.#advanceAfterResolution();
    }
  }

  #resolveVote() {
    const plans = this.currentPlans();
    const tallies = Object.fromEntries(plans.map((plan) => [plan.id, 0]));
    for (const planId of this.#votes.values()) tallies[planId] += 1;

    let highestVotes = 0;
    let leaders = [];
    for (const plan of plans) {
      const count = tallies[plan.id];
      if (count > highestVotes) {
        highestVotes = count;
        leaders = [plan.id];
      } else if (count === highestVotes) {
        leaders.push(plan.id);
      }
    }

    // Ties are deterministic: the lowest-risk tied plan wins, then card order.
    let selected = plans.find((plan) => plan.id === leaders[0]);
    for (const plan of plans) {
      if (leaders.includes(plan.id) && plan.risk < selected.risk) selected = plan;
    }

    let score = selected.base_success + this.resources * 3 - this.suspicion * 4;
    if (this.resources < selected.resource_cost) score -= (selected.resource_cost - this.resources) * 15;
    if (this.timeRemaining < selected.time_cost) score -= (selected.time_cost - this.timeRemaining) * 20;
    score = Math.min(95, Math.max(5, score));
    const success = score >= SUCCESS_THRESHOLD;

    this.timeRemaining = Math.max(0, this.timeRemaining - selected.time_cost);
    this.resources = Math.max(0, this.resources - selected.resource_cost);
    if (success) {
      this.suspicion = Math.max(0, this.suspicion + selected.risk - 2);
    } else {
      this.suspicion = Math.min(MAX_SUSPICION, this.suspicion + selected.risk + 1);
      this.resources = Math.max(0, this.resources - 1);
    }

    const sabotageApplied = this.#sabotagePending;
    if (sabotageApplied) {
      this.suspicion = Math.min(MAX_SUSPICION, this.suspicion + 2);
      this.#sabotagePending = false;
    }

    this.#evaluateMissionFailure();
    let consequence = success
      ? `${selected.title} works. The crew stays ahead of security and preserves momentum.`
      : `${selected.title} breaks down under pressure. Security closes in and an extra resource is lost.`;
    if (sabotageApplied) consequence += " An unexplained complication raises suspicion by 2.";

    this.lastResult = {
      round: this.round,
      plan_id: selected.id,
      plan_title: selected.title,
      tallies,
      was_tie: leaders.length > 1,
      score,
      success,
      sabotage_applied: sabotageApplied,
      consequence,
      mission_failed: this.missionFailed,
      failure_reason: this.failureReason,
    };
    this.history.push({ round: this.round, plan_title: selected.title, success, score });
    this.#votes.clear();
    this.#ready.clear();
    this.phase = "resolution";
  }

  #advanceAfterResolution() {
    if (this.missionFailed) {
      this.#finish(this.#informantSeat !== -1 ? "Informant" : "Nobody");
      return;
    }
    if (this.round >= TOTAL_ROUNDS) {
      if (this.#successfulRounds() < REQUIRED_SUCCESSES) {
        this.missionFailed = true;
        this.failureReason = "The crew failed too many mission plans.";
        this.#finish(this.#informantSeat !== -1 ? "Informant" : "Nobody");
      } else if (this.#informantSeat !== -1) {
        this.#accusations.clear();
        this.phase = "accusation";
      } else {
        this.#finish("Everyone");
      }
      return;
    }
    this.round += 1;
    this.phase = "planning";
  }

  #resolveAccusation() {
    const totals = this.#seats.map(() => 0);
    for (const suspect of this.#accusations.values()) totals[suspect] += 1;
    let highestVotes = 0;
    let leaders = [];
    for (const seat of this.#seats) {
      const total = totals[seat.seat];
      if (total > highestVotes) {
        highestVotes = total;
        leaders = [seat.seat];
      } else if (total === highestVotes && total > 0) {
        leaders.push(seat.seat);
      }
    }
    this.accusationTotals = totals;
    this.accusationTied = leaders.length !== 1;
    this.accusedSeat = this.accusationTied ? null : leaders[0];
    const correct = !this.accusationTied && this.accusedSeat === this.#informantSeat;
    this.#finish(correct ? "Crew" : "Informant");
  }

  #evaluateMissionFailure() {
    if (this.timeRemaining <= 0) {
      this.missionFailed = true;
      this.failureReason = "The crew ran out of time.";
    } else if (this.suspicion >= FAILURE_SUSPICION) {
      this.missionFailed = true;
      this.failureReason = "Security identified the crew.";
    } else if (this.resources <= 0) {
      this.missionFailed = true;
      this.failureReason = "The crew exhausted its operational resources.";
    }
  }

  #finish(winner) {
    this.winner = winner;
    this.#ready.clear();
    this.phase = "finished";
  }

  #successfulRounds() {
    return this.history.filter((entry) => entry.success).length;
  }

  #outcome() {
    return {
      winner: this.winner,
      mission_failed: this.missionFailed,
      failure_reason: this.failureReason,
      successful_rounds: this.#successfulRounds(),
      sabotage_used: this.sabotageUsed,
      roles: this.#seats.map((seat) => ({ seat: seat.seat, role: seat.role })),
      history: structuredClone(this.history),
      accusation: this.accusationTotals
        ? { totals: [...this.accusationTotals], tied: this.accusationTied, accused_seat: this.accusedSeat }
        : null,
    };
  }
}

function shuffled(items, random) {
  const copy = items.map((item) => ({ ...item }));
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swap = random(index + 1);
    [copy[index], copy[swap]] = [copy[swap], copy[index]];
  }
  return copy;
}

function pick(source, keys) {
  return Object.fromEntries(keys.map((key) => [key, source[key]]));
}

function failure(code) {
  return { ok: false, code };
}
