extends SceneTree


const DT := 1.0 / 60.0
const CLASSES := [PlayerPawn.WeightClass.LIGHT, PlayerPawn.WeightClass.NORMAL,
		PlayerPawn.WeightClass.HEAVY]

var _root: Node3D


class ContactStepper extends Node:
	var touching := {}

	func _physics_process(_delta: float) -> void:
		var list: Array = []
		for n in get_parent().get_children():
			if n is PlayerPawn:
				list.append(n)
		PlayerPawn.resolve_contacts(list, touching, func(_a: PlayerPawn, _b: PlayerPawn, _s: float) -> void: pass)

func _initialize() -> void:

	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	Engine.max_physics_steps_per_frame = 64
	_root = Node3D.new()
	root.add_child(_root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PlayerPawn.LAYER_FLOOR
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	shape.shape = box
	shape.position.y = -1.0
	floor_body.add_child(shape)
	_root.add_child(floor_body)
	_root.add_child(ContactStepper.new())
	_run()

func _spawn(cls: int, pos: Vector3) -> PlayerPawn:
	var p := PlayerPawn.new()
	p.weight_class = cls
	p.position = pos

	p.shoved.connect(func(victim: PlayerPawn, _power: float, impulse: Vector3) -> void:
		victim.take_shove(impulse))
	_root.add_child(p)
	await physics_frame
	p.freeze = false
	return p

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _flat_speed(p: PlayerPawn) -> float:
	return Vector2(p.linear_velocity.x, p.linear_velocity.z).length()

func _name(cls: int) -> String:
	return PlayerPawn.STATS[cls]["label"]

func _run() -> void:
	await _ticks(10)
	print("TUNE speed unit = %.3f m/s  (arena radius ~16 m)" % PlayerPawn.SPEED_UNIT)
	for cls: int in CLASSES:
		await _buildup(cls)
	for cls: int in CLASSES:
		await _movement(cls)
	print("TUNE push: metres the victim is thrown  [standing / running / running away / ram only]")
	for a: int in CLASSES:
		for v: int in CLASSES:
			var standing := await _push(a, v, 0)
			var running := await _push(a, v, 1)
			var away := await _push(a, v, -1)
			var ram := await _push(a, v, 2)
			print("TUNE   %-6s -> %-6s  %5.1f / %5.1f / %5.1f / %5.1f" % [_name(a), _name(v),
					standing, running, away, ram])
	print("TUNE_DONE")
	quit()

func _movement(cls: int) -> void:
	var p: PlayerPawn = await _spawn(cls, Vector3(0, 0.05, 0))
	await _ticks(20)
	var cap := p.top_speed()

	p.move_input = Vector2(1, 0)
	var t := 0
	var start := p.global_position
	while _flat_speed(p) < cap * 0.95 and t < 600:
		await physics_frame
		t += 1
	var accel_time := t * DT
	var accel_dist := p.global_position.distance_to(start)
	await _ticks(60)
	var top := _flat_speed(p)

	p.move_input = Vector2.ZERO
	start = p.global_position
	t = 0
	while _flat_speed(p) > 0.05 and t < 600:
		await physics_frame
		t += 1
	var stop_time := t * DT
	var stop_dist := p.global_position.distance_to(start)

	p.move_input = Vector2(1, 0)
	await _ticks(240)
	start = p.global_position
	p.move_input = Vector2(0, 1)
	t = 0
	var slowest := INF
	while t < 600:
		await physics_frame
		t += 1
		slowest = minf(slowest, _flat_speed(p))
		var h := Vector2(p.linear_velocity.x, p.linear_velocity.z).normalized()
		if h.dot(Vector2(0, 1)) > 0.996:
			break
	var turn_time := t * DT
	var carry := p.global_position.x - start.x

	await _ticks(240)
	p.move_input = Vector2(0, -1)
	t = 0
	start = p.global_position
	while p.linear_velocity.z > 0.05 and t < 600:
		await physics_frame
		t += 1
	var rev_stop := t * DT
	var rev_dist := p.global_position.distance_to(start)
	while p.linear_velocity.z > -cap * 0.95 and t < 1200:
		await physics_frame
		t += 1
	var rev_total := t * DT
	print("TUNE %-6s top %.2f m/s (%.0f units) | 0→95%%: %.2f s, %.1f m | release stop: %.2f s, %.1f m" % [
			_name(cls), top, top / PlayerPawn.SPEED_UNIT, accel_time, accel_dist, stop_time, stop_dist])
	print("TUNE        90° turn: %.2f s, carries %.1f m, slowest %.0f%% | 180°: stops in %.2f s / %.1f m, back at speed after %.2f s" % [
			turn_time, carry, slowest / cap * 100.0, rev_stop, rev_dist, rev_total])
	p.queue_free()
	await _ticks(2)


func _buildup(cls: int) -> void:
	var p: PlayerPawn = await _spawn(cls, Vector3(0, 0.05, 0))
	await _ticks(10)
	p.move_input = Vector2(1, 0)
	var out := []
	var t := 0
	for mark: float in [0.5, 1.0, 2.0, 3.0]:
		while t * DT < mark:
			await physics_frame
			t += 1
		out.append("%.1fs %.2f m/s (%.0f%%)" % [mark, _flat_speed(p), _flat_speed(p) / p.top_speed() * 100.0])
	print("TUNE %-6s build-up: %s" % [_name(cls), " | ".join(out)])
	p.queue_free()
	await _ticks(2)


func _push(a_cls: int, v_cls: int, mode: int) -> float:
	var a: PlayerPawn = await _spawn(a_cls, Vector3(-14.0 if mode > 0 else 0.0, 0.05, 0))
	var v: PlayerPawn = await _spawn(v_cls, Vector3(0, 0.05, 0))
	var touch := a.radius() + v.radius()
	if mode == 0:
		a.position.x = -(touch + 0.3)
	elif mode == -1:
		a.position.x = -(touch + 0.3) - 7.0
	await _ticks(20)
	var start := v.global_position
	if mode == 0:
		a.try_push(Vector3.RIGHT)
	elif mode == -1:

		a.global_position = Vector3(-(touch + 0.3), 0.05, 0)
		a.linear_velocity = Vector3(-a.top_speed(), 0, 0)
		await physics_frame
		a.try_push(Vector3.RIGHT)
	else:
		a.move_input = Vector2(1, 0)
		var t := 0
		while t < 900:
			await physics_frame
			t += 1
			var gap := v.global_position.x - a.global_position.x - touch
			if mode == 1 and gap < PlayerPawn.PUSH_REACH * 0.8:
				a.try_push(Vector3.RIGHT)
				break
			if mode == 2 and gap < 0.02:
				break
		a.move_input = Vector2.ZERO

	var t2 := 0
	await _ticks(10)
	while _flat_speed(v) > 0.05 and t2 < 900:
		await physics_frame
		t2 += 1
	var dist := v.global_position.distance_to(start)
	a.queue_free()
	v.queue_free()
	await _ticks(2)
	return dist
