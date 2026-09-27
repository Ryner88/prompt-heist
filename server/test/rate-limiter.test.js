import assert from "node:assert/strict";
import test from "node:test";
import { FixedWindowRateLimiter } from "../src/rate-limiter.js";

test("rate limiter allows the boundary, rejects one too many, and resets at the window", () => {
  let now = 100;
  const limiter = new FixedWindowRateLimiter({ limit: 2, windowMs: 10, now: () => now });
  assert.equal(limiter.consume(), true);
  assert.equal(limiter.consume(), true);
  assert.equal(limiter.consume(), false);
  now = 109;
  assert.equal(limiter.consume(), false);
  now = 110;
  assert.equal(limiter.consume(), true);
});
