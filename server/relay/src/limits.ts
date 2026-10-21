// Rate limiters driven by an injected clock (milliseconds).

/** Token bucket: `ratePerS` tokens a second up to `burst`; starts full. */
export class TokenBucket {
  readonly ratePerS: number;
  readonly burst: number;
  #tokens: number;
  #last: number;

  constructor(ratePerS: number, burst: number, nowMs: number) {
    this.ratePerS = ratePerS;
    this.burst = burst;
    this.#tokens = burst;
    this.#last = nowMs;
  }

  /** Take one token; false (and nothing taken) when the bucket is empty. */
  take(nowMs: number): boolean {
    this.#refill(nowMs);
    if (this.#tokens < 1) return false;
    this.#tokens -= 1;
    return true;
  }

  tokens(nowMs: number): number {
    this.#refill(nowMs);
    return this.#tokens;
  }

  #refill(nowMs: number): void {
    const dt = nowMs - this.#last;
    if (dt > 0) {
      this.#tokens = Math.min(this.burst, this.#tokens + (dt * this.ratePerS) / 1000);
      this.#last = nowMs;
    }
  }
}

/** At most `limit` events per sliding `windowMs`, counted per key (an IP address). */
export class SlidingWindowLimiter {
  readonly limit: number;
  readonly windowMs: number;
  #events = new Map<string, number[]>();

  constructor(limit: number, windowMs: number) {
    this.limit = limit;
    this.windowMs = windowMs;
  }

  /** Record an event for `key` and return true, or return false (nothing recorded). */
  allow(key: string, nowMs: number): boolean {
    const list = this.#prune(key, nowMs);
    if (list.length >= this.limit) return false;
    list.push(nowMs);
    this.#events.set(key, list);
    return true;
  }

  /** Forget keys with no event inside the window (call from the periodic sweep). */
  sweep(nowMs: number): void {
    for (const key of [...this.#events.keys()]) {
      if (this.#prune(key, nowMs).length === 0) this.#events.delete(key);
    }
  }

  get size(): number {
    return this.#events.size;
  }

  #prune(key: string, nowMs: number): number[] {
    const list = this.#events.get(key) ?? [];
    let drop = 0;
    while (drop < list.length && nowMs - list[drop] >= this.windowMs) drop++;
    if (drop > 0) list.splice(0, drop);
    return list;
  }
}
