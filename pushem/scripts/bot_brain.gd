class_name BotBrain
extends Node


const THINK := 0.12
const REACTION := Vector2(0.12, 0.4)
const PICKUP_RANGE := 9.0

var pawn: PlayerPawn
var game: Node

var _think_left := 0.0
var _push_delay := -1.0
var _use_delay := -1.0
var _aim_error := 0.0
var _jump_wait := 0.0

func _ready() -> void:
	pawn = get_parent() as PlayerPawn
	_think_left = randf_range(0.0, THINK)

func _physics_process(delta: float) -> void:
	if pawn == null:
		return
	if not pawn.alive or not game._playing():
		pawn.move_input = Vector2.ZERO
		_push_delay = -1.0
		return
	_tick_powerup(delta)
	_tick_push(delta)
	_think_left -= delta
	if _think_left > 0.0:
		return
	_think_left = THINK
	_aim_error = lerpf(_aim_error, randf_range(-0.35, 0.35), 0.25)
	pawn.move_input = _steer()


func _steer() -> Vector2:
	var arena: Arena = game.arena
	var pos := pawn.global_position
	var vel := Vector3(pawn.linear_velocity.x, 0.0, pawn.linear_velocity.z)

	var speed := vel.length()
	var stop := pos + vel * (speed / (2.0 * float(pawn.stats().brake)))
	var room := minf(arena.edge_distance(pos), arena.edge_distance(stop))
	if room < 2.2 + speed * speed / float(pawn.stats().grip) * 0.6:
		var home := -Vector2(pos.x, pos.z)
		return home.normalized() if home.length_squared() > 0.01 else Vector2.ZERO
	var target := _nearest_opponent()
	if target == null:
		return Vector2.ZERO
	var to := target.global_position - pos
	var dir := Vector2(to.x, to.z)

	if pawn.can_collect():
		for drop: Powerup in game._drops.values():
			var d := drop.global_position - pos
			if drop.landed and d.length() < PICKUP_RANGE and dir.length() > 2.0:
				return Vector2(d.x, d.z).normalized()
	if dir.length() < 0.05:
		return Vector2.ZERO

	var gap := dir.length() - pawn.radius() - target.radius()
	return dir.normalized().rotated(_aim_error) * clampf(0.45 + gap * 0.4, 0.45, 1.0)


func _tick_push(delta: float) -> void:
	var target := _nearest_opponent()
	var in_reach := false
	var to := Vector3.ZERO
	if target != null and pawn.can_push() and target.hittable():
		to = target.global_position - pawn.global_position
		to.y = 0.0
		in_reach = to.length() <= pawn.radius() + target.radius() + PlayerPawn.PUSH_REACH * 0.85
	if not in_reach:
		_push_delay = -1.0
		return
	if _push_delay < 0.0:
		_push_delay = randf_range(REACTION.x, REACTION.y)
	_push_delay -= delta
	if _push_delay <= 0.0:
		_push_delay = -1.0
		pawn.try_push(to.rotated(Vector3.UP, randf_range(-0.25, 0.25)))


func _tick_powerup(delta: float) -> void:
	if pawn.can_use():
		if _use_delay < 0.0:
			_use_delay = randf_range(0.5, 1.5)
		_use_delay -= delta
		if _use_delay <= 0.0:
			_use_delay = -1.0
			game.bot_use(pawn)
		return
	if pawn.powerup == Powerup.Kind.SHOES:
		_tick_jump(delta)
		return
	if pawn.powerup != Powerup.Kind.BOMB:
		return
	if _use_delay < 0.0:
		_use_delay = randf_range(0.6, 1.4)
	_use_delay -= delta
	if _use_delay > 0.0:
		return
	var victim := _nearest_opponent()
	if victim == null:
		return
	var away := victim.global_position - pawn.global_position
	away.y = 0.0
	if away.length() > Powerup.BOMB_MAX_RANGE or away.length() < Powerup.BOMB_MIN_RANGE:
		return
	var lead := Powerup.bomb_flight_time(away.length()) * 0.6
	var v := victim.ground_velocity()
	var aim := victim.global_position + Vector3(v.x, 0.0, v.z) * lead
	_use_delay = -1.0
	game.bot_bomb(pawn, aim)


func _tick_jump(delta: float) -> void:
	if not pawn.can_jump():
		return
	if _use_delay < 0.0:
		_use_delay = randf_range(0.5, 1.2)
		_jump_wait = 0.0
	_use_delay -= delta
	_jump_wait += delta
	if _use_delay > 0.0:
		return
	var arena: Arena = game.arena
	var pos := pawn.global_position
	var home := Vector3(-pos.x, 0.0, -pos.z)
	var target := Vector3.INF
	if arena.edge_distance(pos) < 3.0 and home.length() > 1.0:
		target = pos + home.normalized() * minf(home.length(), Powerup.JUMP_MAX_RANGE)
	else:
		var victim := _nearest_opponent()
		if victim != null:
			var over := victim.global_position - pos
			over.y = 0.0
			var spot := victim.global_position + over.normalized() * 1.6
			if over.length() < Powerup.JUMP_MAX_RANGE - 1.6 and arena.contains(spot, 1.5):
				target = spot
	if target == Vector3.INF and _jump_wait > 5.0 and home.length() > 2.0:
		target = pos + home.normalized() * minf(home.length() * 0.6, Powerup.JUMP_MAX_RANGE)
	if target == Vector3.INF:
		return
	_use_delay = -1.0
	game.bot_jump(pawn, target)

func _nearest_opponent() -> PlayerPawn:
	var best: PlayerPawn = null
	var best_d := INF
	for other: PlayerPawn in game.pawns.values():
		if other == pawn or not other.alive:
			continue
		var d := pawn.global_position.distance_squared_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best
