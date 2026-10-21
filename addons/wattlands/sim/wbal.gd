class_name WBalance
extends RefCounted
## W' balance, Skiba's differential model (BRIEF 3.4), advanced every sim tick and shown
## as the stamina bar. A display and game-resource model: it never changes trainer
## targets except through BRIEF 4.6.
##   if P >= CP: wbal -= (P - CP) * dt
##   else:       wbal = Wp - (Wp - wbal) * exp(-dt * (CP - P) / Wp)
##   clamp wbal to [0, Wp]

var cp_w: float = 200.0
var wprime_j: float = 20000.0
var wbal_j: float = 20000.0


static func create(p_cp_w: float, p_wprime_j: float) -> WBalance:
	var w := WBalance.new()
	w.cp_w = p_cp_w
	w.wprime_j = p_wprime_j
	w.wbal_j = p_wprime_j
	return w


func step(power_w: float, dt: float) -> float:
	if power_w >= cp_w:
		wbal_j -= (power_w - cp_w) * dt
	else:
		wbal_j = wprime_j - (wprime_j - wbal_j) * exp(-dt * (cp_w - power_w) / maxf(wprime_j, 1.0))
	wbal_j = clampf(wbal_j, 0.0, wprime_j)
	return wbal_j


## 0..1 of W' remaining.
func fraction() -> float:
	return wbal_j / maxf(wprime_j, 1.0)


func reset() -> void:
	wbal_j = wprime_j
