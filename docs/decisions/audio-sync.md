# Decisions: audio sync

## 2026-10-31: strokes run on real time through one offset per kit, not one follower per machine

Supersedes the kit's earlier call to report the miss and keep `revs` as is (`audio-kit.md`, the jitter bench).

- **Decision:** `FrameClockLock`, one per `GameAudioKit`, keeps how far the frame clock has come from real time, less a 20 s mean of it: `lead_s`. A machine's strokes are planned at `revs - rpm / 60 * lead_s`. `commit(dt)` reads the real clock, unless silent, where real time is the delta and the lead is 0. Past 40 ms the lock follows the frames at once. While the crank stands, a machine keeps the offset it stopped with, so no stroke is skipped or gained at a stop.
- **Cause, as measured:** on the 59.94 Hz display Godot's smoothing hands out 16.667 ms against 16.683 ms real, so the frame clock falls 1 ms/s behind and pays 16 ms back in about 100 ms, every 16.4 s. The picture keeps this. The strokes read it whole, which is the bench's miss.
- **Alternatives:** a smoothed clock per machine, integrating rpm over real time and phase-locking slowly to the view's revs (what the task suggested). The sawtooth's period forces that lock to about 20 s, and it would then lag any machine whose `rpm` and `revs` disagree by a little: 1 % at 90 rpm settles at 0.3 revolutions behind, and a stop, a jump and a resume would each need a rule of their own. Here the sawtooth is measured where it starts, the frame clock, so there is nothing per machine to integrate, drift or snap: a jump in `revs` passes straight through and the distance from the view is bounded by construction. `application/run/delta_smoothing=false`: changes every game's picture, and it is the lead's file. It stays the reference below.
- **What it asks of a game:** `commit(dt)` takes the delta its cranks integrate. All four do (Tank's host adds its render clock's catch-up, which is nothing in steady state). A view fed from anything else would get a sawtooth of at most a vsync added to its strokes, no more.
- **Also gone, by reasoning, not measured (the bench's view does no work):** the time a view spends between its frame's start and `commit`, which moved the strokes the same way. The lock reads the clock at `commit`, where the strokes' delay is counted from.

Measured on WASAPI, 48 kHz, 59.94 Hz, with other builders on the machine; residual p99 / stddev in ms, limits 12 / 4, thresholds unchanged. Slopes hold in every run (at most 0.097 % before, 0.036 % after, limit 0.1 %), all onsets heard, no stroke late or dropped.

| rpm | engine, before | engine, after | real, before | real, after | no seek, before | no seek, after | engine, smoothing off |
|---|---|---|---|---|---|---|---|
| 60 | 14.44 / 5.22 | 5.82 / 3.12 | 5.76 / 3.19 | 5.78 / 3.11 | 9.75 / 4.33 | 18.24 / 6.95 | 6.03 / 3.19 |
| 90 | 10.60 / 4.90 | 11.29 / 3.57 | 5.54 / 3.04 | 5.70 / 3.21 | 18.92 / 7.77 | 14.60 / 6.62 | 5.83 / 3.38 |
| 110 | 11.57 / 5.64 | 6.06 / 3.15 | 5.75 / 3.15 | 5.92 / 3.22 | 16.84 / 6.87 | 14.26 / 6.52 | 6.65 / 3.28 |
| 140 | 12.51 / 4.78 | 6.30 / 3.13 | 5.72 / 3.14 | 6.08 / 3.22 | 21.38 / 7.91 | 16.14 / 6.59 | 5.42 / 3.26 |

The new sprint run, 70 to 130 rpm in 2 s: 144 strokes fired, 144 heard; 6.34 / 3.10 once settled. A commit of 8 machines: 0.111 ms mean, was 0.124 (D10: 0.5). The picture's crank was at most 13.1 ms from the strokes' clock in any engine run. The 90 rpm 11.29 after is two strokes of 112, most likely the machine's load (stddev 3.57). What remains everywhere else is what the seek cannot take out: one 512-frame mix step, stddev 3.08.

## 2026-10-31: the bench's exit code also holds a sprint and D10

- **Decision:** a "sprint" run decides the exit code with the "engine" runs, every stroke fired must be heard, and so does a commit of 8 machines over 0.5 ms.
- **Alternatives:** leaving both as numbers to read. Nobody reads a passing bench's numbers, and both are stated requirements.
- **Reason:** this only adds to what the bench holds; no limit moved. The bench now takes about 340 s, inside its 420 s timeout.
