class_name Bots
extends RefCounted
## Bot riders (BRIEF 3.6): named "Bot n", negative peer ids, is_bot = true, Autopilot on,
## the lobby's bot FTP as a verified FTP, riding MockTrainer's erg profile at compliance
## 1.0 (BRIEF 4.2) plus its `band` cadence policy, so a bot follows the cadence band a game
## publishes for it (BRIEF 3.6 cadence_band): the band's centre after a 2 s lag, with seeded
## noise within +-1.5 rpm, and the preferred cadence (90 rpm) while no band is published.
## Owned by sim; public API frozen after W0.

## Every bot's MockTrainer profile: the app's lobby bots (SessionLauncher) and
## run_game_sim's bots (GameSimRunner) are built from it.
const RIDER_SPEC := "erg:compliance=1.0+band"


## Peer id of the n-th bot (n = 1, 2, ...): -n.
static func peer_id(n: int) -> int:
	return -absi(n)


## A PlayerSlot for bot number n (1-based) in `slot_index`, at `bot_ftp_w`.
static func make_slot(
	n: int, slot_index: int, bot_ftp_w: float, scaling_mode: String = Wl.FAIR_FTP
) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = peer_id(n)
	s.name = "Bot %d" % n
	s.apply_look(slot_index)
	s.ftp = bot_ftp_w
	s.ftp_verified = true
	s.scaling_mode = scaling_mode
	s.p_eff_per_w = EffortScaling.p_eff_per_w(scaling_mode, bot_ftp_w, 75.0)
	s.rider_mass_kg = 75.0
	s.preferred_cadence_rpm = 90.0
	s.haptics_on = true
	s.autopilot = true
	s.is_bot = true
	return s


## A RiderProfile for a bot (FTP verified, CP = FTP, W' 20 kJ, defaults otherwise).
static func make_profile(n: int, bot_ftp_w: float) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Bot %d" % n
	p.ftp_w = bot_ftp_w
	p.ftp_verified = true
	p.cp_w = bot_ftp_w
	p.created = true
	return p
