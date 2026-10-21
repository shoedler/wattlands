// Time source for every relay rule (idle timeout, rate limits, reconnect tokens, room
// lifetime). The relay never reads the wall clock for its logic: production uses the
// monotonic performance clock, tests inject a FakeClock and call Relay.sweep() themselves.

export interface Clock {
  /** Milliseconds on a monotonic timeline. Only differences matter. */
  now(): number;
}

export const systemClock: Clock = {
  now: () => performance.now(),
};

/** A clock that only moves when told to (tests, simulations). */
export class FakeClock implements Clock {
  #t: number;

  constructor(startMs = 0) {
    this.#t = startMs;
  }

  now(): number {
    return this.#t;
  }

  advance(ms: number): void {
    if (!(ms >= 0)) throw new RangeError('FakeClock.advance needs a non-negative number');
    this.#t += ms;
  }
}
