class_name TouchControls
extends Control


const SPLIT := 0.45
const STICK_RADIUS := 86.0
const AIM_RADIUS := 96.0
const AIM_DEADZONE := 16.0
const BUTTON_RADIUS := 74.0
const IDLE_ALPHA := 0.32
const GRAB_REACH := 1.6
const EDIT_MAX_X := 0.6

var pawn: PlayerPawn
var camera: Camera3D
var arena: Arena

var blocker: Control

var _move_touch := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _aim_touch := -1
var _aim_origin := Vector2.ZERO
var _aim_pos := Vector2.ZERO

signal push_committed(direction: Vector3)
signal bomb_thrown(target: Vector3)
signal jump_aimed(target: Vector3)
signal use_pressed
signal editing_done

var editing := false
var _edit_touch := -1
var _edit_ui: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func stick_home() -> Vector2:
	var view := get_viewport_rect().size
	var pos := Settings.stick_pos if Settings.stick_mode == Settings.STICK_FIXED else Settings.STICK_POS_DEFAULT

	return Vector2(pos.x * view.x, pos.y * view.y)


func reset_touches() -> void:
	_move_touch = -1
	if _aim_touch >= 0:
		_aim_touch = -1
	_edit_touch = -1


func start_editing() -> void:
	reset_touches()
	editing = true
	_edit_ui = VBoxContainer.new()
	_edit_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_edit_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edit_ui.offset_top = 110
	_edit_ui.add_theme_constant_override("separation", 10)
	add_child(_edit_ui)
	var hint := WorldTheme.title_label("Drag the joystick where you want it", 34)
	_edit_ui.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_edit_ui.add_child(row)
	var reset := Button.new()
	reset.text = "  Reset  "
	reset.add_theme_font_size_override("font_size", 28)
	reset.custom_minimum_size = Vector2(0, 60)
	WorldTheme.style_button(reset)
	reset.pressed.connect(func() -> void: Settings.stick_pos = Settings.STICK_POS_DEFAULT)
	row.add_child(reset)
	var done := Button.new()
	done.text = "  DONE  "
	done.add_theme_font_size_override("font_size", 28)
	done.custom_minimum_size = Vector2(0, 60)
	WorldTheme.style_button(done, Color(0.45, 0.9, 0.6))
	done.pressed.connect(finish_editing)
	row.add_child(done)

func finish_editing() -> void:
	editing = false
	_edit_touch = -1
	Settings.save()
	if _edit_ui != null:
		_edit_ui.queue_free()
		_edit_ui = null
	editing_done.emit()

func _edit_input(event: InputEvent) -> void:
	var view := get_viewport_rect().size
	if event is InputEventScreenTouch:
		_edit_touch = event.index if event.pressed else -1
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventScreenDrag and event.index == _edit_touch):

		var p: Vector2 = event.position
		var r := STICK_RADIUS + 8.0
		p.x = clampf(p.x, r, view.x * EDIT_MAX_X)
		p.y = clampf(p.y, r + 90.0, view.y - r)
		Settings.stick_pos = Vector2(p.x / view.x, p.y / view.y)

func _bomb_mode() -> bool:
	return pawn != null and pawn.alive and pawn.powerup == Powerup.Kind.BOMB


func _jump_mode() -> bool:
	return pawn != null and pawn.alive and pawn.powerup == Powerup.Kind.SHOES and not pawn.in_air()


func move_vector() -> Vector2:
	if editing:
		return Vector2.ZERO
	var screen := Vector2.ZERO
	if _move_touch >= 0:
		screen = ((_move_pos - _move_origin) / STICK_RADIUS).limit_length(1.0)
	else:
		screen = Vector2(
				float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
				-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
				float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
				-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		).limit_length(1.0)
	if screen == Vector2.ZERO:
		return Vector2.ZERO
	var world := _world_direction(screen)
	return Vector2(world.x, world.z) * screen.length()

func _unhandled_input(event: InputEvent) -> void:
	if editing:
		_edit_input(event)
		return
	if get_tree().paused:
		return
	var fixed := Settings.stick_mode == Settings.STICK_FIXED
	if event is InputEventScreenTouch:
		if event.pressed:
			if blocker != null and blocker.is_visible_in_tree() and blocker.get_global_rect().has_point(event.position):

				return
			var on_stick: bool = event.position.distance_to(stick_home()) <= STICK_RADIUS * GRAB_REACH

			if fixed and on_stick:
				if _move_touch < 0:
					_move_touch = event.index
					_move_origin = stick_home()
					_move_pos = event.position
			elif not fixed and event.position.x < get_viewport_rect().size.x * SPLIT:
				if _move_touch < 0:
					_move_touch = event.index
					_move_origin = event.position
					_move_pos = event.position
			elif fixed and event.position.x < get_viewport_rect().size.x * SPLIT:
				pass
			elif _aim_touch < 0:
				_aim_touch = event.index
				_aim_origin = event.position
				_aim_pos = event.position
		elif event.index == _move_touch:
			_move_touch = -1
		elif event.index == _aim_touch:
			_aim_touch = -1
			_release_aim()
	elif event is InputEventScreenDrag:
		if event.index == _move_touch:
			_move_pos = event.position

			var over := _move_pos - _move_origin
			if not fixed and over.length() > STICK_RADIUS:
				_move_origin = _move_pos - over.normalized() * STICK_RADIUS
		elif event.index == _aim_touch:
			_aim_pos = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and _jump_mode():

			jump_aimed.emit(pawn.global_position + pawn._facing() * 5.0)
		elif event.physical_keycode == KEY_SPACE and not _bomb_mode():
			push_committed.emit(Vector3.ZERO)
		elif event.physical_keycode == KEY_E:
			use_pressed.emit()

func _release_aim() -> void:
	var pull := _aim_pos - _aim_origin
	if _bomb_mode():
		var target: Variant = _bomb_target()
		if target != null:
			bomb_thrown.emit(target)
	elif _jump_mode():
		var spot: Variant = _jump_target()
		if spot != null:
			jump_aimed.emit(spot)
	elif pull.length() < AIM_DEADZONE:
		push_committed.emit(Vector3.ZERO)
	else:
		push_committed.emit(_world_direction(pull))


func _bomb_target() -> Variant:
	var pull := _aim_pos - _aim_origin
	if pawn == null or pull.length() < AIM_DEADZONE:
		return null
	var k := clampf((pull.length() - AIM_DEADZONE) / (AIM_RADIUS - AIM_DEADZONE), 0.0, 1.0)
	var from := pawn.global_position
	var target := from + _world_direction(pull) * lerpf(Powerup.BOMB_MIN_RANGE,
			Powerup.BOMB_MAX_RANGE, k)
	target.y = 0.0
	return target


func _jump_target() -> Variant:
	var pull := _aim_pos - _aim_origin
	if pawn == null or pull.length() < AIM_DEADZONE:
		return null
	var k := clampf((pull.length() - AIM_DEADZONE) / (AIM_RADIUS - AIM_DEADZONE), 0.0, 1.0)
	var target := pawn.global_position + _world_direction(pull) * lerpf(Powerup.JUMP_MIN_RANGE,
			Powerup.JUMP_MAX_RANGE, k)
	target.y = 0.0
	return target


func _world_direction(screen_dir: Vector2) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	return (right * screen_dir.x + forward * -screen_dir.y).normalized()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if pawn == null or camera == null:
		return
	var view := get_viewport_rect().size
	var live := pawn.alive

	var held := _move_touch >= 0
	var base := _move_origin if held else stick_home()
	var knob := base + (_move_pos - _move_origin).limit_length(STICK_RADIUS) if held else base
	var a := 0.55 if held else IDLE_ALPHA
	if editing:
		a = 0.85
		draw_arc(base, STICK_RADIUS + 14.0, 0.0, TAU, 48, Color(0.45, 0.9, 0.6, 0.9), 5.0, true)
	draw_circle(base, STICK_RADIUS, Color(0.06, 0.09, 0.15, a * 0.6))
	draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, a), 3.0, true)
	draw_circle(knob, 34.0, Color(1, 1, 1, a + 0.15))

	var bomb := _bomb_mode()
	var jump := _jump_mode()
	var aiming := _aim_touch >= 0
	var center := _aim_origin if aiming else Vector2(view.x - 150.0, view.y - 140.0)
	var pull := (_aim_pos - _aim_origin) if aiming else Vector2.ZERO
	var tint := Color(1.0, 0.55, 0.15) if bomb else (pawn.stats().color as Color).lightened(0.25)
	if jump:
		tint = Powerup.COLORS[Powerup.Kind.SHOES]
	var armed := live and (bomb or jump or pawn.can_push())
	var ba := (0.7 if aiming else 0.45) * (1.0 if armed else 0.55)
	draw_circle(center, BUTTON_RADIUS, Color(tint.r, tint.g, tint.b, ba * 0.55))
	draw_arc(center, BUTTON_RADIUS, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, ba + 0.25), 4.0, true)
	if not bomb and not jump and pawn.cooldown_left > 0.0:

		var k := 1.0 - pawn.cooldown_left / float(pawn.stats().cooldown)
		draw_arc(center, BUTTON_RADIUS - 8.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40,
				Color(1, 1, 1, 0.8), 5.0, true)
	var font := get_theme_default_font()
	draw_string(font, center + Vector2(-BUTTON_RADIUS, 9.0),
			"THROW" if bomb else ("JUMP" if jump else "PUSH"),
			HORIZONTAL_ALIGNMENT_CENTER, BUTTON_RADIUS * 2.0, 26, Color(1, 1, 1, ba + 0.3))
	if aiming and pull.length() >= AIM_DEADZONE:
		draw_circle(center + pull.limit_length(AIM_RADIUS), 26.0, Color(1, 1, 1, 0.75))

	if not live or not aiming or camera.is_position_behind(pawn.global_position):
		return
	if bomb:
		_draw_throw()
	elif jump:
		_draw_jump()
	elif pull.length() >= AIM_DEADZONE:

		var dir := _world_direction(pull)
		var from3 := pawn.global_position + Vector3.UP * 0.6
		var o := camera.unproject_position(from3 + dir * (pawn.radius() + 0.2))
		var tip := camera.unproject_position(from3 + dir * (pawn.radius() + 2.2))
		var col := Color(tint.r, tint.g, tint.b, 0.8 if armed else 0.35)
		draw_line(o, tip, col, 6.0, true)
		var d2 := (tip - o).normalized()
		draw_colored_polygon(PackedVector2Array([tip + d2 * 16.0,
				tip - d2.rotated(0.9) * 16.0, tip - d2.rotated(-0.9) * 16.0]), col)


func _draw_throw() -> void:
	var target: Variant = _bomb_target()
	if target == null:
		return
	var to: Vector3 = target
	var from := pawn.global_position + Vector3.UP * (pawn.height() + 0.45)
	var on_map := arena == null or arena.contains(to)
	var col := Color(1.0, 0.55, 0.12, 0.95) if on_map else Color(1.0, 0.2, 0.15, 0.9)
	var arc := PackedVector2Array()
	for i in 21:
		arc.append(camera.unproject_position(Powerup.bomb_arc(from, to, i / 20.0)))

	for i in range(0, 20, 2):
		draw_line(arc[i], arc[i + 1], col, 4.0, true)
	var r := Powerup.hole_radius()
	var ring := PackedVector2Array()
	for i in 41:
		var ang := TAU * i / 40.0
		ring.append(camera.unproject_position(to + Vector3(cos(ang) * r, 0.0, sin(ang) * r)))
	draw_polyline(ring, col, 4.0, true)
	draw_line(ring[0], ring[20], col, 2.0)
	draw_line(ring[10], ring[30], col, 2.0)


func _draw_jump() -> void:
	var spot: Variant = _jump_target()
	if spot == null:
		return
	var to: Vector3 = spot
	var from := pawn.global_position
	from.y = 0.0
	var on_map := arena == null or arena.contains(to)
	var base: Color = Powerup.COLORS[Powerup.Kind.SHOES]
	var col := Color(base.r, base.g, base.b, 0.95) if on_map else Color(1.0, 0.2, 0.15, 0.9)
	var arc := PackedVector2Array()
	for i in 21:
		arc.append(camera.unproject_position(Powerup.jump_arc(from, to, i / 20.0)
				+Vector3.UP * pawn.height() * 0.5))
	for i in range(0, 20, 2):
		draw_line(arc[i], arc[i + 1], col, 4.0, true)
	var r := pawn.radius() + 0.25
	var ring := PackedVector2Array()
	for i in 33:
		var ang := TAU * i / 32.0
		ring.append(camera.unproject_position(to + Vector3(cos(ang) * r, 0.0, sin(ang) * r)))
	draw_polyline(ring, col, 4.0, true)
	draw_circle(camera.unproject_position(to), 5.0, col)
