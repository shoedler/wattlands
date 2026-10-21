class_name SfxSynth
extends RefCounted
## Runtime sound synthesis for WlSfx (BRIEF 3.9 audio): 16-bit mono PCM AudioStreamWAV
## clips from simple oscillators with linear attack and release envelopes. Pure and
## deterministic (noise comes from a fixed-seed xorshift, never the global RNG). Owned by
## ui-hud. Games can build their own clips with WlSfx.synth() or these helpers.

const MIX_RATE := 22050
const KINDS: Array[String] = ["sine", "square", "saw", "triangle", "noise"]


## One oscillator clip. freq_end_hz >= 0 sweeps the pitch linearly to it. A looped clip gets
## no envelope (so the loop has no gap), loop_mode LOOP_FORWARD over the whole clip.
static func tone(
	kind: String,
	freq_hz: float,
	duration_s: float,
	attack_s: float = 0.005,
	release_s: float = 0.05,
	loop: bool = false,
	gain: float = 0.6,
	freq_end_hz: float = -1.0
) -> AudioStreamWAV:
	var samples := render(
		kind,
		freq_hz,
		duration_s,
		0.0 if loop else attack_s,
		0.0 if loop else release_s,
		gain,
		freq_end_hz
	)
	return to_wav(samples, loop)


## Raw samples in [-1, 1] for one oscillator segment.
static func render(
	kind: String,
	freq_hz: float,
	duration_s: float,
	attack_s: float = 0.005,
	release_s: float = 0.05,
	gain: float = 0.6,
	freq_end_hz: float = -1.0,
	seed: int = 0x2545F491
) -> PackedFloat32Array:
	var n := maxi(1, roundi(duration_s * MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var state := seed if seed != 0 else 1
	var attack_n := maxi(0, roundi(attack_s * MIX_RATE))
	var release_n := maxi(0, roundi(release_s * MIX_RATE))
	var sweep := freq_end_hz >= 0.0
	for i in n:
		var f := freq_hz
		if sweep:
			f = lerpf(freq_hz, freq_end_hz, float(i) / float(n))
		phase = fposmod(phase + f / MIX_RATE, 1.0)
		var v := 0.0
		match kind:
			"sine":
				v = sin(TAU * phase)
			"square":
				v = 1.0 if phase < 0.5 else -1.0
			"saw":
				v = 2.0 * phase - 1.0
			"triangle":
				v = 4.0 * absf(phase - 0.5) - 1.0
			"noise":
				state ^= (state << 13) & 0xFFFFFFFF
				state ^= state >> 17
				state ^= (state << 5) & 0xFFFFFFFF
				state &= 0xFFFFFFFF
				v = float(state) / 2147483647.5 - 1.0
		var env := 1.0
		if attack_n > 0 and i < attack_n:
			env = float(i) / float(attack_n)
		if release_n > 0 and i >= n - release_n:
			env = minf(env, float(n - 1 - i) / float(release_n))
		out[i] = v * gain * env
	return out


## Segments one after the other.
static func concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Variant in parts:
		if p is PackedFloat32Array:
			out.append_array(p)
	return out


## Sum of two clips (the longer length), clipped to [-1, 1].
static func mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i < b.size():
			v += b[i]
		out[i] = clampf(v, -1.0, 1.0)
	return out


## One-pole low-pass (alpha in (0, 1]; smaller is darker).
static func lowpass(samples: PackedFloat32Array, alpha: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	var y := 0.0
	var a := clampf(alpha, 0.001, 1.0)
	for i in out.size():
		y += a * (out[i] - y)
		out[i] = y
	return out


## Exponential decay over the clip (sharper hits and booms).
static func decay(samples: PackedFloat32Array, per_second: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	for i in out.size():
		out[i] *= exp(-per_second * float(i) / MIX_RATE)
	return out


## Silence of `duration_s`.
static func silence(duration_s: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(0, roundi(duration_s * MIX_RATE)))
	return out


## Samples -> a 16-bit mono AudioStreamWAV at MIX_RATE.
static func to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Largest absolute sample of a 16-bit clip, 0..1 (tests: "not silent").
static func peak(wav: AudioStreamWAV) -> float:
	var m := 0
	var d := wav.data
	for i in range(0, d.size() - 1, 2):
		m = maxi(m, absi(d.decode_s16(i)))
	return float(m) / 32767.0


## Length of a 16-bit mono clip in seconds.
static func length_s(wav: AudioStreamWAV) -> float:
	return float(wav.data.size()) / 2.0 / float(wav.mix_rate)


## The platform's built-in effects (WlSfx.BUILTIN_NAMES); null for an unknown name.
static func builtin(sound: String) -> AudioStreamWAV:
	match sound:
		"ui_move":
			return to_wav(render("sine", 880.0, 0.04, 0.002, 0.02, 0.35))
		"ui_confirm":
			return to_wav(
				concat(
					[
						render("sine", 660.0, 0.06, 0.003, 0.02, 0.5),
						render("sine", 990.0, 0.1, 0.003, 0.06, 0.5)
					]
				)
			)
		"ui_back":
			return to_wav(render("sine", 660.0, 0.14, 0.003, 0.08, 0.5, 400.0))
		"toast":
			return to_wav(render("triangle", 1046.5, 0.14, 0.004, 0.1, 0.5))
		"warning":
			return to_wav(
				concat(
					[
						render("square", 440.0, 0.12, 0.004, 0.03, 0.3),
						silence(0.06),
						render("square", 440.0, 0.12, 0.004, 0.03, 0.3)
					]
				)
			)
		"rescue":
			return to_wav(render("square", 620.0, 0.5, 0.01, 0.15, 0.3, 300.0))
		"phase":
			return to_wav(
				mix(
					render("sine", 523.25, 0.35, 0.01, 0.25, 0.35),
					render("sine", 659.25, 0.35, 0.01, 0.25, 0.35)
				)
			)
		"countdown":
			return to_wav(render("sine", 880.0, 0.1, 0.003, 0.05, 0.5))
		"lap":
			return to_wav(
				concat(
					[
						render("sine", 784.0, 0.08, 0.003, 0.02, 0.45),
						render("sine", 1046.5, 0.16, 0.003, 0.1, 0.45)
					]
				)
			)
		"results":
			return to_wav(
				concat(
					[
						render("triangle", 523.25, 0.1, 0.004, 0.02, 0.5),
						render("triangle", 659.25, 0.1, 0.004, 0.02, 0.5),
						render("triangle", 784.0, 0.1, 0.004, 0.02, 0.5),
						render("triangle", 1046.5, 0.3, 0.004, 0.2, 0.5),
					]
				)
			)
		"coin":
			return to_wav(
				concat(
					[
						render("square", 988.0, 0.05, 0.002, 0.01, 0.25),
						render("square", 1318.5, 0.2, 0.002, 0.15, 0.25)
					]
				)
			)
		"hit":
			return to_wav(decay(lowpass(render("noise", 0.0, 0.12, 0.001, 0.03, 0.8), 0.5), 30.0))
		"boom":
			return to_wav(
				mix(
					decay(
						lowpass(render("noise", 0.0, 0.7, 0.002, 0.2, 0.9, -1.0, 0x1234567), 0.08),
						6.0
					),
					decay(render("sine", 60.0, 0.7, 0.002, 0.2, 0.6, 40.0), 5.0)
				)
			)
		"whoosh":
			var n := lowpass(render("noise", 0.0, 0.45, 0.15, 0.25, 0.7, -1.0, 0x0BADC0DE), 0.15)
			return to_wav(n)
		"click":
			return to_wav(render("square", 2000.0, 0.012, 0.0005, 0.006, 0.4))
	return null
