class_name PlayerPawn
extends RigidBody3D


enum WeightClass {NORMAL, HEAVY, LIGHT}


const SPEED_UNIT := 0.09


const STATS := {
	WeightClass.NORMAL: {
		"label": "Normal", "mass": 1.0, "speed": 75.0, "accel": 10.0, "build": 2.6,
		"brake": 6.5, "grip": 9.0, "push": 4.6, "lunge": 2.2, "cooldown": 0.75,
		"radius": 0.45, "height": 1.65, "color": Color(0.25, 0.55, 1.0),
	},
	WeightClass.HEAVY: {
		"label": "Heavy", "mass": 1.5, "speed": 50.0, "accel": 6.0, "build": 1.5,
		"brake": 3.8, "grip": 5.0, "push": 5.2, "lunge": 1.8, "cooldown": 0.95,
		"radius": 0.6, "height": 1.8, "color": Color(0.92, 0.3, 0.25),
	},
	WeightClass.LIGHT: {
		"label": "Light", "mass": 0.75, "speed": 100.0, "accel": 14.0, "build": 3.8,
		"brake": 9.0, "grip": 14.0, "push": 3.4, "lunge": 2.2, "cooldown": 0.6,
		"radius": 0.34, "height": 1.2, "color": Color(0.32, 0.85, 0.45),
	},
}


const STICK_DEADZONE := 0.12
const TURN_FREE_SPEED := 0.9
const MAX_TURN := 9.0
const TURN_SCRUB := 0.12
const REVERSE_ANGLE := deg_to_rad(125.0)
const REVERSE_BRAKE := 1.7

const JOG_SHARE := 0.35


const OVERSPEED := 1.15
const SLIDE_DECEL := 9.0


const PUSH_REACH := 0.75
const PUSH_CONE := 0.5
const PUSH_WINDOW := 0.2
const PUSH_MOMENTUM := 0.95
const PUSH_MIN := 0.4


const LEAN_GAIN := 0.55
const LEAN_MAX := 0.42
const PITCH_GAIN := 0.35
const PITCH_MAX := 0.22


const WALK_SPEED := 0.6
const TURN_RATE := 12.0


const POSE_PUSH := {
	"Spine": Vector3(0.35, 0.0, 0.0),
	"Head": Vector3(-0.3, 0.0, 0.0),
	"ArmL": Vector3(-1.45, 0.0, -0.18),
	"ArmR": Vector3(-1.45, 0.0, 0.18),
}
const POSE_KICK := {
	"Spine": Vector3(-0.5, 0.0, 0.0),
	"Head": Vector3(0.35, 0.0, 0.0),
	"LegR": Vector3(-1.5, 0.0, 0.0),
	"LegL": Vector3(0.6, 0.0, 0.0),
	"ArmL": Vector3(0.0, 0.0, 1.3),
	"ArmR": Vector3(-1.0, 0.0, 0.3),
}

const POSE_JUMP := {
	"Spine": Vector3(0.25, 0.0, 0.0),
	"Head": Vector3(-0.2, 0.0, 0.0),
	"ArmL": Vector3(-2.5, 0.0, 0.45),
	"ArmR": Vector3(-2.5, 0.0, -0.45),
	"LegL": Vector3(-1.35, 0.0, 0.0),
	"LegR": Vector3(-0.75, 0.0, 0.0),
}

const POSE_HIT := {
	"Spine": Vector3(-0.45, 0.0, 0.15),
	"Head": Vector3(0.35, 0.0, -0.2),
	"ArmL": Vector3(-0.6, 0.0, 1.1),
	"ArmR": Vector3(-0.6, 0.0, -1.1),
}
const HIT_POSE_TIME := 0.4


const SQUASH_K := 320.0
const SQUASH_DAMP := 16.0
const RIG_PARTS := ["Hips", "Spine", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const DASH_POSE_TIME := 0.4
const KICK_POSE_TIME := 0.5
const KICK_HOP := 0.55

const CONTACT_REACH := 0.3
const YELL_GAP_MS := 900


const BUMP_BOOST := 0.35
const BUMP_BOUNCE := 0.4
const INVULN_TIME := 2.0


const TETHER_PULL := 14.0
const TETHER_SLOW := 0.8


const NET_EXTRAPOLATE := 0.2
const NET_GAP := 0.25


const LAYER_PAWN := 1
const LAYER_FLOOR := 2

var weight_class: WeightClass = WeightClass.NORMAL
var character := ""
var player_name := "Player"
var is_bot := false
var lives := 3
var alive := true
var cooldown_left := 0.0
var invuln_left := 0.0

var move_input := Vector2.ZERO
var stagger_left := 0.0


var remote_controlled := false

var referee := true

var net_vel := Vector3.ZERO

var net_seq := 0
var _net_buf: Array = []

var ghost_left := 0.0


var held := -1
var powerup := -1
var powerup_left := 0.0
var powerup_age := 0.0
var latched: PlayerPawn
var gripped_by: PlayerPawn
var grip_left := 0.0

var grab_block_left := 0.0

var _push_left := 0.0
var _push_dir := Vector3.FORWARD
var _push_power := 0.0
var _push_hit: Array[PlayerPawn] = []
var _aim_face := Vector3.ZERO
var _gloves: Node3D
var _trail_left := 0.0


var _jump_t := -1.0
var _jump_time := 1.0
var _jump_from := Vector3.ZERO
var _jump_to := Vector3.ZERO
var _visual: Node3D
var _model_pivot: Node3D
var _anim: AnimationPlayer
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _cheering := false
var _rig := {}
var _rig_rest := {}
var _pose := ""
var _pose_left := 0.0
var _pose_len := 1.0
var _contact_w := 0.0
var _next_yell_ms := 0
var _squash := 0.0
var _squash_v := 0.0
var _pop := 1.0
var _flail_w := 0.0
var _t := 0.0
var _label: Label3D
var _badge: Node3D
var _vel_s := Vector3.ZERO
var _acc_s := Vector3.ZERO
var _lean := Vector2.ZERO

signal fell(pawn: PlayerPawn)

signal pushed(direction: Vector3)


signal shoved(victim: PlayerPawn, power: float, impulse: Vector3)

signal stomped(victim: PlayerPawn, dir: Vector3, distance: float)

signal broke_free

func stats() -> Dictionary:
	return STATS[weight_class]

func radius() -> float:
	return stats().radius

func height() -> float:
	return stats().height

func _ready() -> void:
	mass = stats().mass

	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = LAYER_PAWN
	collision_mask = LAYER_FLOOR
	var phys := PhysicsMaterial.new()
	phys.bounce = 0.5
	phys.friction = 0.0
	physics_material_override = phys

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius()
	capsule.height = height()
	col.shape = capsule
	col.position.y = height() / 2.0
	add_child(col)

	_build_visual()
	_last_pos = global_position

	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56

	_label.fixed_size = true
	_label.pixel_size = 0.0006
	_label.outline_size = 14
	_label.position.y = height() + 0.4
	_label.modulate = Color.WHITE
	add_child(_label)


func active() -> bool:
	return alive and (remote_controlled or not freeze)


func hittable() -> bool:
	return active() and visible and invuln_left <= 0.0 and not in_air() and ghost_left <= 0.0

func can_collect() -> bool:
	return active() and held < 0 and powerup < 0 and not in_air()

func can_use() -> bool:
	return alive and held >= 0 and powerup < 0


func can_cancel() -> bool:
	return alive and powerup >= 0 and powerup_age >= Powerup.CANCEL_DELAY and not in_air()


func in_air() -> bool:
	return _jump_t >= 0.0 or _pose == "jump"


func can_jump() -> bool:
	return active() and powerup == Powerup.Kind.SHOES and not in_air() and _grounded() and not (gripped_by != null and grip_left > 0.0)


func start_jump(to: Vector3, time: float) -> void:
	if gripped_by != null:
		gripped_by.detach()
	detach()
	_jump_from = global_position
	_jump_to = Vector3(to.x, 0.0, to.z)
	_jump_time = maxf(time, 0.2)
	_jump_t = 0.0
	_push_left = 0.0
	linear_velocity = Vector3.ZERO
	freeze = true
	collision_layer = 0
	collision_mask = 0
	start_jump_pose(_jump_to - _jump_from, _jump_time)


func start_jump_pose(dir: Vector3, time: float) -> void:
	dir.y = 0.0
	_aim_face = dir.normalized() if dir.length_squared() > 0.0001 else _facing()
	if _model_pivot != null:
		_model_pivot.rotation.y = atan2(_aim_face.x, _aim_face.z)
	Fx.dash_dust(get_parent(), global_position, _aim_face)
	_squash_v -= 4.0
	_pose = "jump"
	_pose_len = time
	_pose_left = time
	GameAudio.play("flick", 0.0, 1.5)


func _tick_jump(delta: float) -> void:
	if _jump_t < 0.0:
		return
	if not alive:
		_end_jump(false)
		return
	_jump_t += delta
	var u := minf(_jump_t / _jump_time, 1.0)
	global_position = Powerup.jump_arc(_jump_from, _jump_to, u)
	if u >= 1.0:
		_land_jump()


func _land_jump() -> void:
	var dir := _jump_to - _jump_from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else _facing()
	_end_jump(true)
	linear_velocity = dir * top_speed() * 0.4
	clear_powerup()
	var hit: Array[PlayerPawn] = []
	for node in get_parent().get_children():
		var other := node as PlayerPawn
		if other == null or other == self or not other.hittable():
			continue
		var d := other.global_position - global_position
		if absf(d.y) > 1.0:
			continue
		d.y = 0.0
		if d.length() <= radius() + other.radius() + 0.25:
			hit.append(other)

	for other in hit.duplicate():
		for partner: PlayerPawn in [other.gripped_by, other.latched]:
			if partner != null and partner != self and partner.alive and not hit.has(partner):
				hit.append(partner)
	for other in hit:
		var d := other.global_position - global_position
		d.y = 0.0
		var away := d.normalized() if d.length_squared() > 0.0001 else dir
		stomped.emit(other, away, maxf(0.5, Powerup.JUMP_STOMP_DISTANCE - d.length()))


static func stomp_slide_time() -> float:
	return sqrt(2.0 * SLIDE_DECEL * Powerup.JUMP_STOMP_DISTANCE) / SLIDE_DECEL

func _end_jump(unfreeze: bool) -> void:
	_jump_t = -1.0
	collision_layer = LAYER_PAWN
	set_floor_collision(true)
	if unfreeze:
		freeze = remote_controlled


func top_speed() -> float:
	return stats().speed * SPEED_UNIT

func can_push() -> bool:
	if not alive or cooldown_left > 0.0:
		return false
	if powerup == Powerup.Kind.BOMB or powerup == Powerup.Kind.SHOES:
		return false
	if gripped_by != null and grip_left > 0.0:
		return false

	return remote_controlled or not freeze


func try_push(direction: Vector3) -> bool:
	if not can_push():
		return false
	direction.y = 0.0
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else _facing()

	if gripped_by != null:
		_break_free()
	var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var along := clampf(flat.dot(dir) / top_speed(), -1.0, 1.3)
	_push_power = stats().push * maxf(PUSH_MIN, 1.0 + PUSH_MOMENTUM * along)
	_push_dir = dir
	_push_left = PUSH_WINDOW
	_push_hit.clear()
	_kick(dir * stats().lunge)
	cooldown_left = stats().cooldown
	start_push_pose(dir)
	pushed.emit(dir)
	return true


func _tick_push(delta: float) -> void:
	if _push_left <= 0.0:
		return
	_push_left -= delta
	for node in get_parent().get_children():
		var other := node as PlayerPawn
		if other == null or other == self or not other.hittable() or _push_hit.has(other):
			continue
		var d := other.global_position - global_position
		if absf(d.y) > 1.0:
			continue
		d.y = 0.0
		var dist := d.length()
		if dist > radius() + other.radius() + PUSH_REACH:
			continue
		var to := d / dist if dist > 0.001 else _push_dir
		if to.dot(_push_dir) < PUSH_CONE:
			continue
		_push_hit.append(other)
		var power := _push_power * hit_multiplier()
		shoved.emit(other, power, (_push_dir * 0.7 + to * 0.3).normalized() * power)


func max_push() -> float:
	return stats().push * (1.0 + PUSH_MOMENTUM * 1.3) * Powerup.GLOVES_HIT_MULT


func take_shove(impulse: Vector3) -> void:
	_kick(impulse / mass)
	stagger_left = maxf(stagger_left, clampf(impulse.length() / mass / 16.0, 0.15, 0.6))
	GameAudio.play("bump", linear_to_db(clampf(impulse.length() / mass / 10.0, 0.3, 1.0)),
			randf_range(0.9, 1.1))


func throw_back(dir: Vector3, distance: float) -> void:
	dir.y = 0.0
	dir = dir.normalized()
	var speed := sqrt(2.0 * SLIDE_DECEL * distance)
	linear_velocity = Vector3(dir.x * speed, linear_velocity.y, dir.z * speed)
	stagger_left = maxf(stagger_left, speed / SLIDE_DECEL)
	GameAudio.play("bump", 0.0, randf_range(0.85, 1.0))


func _kick(dv: Vector3) -> void:
	linear_velocity += dv


func _grounded() -> bool:
	return has_floor_collision() and global_position.y > -0.2 and global_position.y < 0.3


func _accel_at(speed: float) -> float:
	var st := stats()
	var f := speed / top_speed()
	return lerpf(float(st.accel), float(st.build), smoothstep(JOG_SHARE * 0.6, JOG_SHARE * 1.4, f))


func ground_velocity() -> Vector3:
	return net_vel if remote_controlled else linear_velocity


func _drive(delta: float) -> void:
	if not alive or freeze or not _grounded():
		return
	var st := stats()
	var flat := Vector2(linear_velocity.x, linear_velocity.z)
	var speed := flat.length()
	var heading := flat / speed if speed > 0.001 else Vector2.ZERO
	var stick := move_input.limit_length(1.0)
	var amount := stick.length()
	var stuck := gripped_by != null and grip_left > 0.0
	var dashing := powerup == Powerup.Kind.DASH
	if stagger_left > 0.0 or stuck or speed > top_speed() * OVERSPEED:
		speed = move_toward(speed, 0.0, SLIDE_DECEL * delta)
	elif amount < STICK_DEADZONE:
		speed = move_toward(speed, 0.0, float(st.brake) * delta)
	else:

		if gripped_by != null:
			_break_free()
		var want := stick / amount
		var cap := top_speed() * amount
		if latched != null:
			cap *= TETHER_SLOW
		if dashing:

			heading = want
			speed = top_speed()
		elif speed < TURN_FREE_SPEED:
			heading = want
			speed = move_toward(speed, cap, _accel_at(speed) * delta)
		else:
			var off := heading.angle_to(want)
			if absf(off) > REVERSE_ANGLE:
				speed = move_toward(speed, 0.0, float(st.brake) * REVERSE_BRAKE * delta)
			else:

				var rate := minf(float(st.grip) / speed, MAX_TURN)
				var turn := clampf(off, -rate * delta, rate * delta)
				heading = heading.rotated(turn)
				speed = maxf(0.0, speed - TURN_SCRUB * speed * absf(turn))
				if speed < cap:
					speed = move_toward(speed, cap, _accel_at(speed) * delta)
				else:
					speed = move_toward(speed, cap, float(st.brake) * 0.5 * delta)
	flat = heading * speed
	if gripped_by != null and is_instance_valid(gripped_by):
		flat = _tether(flat, stuck)
	linear_velocity = Vector3(flat.x, linear_velocity.y, flat.y)


func _tether(flat: Vector2, stuck: bool) -> Vector2:
	var d := gripped_by.global_position - global_position
	var to := Vector2(d.x, d.z)
	var rest := radius() + gripped_by.radius() + 0.05
	var dist := to.length()
	var pull := Vector2.ZERO
	if dist > rest:
		pull = to / dist * (dist - rest) * TETHER_PULL
	if stuck:
		var hv := gripped_by.ground_velocity()
		return Vector2(hv.x, hv.z) + pull
	return flat + pull


func _break_free() -> void:
	if gripped_by == null:
		return
	gripped_by.detach()
	broke_free.emit()

func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
	if stagger_left > 0.0:
		stagger_left = maxf(0.0, stagger_left - delta)
	if invuln_left > 0.0:
		invuln_left = maxf(0.0, invuln_left - delta)
		_visual.visible = fmod(invuln_left, 0.25) > 0.1
		if invuln_left == 0.0:
			_visual.visible = true
	if grip_left > 0.0:
		grip_left = maxf(0.0, grip_left - delta)
	if grab_block_left > 0.0:
		grab_block_left = maxf(0.0, grab_block_left - delta)
	if ghost_left > 0.0:
		ghost_left = maxf(0.0, ghost_left - delta)
	if _badge != null:
		_badge.rotation.y += delta * 3.0
	if powerup == Powerup.Kind.DASH and alive:

		_trail_left -= delta
		if _trail_left <= 0.0 and _speed > WALK_SPEED * 2.0:
			_trail_left = 0.09
			Fx.dash_dust(get_parent(), global_position, _facing())
	if powerup >= 0:
		powerup_age += delta

	if referee and powerup >= 0 and Powerup.timed(powerup):
		powerup_left = maxf(0.0, powerup_left - delta)
		if powerup_left == 0.0:
			clear_powerup()
	if remote_controlled:
		return
	_tick_jump(delta)
	_drive(delta)
	_tick_push(delta)
	if alive and global_position.y < -4.0:
		alive = false
		move_input = Vector2.ZERO
		detach()
		if gripped_by != null:
			gripped_by.detach()
		fell.emit(self)
	elif not alive and global_position.y < -40.0 and not freeze:
		freeze = true


func push_net_state(t: float, pos: Vector3, vel: Vector3) -> void:
	if not _net_buf.is_empty() and t <= float(_net_buf[_net_buf.size() - 1][0]):
		return
	_net_buf.append([t, pos, vel])
	if _net_buf.size() > 16:
		_net_buf.pop_front()


func follow_net(t: float) -> void:
	var n := _net_buf.size()
	if n == 0:
		return
	var pos: Vector3
	var vel: Vector3
	var last: Array = _net_buf[n - 1]
	var first: Array = _net_buf[0]
	if t >= float(last[0]):
		var dt := minf(t - float(last[0]), NET_EXTRAPOLATE)
		vel = last[2]
		pos = (last[1] as Vector3) + vel * dt
	elif t <= float(first[0]):
		pos = first[1]
		vel = first[2]
	else:
		var i := 0
		while i < n - 2 and float(_net_buf[i + 1][0]) <= t:
			i += 1
		var a: Array = _net_buf[i]
		var b: Array = _net_buf[i + 1]
		var span := float(b[0]) - float(a[0])
		var u := (t - float(a[0])) / span
		var p0: Vector3 = a[1]
		var p1: Vector3 = b[1]
		if span > NET_GAP:
			pos = p0.lerp(p1, u)
			vel = (p1 - p0) / span
		else:
			var v0: Vector3 = (a[2] as Vector3) * span
			var v1: Vector3 = (b[2] as Vector3) * span
			var u2 := u * u
			var u3 := u2 * u
			pos = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * v0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * v1

			vel = (a[2] as Vector3).lerp(b[2], u)

		for k in i:
			_net_buf.pop_front()
	global_position = pos
	net_vel = vel


func clear_net() -> void:
	_net_buf.clear()
	net_vel = Vector3.ZERO


static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 255
	return d > 0 and d < 128


static func resolve_contacts(list: Array, touching: Dictionary, on_enter: Callable) -> void:
	var n := list.size()
	for i in n:
		var a: PlayerPawn = list[i]
		for j in range(i + 1, n):
			var b: PlayerPawn = list[j]
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			if not _can_touch(a, b):
				touching.erase(key)
				continue
			var d := a.global_position - b.global_position
			if absf(d.y) > 1.2:
				touching.erase(key)
				continue
			d.y = 0.0
			var dist := d.length()
			var reach := a.radius() + b.radius()
			if dist >= reach:
				touching.erase(key)
				continue
			var nrm := d / dist if dist > 0.0001 else Vector3.RIGHT
			var ma := a.mass
			var mb := b.mass
			var overlap := reach - dist
			if not a.remote_controlled and not a.freeze:
				a.global_position += nrm * overlap * mb / (ma + mb)
			if not b.remote_controlled and not b.freeze:
				b.global_position -= nrm * overlap * ma / (ma + mb)
			var va := a.ground_velocity()
			var vb := b.ground_velocity()
			var rel := (va - vb).dot(nrm)
			if rel < 0.0:
				var jn := -(1.0 + BUMP_BOUNCE) * rel / (1.0 / ma + 1.0 / mb)
				if not a.remote_controlled and not a.freeze:
					a._kick(nrm * jn / ma)
				if not b.remote_controlled and not b.freeze:
					b._kick(-nrm * jn / mb)
			if touching.has(key):
				continue
			touching[key] = true

			var closing_b := vb.dot(nrm)
			var closing_a := -va.dot(nrm)
			a._bump_from(b, nrm, closing_b)
			b._bump_from(a, -nrm, closing_a)
			on_enter.call(a, b, maxf(closing_a, 0.0) + maxf(closing_b, 0.0))

static func _can_touch(a: PlayerPawn, b: PlayerPawn) -> bool:
	if not a.alive or not b.alive or not a.visible or not b.visible:
		return false
	if a.in_air() or b.in_air() or a.ghost_left > 0.0 or b.ghost_left > 0.0:
		return false

	return a.latched != b and b.latched != a


func _bump_from(other: PlayerPawn, away: Vector3, closing: float) -> void:
	if remote_controlled or freeze or closing <= 0.0 or invuln_left > 0.0:
		return
	var boost := closing * other.mass * BUMP_BOOST * other.hit_multiplier()
	_kick(away * boost / mass)
	stagger_left = maxf(stagger_left, clampf(boost / mass / 16.0, 0.0, 0.4))
	if closing > 0.8:
		GameAudio.play("bump", linear_to_db(clampf(closing / 9.0, 0.25, 1.0)),
				randf_range(0.9, 1.1))


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var model := Characters.instantiate(character, Settings.quality()["outline"]) if character != "" else null

	if model != null:
		_model_pivot = Node3D.new()
		_visual.add_child(_model_pivot)
		_model_pivot.add_child(model)
		_anim = Characters.animation_player(model)
		if _anim != null:

			_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for part: String in RIG_PARTS:
			var node := model.find_child(part, true, false)
			if node is Node3D:
				_rig[part] = node
				_rig_rest[part] = (node as Node3D).quaternion
	else:
		var mesh := MeshInstance3D.new()
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = radius()
		capsule_mesh.height = height()
		mesh.mesh = capsule_mesh
		mesh.position.y = height() / 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = stats().color
		mat.roughness = 0.6
		mesh.material_override = mat
		_visual.add_child(mesh)

	if not Settings.quality()["shadows"]:
		var blob := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius() * 1.15
		disc.bottom_radius = radius() * 1.15
		disc.height = 0.01
		disc.radial_segments = 20
		blob.mesh = disc
		blob.position.y = 0.015
		var blob_mat := StandardMaterial3D.new()
		blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blob_mat.albedo_color = Color(0, 0, 0, 0.35)
		blob.material_override = blob_mat
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(blob)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius() - 0.06
	torus.outer_radius = radius() + 0.03
	torus.rings = 32
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position.y = 0.03
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = stats().color
	ring_mat.emission_enabled = true
	ring_mat.emission = stats().color
	ring_mat.emission_energy_multiplier = 0.6
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(ring)


func _process(delta: float) -> void:

	var deep := global_position.y < -3.0
	_label.visible = not deep
	if deep:
		_visual.visible = false
	elif invuln_left <= 0.0:
		_visual.visible = true
	if _model_pivot == null or delta <= 0.0:
		return
	var step := global_position - _last_pos
	_last_pos = global_position
	step.y = 0.0
	var speed := step.length() / delta
	_speed = lerpf(_speed, speed, minf(1.0, delta * 10.0))
	_update_lean(step / delta, delta)

	var contact := _contact_direction()
	_contact_w = move_toward(_contact_w, 1.0 if contact != Vector3.ZERO else 0.0, delta * 6.0)
	var face := Vector3.ZERO
	if _pose in ["push", "kick", "jump"] and _aim_face != Vector3.ZERO:
		face = _aim_face
	elif contact != Vector3.ZERO:
		face = contact
	elif _speed > WALK_SPEED and step.length_squared() > 1e-06:
		face = step
	if face != Vector3.ZERO and not _cheering and _pose != "hit":
		_model_pivot.rotation.y = lerp_angle(_model_pivot.rotation.y, atan2(face.x, face.z),
				minf(1.0, delta * TURN_RATE))

	_t += delta
	var falling := global_position.y < -0.35 and alive
	_flail_w = move_toward(_flail_w, 1.0 if falling else 0.0, delta * 8.0)

	_squash_v += (-SQUASH_K * _squash - SQUASH_DAMP * _squash_v) * delta
	_squash += _squash_v * delta
	var sq := clampf(_squash, -0.35, 0.35)
	_model_pivot.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5) * _pop
	_model_pivot.rotation.x = _lean.x
	_model_pivot.rotation.z = _lean.y

	if _anim == null:
		return
	if not _cheering:
		if _speed > WALK_SPEED:
			if _anim.current_animation != "Walk":
				_anim.play("Walk", 0.15)
			_anim.speed_scale = clampf(_speed / 3.0, 0.8, 2.5)
		elif _anim.current_animation != "Idle":
			_anim.play("Idle", 0.25)
			_anim.speed_scale = 1.0

	for part: String in _rig:
		(_rig[part] as Node3D).quaternion = _rig_rest[part]
	_anim.advance(delta)
	if not _cheering:
		_apply_action_pose(delta)


func _update_lean(vel: Vector3, delta: float) -> void:
	var prev := _vel_s
	_vel_s = _vel_s.lerp(vel, minf(1.0, delta * 14.0))
	_acc_s = _acc_s.lerp((_vel_s - prev) / delta, minf(1.0, delta * 8.0))
	var target := Vector2.ZERO
	var grounded := global_position.y > -0.3 and global_position.y < 0.4
	if alive and grounded and not _cheering and _pose not in ["hit", "jump", "kick"] and _speed > WALK_SPEED:

		var yaw := _model_pivot.rotation.y
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(cos(yaw), 0.0, -sin(yaw))
		var g := 9.8
		target.x = clampf(atan(_acc_s.dot(fwd) / g) * PITCH_GAIN, -PITCH_MAX, PITCH_MAX)
		target.y = clampf(-atan(_acc_s.dot(side) / g) * LEAN_GAIN, -LEAN_MAX, LEAN_MAX)
	_lean = _lean.lerp(target, minf(1.0, delta * 9.0))


func start_push_pose(dir: Vector3) -> void:

	var now := Time.get_ticks_msec()
	if now >= _next_yell_ms:
		_next_yell_ms = now + YELL_GAP_MS
		GameAudio.yell(weight_class)
	dir.y = 0.0
	_aim_face = dir.normalized() if dir.length_squared() > 0.0001 else _facing()
	if _model_pivot != null:
		_model_pivot.rotation.y = atan2(_aim_face.x, _aim_face.z)
	Fx.dash_dust(get_parent(), global_position, _aim_face)
	_squash_v -= 3.0
	if weight_class == WeightClass.LIGHT:
		_pose = "kick"
		_pose_len = KICK_POSE_TIME
	else:
		_pose = "push"
		_pose_len = DASH_POSE_TIME
	_pose_left = _pose_len

func _apply_action_pose(delta: float) -> void:
	var timed_w := 0.0
	if _pose != "":
		_pose_left = maxf(0.0, _pose_left - delta)
		var elapsed := _pose_len - _pose_left

		timed_w = smoothstep(0.0, 0.07, elapsed) * smoothstep(0.0, 0.16, _pose_left)
		if _pose_left == 0.0:
			if _pose == "kick":
				_squash_v -= 3.0
			elif _pose == "jump" and global_position.y > -0.5:
				_squash_v -= 6.0
				Fx.land_puff(get_parent(), global_position)
				GameAudio.play("bump", -6.0, 0.8)
			_pose = ""
	var hop := 0.0
	if _pose == "kick":
		_blend_pose(POSE_KICK, timed_w)
		hop = sin(PI * clampf((_pose_len - _pose_left) / _pose_len, 0.0, 1.0)) * KICK_HOP
	elif _pose == "hit":
		_blend_pose(POSE_HIT, timed_w)
	elif _pose == "jump":
		_blend_pose(POSE_JUMP, smoothstep(0.0, 0.08, _pose_len - _pose_left)
				* smoothstep(0.0, 0.1, _pose_left))
	else:
		var w := maxf(timed_w if _pose == "push" else 0.0, _contact_w)
		_blend_pose(POSE_PUSH, w)
	if _gloves != null:

		_gloves.position.z = (timed_w if _pose in ["push", "kick"] else 0.0) * 0.5
	if _flail_w > 0.0:
		var wave := sin(_t * 18.0)
		_blend_pose({
			"Spine": Vector3(-0.25, 0.0, 0.0),
			"ArmL": Vector3(-2.6 + 0.5 * wave, 0.0, 0.5),
			"ArmR": Vector3(-2.6 - 0.5 * wave, 0.0, -0.5),
			"LegL": Vector3(0.7 * wave, 0.0, 0.0),
			"LegR": Vector3(-0.7 * wave, 0.0, 0.0),
		}, _flail_w)
	_model_pivot.position.y = hop


func start_hit_pose(from: Vector3) -> void:
	if _cheering or _pose == "kick" or _pose == "jump":
		return
	_pose = "hit"
	_pose_len = HIT_POSE_TIME
	_pose_left = HIT_POSE_TIME
	_squash_v -= 5.0
	if _model_pivot != null:
		var d := from - global_position
		d.y = 0.0
		if d.length_squared() > 0.01:
			_model_pivot.rotation.y = atan2(d.x, d.z)

func _blend_pose(pose: Dictionary, w: float) -> void:
	if w <= 0.0:
		return
	for part: String in pose:
		if _rig.has(part):
			var node: Node3D = _rig[part]
			node.quaternion = node.quaternion.slerp(Quaternion.from_euler(pose[part]), w)


func _facing() -> Vector3:
	var yaw := _model_pivot.rotation.y if _model_pivot != null else 0.0
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _contact_direction() -> Vector3:
	if not alive or not visible:
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_gap := CONTACT_REACH
	for node in get_parent().get_children():
		if node == self or not (node is PlayerPawn):
			continue
		var other := node as PlayerPawn
		if not other.alive or not other.visible:
			continue
		var d := other.global_position - global_position
		if absf(d.y) > 1.0:
			continue
		d.y = 0.0
		var gap := d.length() - radius() - other.radius()
		if gap < best_gap and d.length_squared() > 0.0001:
			best_gap = gap
			best = d.normalized()
	return best


func cheer() -> void:
	if _anim == null or not _anim.has_animation("Cheer"):
		return
	_cheering = true
	_pose = ""
	_model_pivot.position.y = 0.0
	_anim.get_animation("Cheer").loop_mode = Animation.LOOP_LINEAR
	_anim.speed_scale = 1.0
	_anim.play("Cheer", 0.2)
	if _model_pivot != null:
		_model_pivot.rotation.y = 0.0


func respawn_at(point: Vector3, seq := -1) -> void:
	freeze = true
	if seq >= 0:
		net_seq = seq
	clear_net()
	global_position = point
	_last_pos = point
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	alive = true
	visible = true
	invuln_left = INVULN_TIME
	cooldown_left = 0.0
	stagger_left = 0.0
	ghost_left = 0.0
	_push_left = 0.0
	_jump_t = -1.0
	collision_layer = LAYER_PAWN
	set_floor_collision(true)
	clear_powerup()
	if gripped_by != null:
		gripped_by.detach()
	freeze = remote_controlled

	_pose = ""
	_pop = 0.2
	create_tween().tween_property(self, "_pop", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_floor_collision(on: bool) -> void:
	collision_mask = LAYER_FLOOR if on else 0

func has_floor_collision() -> bool:
	return collision_mask & LAYER_FLOOR != 0


func give_powerup(kind: int) -> void:
	clear_powerup()
	powerup = kind
	powerup_left = Powerup.DURATION[kind]
	powerup_age = 0.0
	if kind == Powerup.Kind.GLOVES:

		_gloves = Node3D.new()
		for side: float in [-1.0, 1.0]:
			var glove := Powerup.build_model(kind)
			glove.scale = Vector3.ONE * height() * 0.3
			glove.position = Vector3(side * (radius() + 0.08), height() * 0.55, radius() * 0.7)
			glove.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			_gloves.add_child(glove)
		(_model_pivot if _model_pivot != null else _visual).add_child(_gloves)
		return

	_badge = Powerup.build_model(kind)
	var held_bomb := kind == Powerup.Kind.BOMB
	_badge.scale = Vector3.ONE * (0.7 if held_bomb else 0.45)
	_badge.position.y = height() + (0.45 if held_bomb else 1.0)
	add_child(_badge)

func clear_powerup() -> void:
	powerup = -1
	powerup_left = 0.0
	if _badge != null:
		_badge.queue_free()
		_badge = null
	if _gloves != null:
		_gloves.queue_free()
		_gloves = null
	detach()


func sync_powerup(kind: int, left: float) -> void:
	if kind != powerup:
		if kind < 0:
			clear_powerup()
		else:
			give_powerup(kind)
	powerup_left = left


func hit_multiplier() -> float:
	return Powerup.GLOVES_HIT_MULT if powerup == Powerup.Kind.GLOVES else 1.0


func latch(victim: PlayerPawn) -> void:
	if latched != null or victim.gripped_by != null:
		return
	latched = victim
	victim.gripped_by = self
	victim.grip_left = Powerup.GRIP_TIME
	GameAudio.play("bump", 0.0, 1.4)

func detach() -> void:
	if latched != null:
		latched.gripped_by = null
		latched.grip_left = 0.0
		latched = null
