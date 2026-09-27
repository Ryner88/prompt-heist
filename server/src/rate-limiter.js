import { RATE_LIMIT_COMMANDS, RATE_LIMIT_WINDOW_MS } from "./constants.js";

export class FixedWindowRateLimiter {
  constructor({ limit = RATE_LIMIT_COMMANDS, windowMs = RATE_LIMIT_WINDOW_MS, now = Date.now } = {}) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
    this.windowStartedAt = now();
    this.count = 0;
  }

  consume() {
    const current = this.now();
    if (current - this.windowStartedAt >= this.windowMs) {
      this.windowStartedAt = current;
      this.count = 0;
    }
    this.count += 1;
    return this.count <= this.limit;
  }
}
