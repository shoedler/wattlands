class_name TankDamage
extends RefCounted
## The damage table (brief 2.4 Gun): light 20, heavy 50, Overpressure 100, a bow-gun burst 5;
## splash 16 px at 50%; mediums take half from light shells and bow-gun bursts, heavy tanks, tank
## destroyers and the Behemoth a quarter (enemies.json `light_mult`); heavy and Overpressure
## shells deal full damage to every target. Owner: rules (combat).


## The damage of one round of `shell` (a TankIds.SHELL_* code) before the target's armour.
static func shell_damage(c: TankContent, shell: int) -> float:
	match shell:
		TankIds.SHELL_LIGHT:
			return c.num("tanks", "damage.light", 20.0)
		TankIds.SHELL_HEAVY:
			return c.num("tanks", "damage.heavy", 50.0)
		TankIds.SHELL_OVER:
			return c.num("tanks", "damage.over", 100.0)
		TankIds.SHELL_BOW:
			return c.num("tanks", "bow.damage", 5.0)
	return 0.0


## True for the shells armour reduces (light shells and bow-gun bursts).
static func is_soft(shell: int) -> bool:
	return shell == TankIds.SHELL_LIGHT or shell == TankIds.SHELL_BOW


## The armour factor `shell` meets on enemy `type` (1 for heavy and Overpressure shells).
static func enemy_mult(c: TankContent, type: String, shell: int) -> float:
	if not is_soft(shell):
		return 1.0
	return float(c.enemy_def(type).get("light_mult", 1.0))


## The armour factor on the Behemoth's parts.
static func boss_mult(c: TankContent, shell: int) -> float:
	if not is_soft(shell):
		return 1.0
	return float(c.boss_def().get("light_mult", 0.25))


## Damage `shell` deals when it hits `target` (direct), after armour; 0 for an obstacle (they
## take shell counts, not HP).
static func against(c: TankContent, shell: int, target: TankTarget) -> float:
	var base := shell_damage(c, shell)
	match target.kind:
		TankTarget.KIND_ENEMY:
			return base * enemy_mult(c, TankIds.enemy_of(target.enemy.code), shell)
		TankTarget.KIND_BOSS:
			return base * boss_mult(c, shell)
	return 0.0


## The splash a shell that lands at `point` deals to `target`: splash_frac of the direct damage
## when the box lies within splash_px of the point, else 0.
static func splash(c: TankContent, shell: int, target: TankTarget, point: Vector2) -> float:
	var radius := c.num("tanks", "damage.splash_px", 16.0)
	if distance_to_rect(point, target.rect) > radius:
		return 0.0
	return against(c, shell, target) * c.num("tanks", "damage.splash_frac", 0.5)


## Distance from `p` to the box (0 inside it).
static func distance_to_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)
