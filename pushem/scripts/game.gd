class_name Game
extends Node3D


enum Phase {LOADING, COUNTDOWN, PUSH, SHRINK, OVER}
enum Mode {SOLO, HOST, CLIENT}

const COUNTDOWN_SECS := 3.0
const PUSH_PHASE_SECS := 60.0


const SHRINK_SECS := 60.0
const SHRINK_RATE := 0.95 / SHRINK_SECS
const RESPAWN_DELAY := 1.5
const RESTART_DELAY := 5.0
const START_LIVES := 3
const LOAD_TIMEOUT := 20.0

const HIT_SLACK := 1.6
const REPORT_WINDOW := 0.8


const FIT_EASE := 2.5
const CAMERA_ELEVATION_DEG := 54.0
const CLOSE_DIST := 11.0
const CAMERA_FOLLOW_RATE := 5.0


const SHAKE_MAX := 0.55
const SHAKE_DECAY := 1.8


const HIT_STOP_SECS := 0.06
const HIT_STOP_MIN := 0.55

const FOG_BEGIN := 110.0

const SKY_AMBIENT_GAIN := 1.6
const FOG_END := 1100.0

const HIT_DEDUP_MS := 150

const FRAME_MARGIN_TOP := 96.0
const FRAME_MARGIN_BOTTOM := 56.0
const FRAME_MARGIN_SIDE := 24.0

const DROP_SET := [
	Powerup.Kind.BOMB, Powerup.Kind.BOMB, Powerup.Kind.BOMB, Powerup.Kind.BOMB,
	Powerup.Kind.GLOVES, Powerup.Kind.GLOVES,
	Powerup.Kind.SPIKES, Powerup.Kind.SPIKES,
	Powerup.Kind.DASH, Powerup.Kind.DASH,
	Powerup.Kind.SHOES, Powerup.Kind.SHOES,
]
const DROP_WINDOW := Vector2(3.0, 56.0)
const DROP_MARGIN := 1.6
const LEFTOVER_SECS := 5.0


const SNAP_HEADER := 14
const SNAP_PER_PAWN := 26

const STATE_SIZE := 24

var map_shape: Arena.Shape = Arena.Shape.CIRCLE
var world: WorldTheme.Kind = WorldTheme.Kind.WINDY
var local_char := Characters.DEFAULT
var net: Net

var mode: Mode = Mode.SOLO
var arena: Arena
var pawns := {}
var local_pawn: PlayerPawn
var hud: Hud
var camera: Camera3D
var _full_dist := 40.0
var _fit := -1.0
var _cam_dir := Vector3.UP
var _cam_focus := Vector3.ZERO
var _sun: DirectionalLight3D
var _weather: CPUParticles3D
var _weather_offset := Vector3.ZERO
var _trauma := 0.0

var _perf_frames := 0
var _perf_secs := 0.0
var _crumble_accum := 0.0
var _last_hits := {}
var controls: TouchControls

var auto_local := false
var _state_accum := 0.0
var _loaded := false
var _pending_events: Array = []
var _loading_ui: CanvasLayer
var _loading_bar: ProgressBar
var _scenery: WorldScenery
var _touching := {}

var _host_clock := Net.Clock.new()
var _clocks := {}
var _latest := {}
var _push_ms := {}
var _jump_ms := {}

var net_stats := {"snaps": 0, "states": 0, "knocks_sent": 0, "knocks_ok": 0, "knocks_bad": 0,
		"knocks_taken": 0}

var phase: Phase = Phase.LOADING

var push_secs := PUSH_PHASE_SECS
var _log_events := "--logevents" in OS.get_cmdline_user_args()
var phase_time := 0.0
var _snapshot_accum := 0.0
var _last_countdown := -1

var _drops := {}
var _next_drop_id := 1
var _drop_schedule: Array = []
var _holes: Array[Dictionary] = []


var _flying: Array[Dictionary] = []
var _bombs_due: Array = []

# --- Knockout credit, victory moment and post-match payout (all local) -------
const KO_CREDIT_MS := 6000
const VICTORY_SLOWMO := 0.3
const VICTORY_SLOWMO_SECS := 1.1
const VICTORY_DIST := 8.5
const VICTORY_ELEVATION_DEG := 30.0
const VICTORY_ORBIT := 0.35
const RESULTS_DELAY := 2.2

var _last_attacker := {}
var _kos := {}
var _out_order: Array[int] = []
var _powerups_used := 0
var _victor: PlayerPawn
var _victory_t := 0.0
var _victory_yaw := 0.0
var _results: ResultsScreen
var _hold_finish := false
var _vignette: CanvasLayer

signal match_finished

signal loaded

signal exit_requested

var _menu: GameMenu
var _menu_layer: CanvasLayer

func _ready() -> void:

	process_mode = Node.PROCESS_MODE_PAUSABLE
	if net != null and net.role == Net.Role.HOST:
		mode = Mode.HOST
	elif net != null and net.role == Net.Role.CLIENT:
		mode = Mode.CLIENT
	if net != null:
		net.game = self
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pushsecs="):
			push_secs = maxf(5.0, float(arg.get_slice("=", 1)))
	_show_loading()
	_load()


func _load() -> void:
	var steps: Array[Callable] = [_build_world]
	if not _lite():
		steps.append(_add_scenery)
	var t0 := Time.get_ticks_msec()
	var i := 0
	while i < steps.size():
		steps[i].call()
		if steps[i] == _add_scenery:
			steps.append_array(_scenery.steps())
		i += 1
		_loading_progress(float(i) / (steps.size() + 4))
		await get_tree().process_frame
	_spawn_pawns()
	_build_ui()
	_loading_progress(0.85)
	_warm_up()
	for f in 3:
		await get_tree().process_frame
	_loading_progress(1.0)
	print("MATCH_LOADED %d ms" % (Time.get_ticks_msec() - t0))
	_loaded = true
	_hide_loading()
	loaded.emit()
	for ev: Array in _pending_events:
		apply_event(ev[0], ev[1])
	_pending_events.clear()
	if mode == Mode.CLIENT:
		net.report_loaded.rpc_id(1)
	elif mode == Mode.SOLO:
		_set_phase(Phase.COUNTDOWN)


func _show_loading() -> void:
	_loading_ui = CanvasLayer.new()
	_loading_ui.layer = 50
	add_child(_loading_ui)
	var back := WorldTheme.make_backdrop(world)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_ui.add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 18)
	_loading_ui.add_child(box)
	var title := UiKit.title("LOADING " + str(WorldTheme.NAMES[world]).to_upper(), 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(520, 22)
	_loading_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = WorldTheme.MENU_ACCENT
	fill.set_corner_radius_all(11)
	var bg := StyleBoxFlat.new()
	bg.bg_color = WorldTheme.MENU_FIELD
	bg.set_corner_radius_all(11)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_loading_bar)

func _loading_progress(f: float) -> void:
	if _loading_bar != null:
		_loading_bar.value = f

func _hide_loading() -> void:
	if _loading_ui != null:
		var ui := _loading_ui
		_loading_ui = null
		_loading_bar = null
		var tw := create_tween()
		for c in ui.get_children():
			if c is CanvasItem:
				tw.parallel().tween_property(c, "modulate:a", 0.0, 0.3)
		tw.tween_callback(ui.queue_free)


func _warm_up() -> void:
	var spot := _cam_focus + Vector3(0.0, 0.6, 0.0)
	var temp: Array[Node3D] = []
	for kind: int in Powerup.Kind.values():
		var model := Powerup.build_model(kind)
		model.position = spot + Vector3(randf_range(-2, 2), 0.0, randf_range(-2, 2))
		add_child(model)
		temp.append(model)
	var marker := Powerup.landing_marker(Powerup.hole_radius())
	marker.position = spot
	add_child(marker)
	temp.append(marker)
	var hole := Powerup.make_hole(Powerup.hole_radius(), arena.wall_color())
	hole.position = Vector3(spot.x, -60.0, spot.z)
	add_child(hole)
	temp.append(hole)
	Fx.dash_dust(self, spot, Vector3.FORWARD)
	Fx.hit(self, spot, 1.0)
	Fx.explosion(self, spot)
	Fx.land_puff(self, spot)
	Fx.sparkle(self, spot, Color(1.0, 0.8, 0.3))
	Fx.crumble(self, spot, Vector3.RIGHT, arena.rock_color())
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		for n in temp:
			if is_instance_valid(n):
				n.queue_free())

func _is_sim() -> bool:
	return mode != Mode.CLIENT


func _owner_of(id: int) -> int:
	return 1 if id < 0 else id


func _simulates(id: int) -> bool:
	match mode:
		Mode.SOLO:
			return true
		Mode.HOST:
			return _owner_of(id) == 1
	return id == _my_id()

func _lite() -> bool:
	return net != null and net.lite_render and mode == Mode.HOST


func _is_dedicated() -> bool:
	return mode == Mode.HOST and not net.host_is_player

func _build_world() -> void:
	arena = Arena.new()
	arena.shape = map_shape
	arena.world = world
	add_child(arena)
	Fx.world = world

	var pal: Dictionary = WorldTheme.PALETTES[world]
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.shadow_enabled = not _lite() and Settings.quality()["shadows"]
	_sun = sun
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_energy"]
	add_child(sun)
	if not _lite() and Settings.graphics != Settings.Quality.LOW:
		# Back light from the opposite side so fighters read against the floor.
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-28, 150, 0)
		rim.shadow_enabled = false
		rim.light_color = (pal["sky_horizon"] as Color).lerp(Color.WHITE, 0.45)
		rim.light_energy = 0.55
		rim.light_specular = 1.4
		add_child(rim)
		_vignette = _make_vignette()
		add_child(_vignette)

	var env := Environment.new()
	env.ambient_light_color = pal["ambient"]
	env.ambient_light_energy = pal["ambient_energy"]
	if _lite():
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	else:

		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = pal["sky_top"]
		sky_mat.sky_horizon_color = pal["sky_horizon"]
		sky_mat.ground_horizon_color = pal["sky_horizon"]
		sky_mat.ground_bottom_color = pal["sky_ground"]
		sky_mat.sun_angle_max = 0.0

		sky_mat.energy_multiplier = float(pal["ambient_energy"]) * SKY_AMBIENT_GAIN
		var sky := Sky.new()
		sky.sky_material = sky_mat
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		sky.radiance_size = Settings.quality()["sky_radiance"]
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.7
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_grade(env, pal)
	if _lite():
		env.background_mode = Environment.BG_COLOR
		env.background_color = pal["lite_bg"]
	else:

		env.background_mode = Environment.BG_COLOR
		env.background_color = pal["fog"]
		_weather = Fx.ambient(world)
		if _weather != null:
			_weather_offset = _weather.position
			add_child(_weather)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	_frame_camera()

	if _is_dedicated() and net.lite_render:
		get_viewport().disable_3d = true


func _make_vignette() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -1
	var rect := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0.03, 0.42)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 128
	tex.height = 128
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return layer


func _add_scenery() -> void:
	_scenery = WorldScenery.new()
	_scenery.world = world
	_scenery.rim = arena.glacier_radius()
	_scenery.build_in_steps = true
	add_child(_scenery)


func _grade(env: Environment, pal: Dictionary) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = pal["exposure"]

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tonemap="):
			env.tonemap_mode = {"linear": Environment.TONE_MAPPER_LINEAR,
					"filmic": Environment.TONE_MAPPER_FILMIC,
					"aces": Environment.TONE_MAPPER_ACES,
					"agx": Environment.TONE_MAPPER_AGX}.get(arg.get_slice("=", 1),
					Environment.TONE_MAPPER_FILMIC)
	var grade: Vector3 = pal["grade"]
	env.adjustment_enabled = true
	env.adjustment_brightness = grade.x
	env.adjustment_contrast = grade.y
	env.adjustment_saturation = grade.z
	if Settings.quality()["glow"] and not _lite():
		env.glow_enabled = true
		env.glow_intensity = pal["glow_intensity"]
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = pal["glow_threshold"]
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = pal["fog"]
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.2
	env.fog_height = pal.get("fog_height", -20.0)
	env.fog_height_density = pal.get("fog_height_density", 0.005)


func _frame_camera() -> void:
	var r := arena.current_radius()
	var corners: Array[Vector3] = []
	for p in Arena.base_points_for(arena.shape):
		corners.append(Vector3(p.x, 0.0, p.y))
		corners.append(Vector3(p.x, -Arena.FLOOR_THICKNESS, p.y))
	var view := get_viewport().get_visible_rect().size
	var sx := view.x / 1280.0
	var sy := view.y / 720.0
	var safe := Rect2(FRAME_MARGIN_SIDE * sx, FRAME_MARGIN_TOP * sy,
			view.x - 2.0 * FRAME_MARGIN_SIDE * sx,
			view.y - (FRAME_MARGIN_TOP + FRAME_MARGIN_BOTTOM) * sy)
	var elevation := deg_to_rad(CAMERA_ELEVATION_DEG)
	var dir := Vector3(0, sin(elevation), cos(elevation))
	var best_dist := INF
	var best_aim := Vector3.ZERO
	for aim_step in 6:
		var aim := Vector3(0, 0, r * 0.05 * aim_step)
		for k in 60:
			var dist := r * (1.2 + k * 0.05)
			if dist >= best_dist:
				break
			camera.look_at_from_position(aim + dir * dist, aim, Vector3.UP)
			var fits := true
			for c in corners:
				if camera.is_position_behind(c) or not safe.has_point(camera.unproject_position(c)):
					fits = false
					break
			if fits:
				best_dist = dist
				best_aim = aim
				break
	if best_dist == INF:
		best_dist = r * 3.0
	camera.look_at_from_position(best_aim + dir * best_dist, best_aim, Vector3.UP)
	_full_dist = best_dist
	_cam_dir = dir
	_cam_focus = best_aim

func _camera_dist() -> float:
	var full := _fit if _fit > 0.0 else _fit_dist(_cam_focus)
	return lerpf(full, minf(CLOSE_DIST, full), Settings.zoom)


func _fit_dist(focus: Vector3) -> float:
	var view := get_viewport().get_visible_rect().size
	var sx := view.x / 1280.0
	var sy := view.y / 720.0
	var k := (view.y * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	var left := (FRAME_MARGIN_SIDE * sx - view.x * 0.5) / k
	var right := (view.x * 0.5 - FRAME_MARGIN_SIDE * sx) / k
	var up := (view.y * 0.5 - FRAME_MARGIN_TOP * sy) / k
	var down := (FRAME_MARGIN_BOTTOM * sy - view.y * 0.5) / k
	var basis := camera.global_basis
	var need := CLOSE_DIST
	for p in arena.outline():
		for y: float in [0.0, -Arena.FLOOR_THICKNESS]:
			var q := basis.inverse() * (Vector3(p.x, y, p.y) - focus)
			var dx := q.x / (right if q.x > 0.0 else left)
			var dy := q.y / (up if q.y > 0.0 else down)
			need = maxf(need, q.z + maxf(dx, dy))
	return need


func _follow_point() -> Vector3:
	if local_pawn != null and local_pawn.alive and local_pawn.visible:
		var p := local_pawn.global_position
		if p.y > -1.0:
			return Vector3(p.x, 0.0, p.z)
		return _cam_focus
	var sum := Vector3.ZERO
	var n := 0
	for p: PlayerPawn in pawns.values():
		if p.alive and p.global_position.y > -1.0:
			sum += Vector3(p.global_position.x, 0.0, p.global_position.z)
			n += 1
	return sum / n if n > 0 else _cam_focus


func _update_music() -> void:
	if phase == Phase.SHRINK:
		GameAudio.set_music_progress(phase_time / SHRINK_SECS)
	else:
		GameAudio.stop_music()


func open_menu(options := false) -> void:
	if _menu != null:
		_menu.show_page(options)
		return
	if controls != null:
		controls.reset_touches()
	if mode == Mode.SOLO:
		get_tree().paused = true
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 20
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_layer)
	_menu = GameMenu.new()
	_menu.paused_match = mode == Mode.SOLO
	_menu.resumed.connect(close_menu)
	_menu.exit_to_menu.connect(_confirm_exit_to_menu)
	_menu.adjust_stick.connect(func() -> void:
		_hide_menu()
		if controls != null:
			controls.start_editing())
	_menu_layer.add_child(_menu)
	_menu.show_page(options)

func close_menu() -> void:
	_hide_menu()
	get_tree().paused = false

func _hide_menu() -> void:
	if _menu_layer != null:
		_menu_layer.queue_free()
	_menu_layer = null
	_menu = null

func _confirm_exit_to_menu() -> void:
	var text := "Leave this practice match?"
	var more := ""
	if mode == Mode.HOST:
		text = "End the match for everyone?"
		more = "You're the host: leaving ends the game and sends every player back to the menu."
	elif mode == Mode.CLIENT:
		text = "Leave the match?"
		more = "You'll be out of this game; the others play on."
	ConfirmBox.ask(_menu, text, func() -> void:
		_hide_menu()
		exit_requested.emit(), "Leave", more)


func handle_back() -> void:
	if controls != null and controls.editing:
		controls.finish_editing()
	elif _menu != null:
		_menu.go_back()
	else:
		open_menu()

func _exit_tree() -> void:
	get_tree().paused = false
	if _perf_secs > 0.0:
		DeviceProfile.record_match_fps(Settings.graphics, _perf_frames / _perf_secs, _perf_secs)
	GameAudio.stop_music(true)
	Engine.time_scale = 1.0


func _crumble_edge(delta: float) -> void:
	if phase != Phase.SHRINK or arena.shrink_factor <= 0.06 or _lite():
		return
	_crumble_accum += delta
	var interval: float = [0.3, 0.16, 0.1][Settings.scenery]
	while _crumble_accum >= interval:
		_crumble_accum -= interval
		var edge := arena.random_edge_point()
		Fx.crumble(self, edge[0], edge[1], arena.rock_color())


func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _shake_at(pos: Vector3, amount: float) -> void:
	var d := Vector2(pos.x - _cam_focus.x, pos.z - _cam_focus.z).length()
	add_shake(amount * clampf(1.2 - d / 18.0, 0.15, 1.0))

func _hit_stop() -> void:
	if mode == Mode.HOST or Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	get_tree().create_timer(HIT_STOP_SECS, true, false, true).timeout.connect(
			func() -> void: Engine.time_scale = 1.0)


func _on_pawn_shoved(victim: PlayerPawn, power: float, impulse: Vector3,
		attacker: PlayerPawn) -> void:
	var payload := {"id": id_of(victim), "v": impulse, "p": power}
	if mode == Mode.CLIENT:
		net.report_knock.rpc_id(1, payload)
		net_stats["knocks_sent"] += 1
	else:
		_deliver_knock(attacker, victim, payload)


func _on_pawn_stomped(victim: PlayerPawn, dir: Vector3, distance: float,
		jumper: PlayerPawn) -> void:
	var payload := {"id": id_of(victim), "dir": dir, "d": distance,
			"p": jumper.stats().push * 1.5}
	if mode == Mode.CLIENT:
		net.report_knock.rpc_id(1, payload)
	else:
		_deliver_knock(jumper, victim, payload)


func _deliver_knock(attacker: PlayerPawn, victim: PlayerPawn, payload: Dictionary) -> void:
	payload["by"] = id_of(attacker)
	_emit("knock", payload)
	var a := id_of(attacker)
	var b := id_of(victim)
	_last_hits["%d:%d" % [mini(a, b), maxi(a, b)]] = Time.get_ticks_msec()
	var pos := (victim.global_position + attacker.global_position) * 0.5 + Vector3.UP * 0.8
	_emit("hit", {"pos": pos, "s": clampf(float(payload["p"]) / victim.mass / 14.0, 0.25, 1.0),
			"a": a, "b": b})


func apply_knock_report(peer_id: int, payload: Dictionary) -> void:
	if not _playing() or not pawns.has(peer_id) or not pawns.has(payload.get("id", 0)):
		return
	var attacker: PlayerPawn = pawns[peer_id]
	var victim: PlayerPawn = pawns[payload["id"]]
	net_stats["knocks_bad"] += 1
	if attacker == victim or not attacker.alive or not victim.alive or victim.invuln_left > 0.0:
		return
	var gap := attacker.global_position - victim.global_position
	gap.y = 0.0
	var now := Time.get_ticks_msec()
	var clean := {"id": payload["id"]}
	if payload.has("d"):
		if now - int(_jump_ms.get(peer_id, -100000)) > REPORT_WINDOW * 1000.0 or gap.length() > 3.5:

			return
		var dir: Vector3 = payload.get("dir", Vector3.ZERO)
		dir.y = 0.0
		if not dir.is_finite() or dir.length_squared() < 0.01:
			return
		clean["dir"] = dir.normalized()
		clean["d"] = clampf(float(payload["d"]), 0.5, Powerup.JUMP_STOMP_DISTANCE)
		clean["p"] = attacker.stats().push * 1.5
	else:
		var impulse: Vector3 = payload.get("v", Vector3.ZERO)
		if now - int(_push_ms.get(peer_id, -100000)) > REPORT_WINDOW * 1000.0 or gap.length() > attacker.radius() + victim.radius() + PlayerPawn.PUSH_REACH + HIT_SLACK or not impulse.is_finite():

			return
		clean["v"] = impulse.limit_length(attacker.max_push())
		clean["p"] = clean["v"].length()
	net_stats["knocks_bad"] -= 1
	net_stats["knocks_ok"] += 1
	_deliver_knock(attacker, victim, clean)


func _on_pawn_broke_free(pawn: PlayerPawn) -> void:
	if mode == Mode.CLIENT:
		net.report_release.rpc_id(1)
	else:
		_emit("release", {"id": id_of(pawn)})


func apply_release_report(peer_id: int) -> void:
	if pawns.has(peer_id):
		var pawn: PlayerPawn = pawns[peer_id]
		if pawn.gripped_by != null and pawn.grip_left <= 0.3:
			_emit("release", {"id": peer_id})


func _on_contact(a: PlayerPawn, b: PlayerPawn, speed: float) -> void:
	if not _is_sim() or not _playing():
		return
	for pair: Array in [[a, b], [b, a]]:
		var holder: PlayerPawn = pair[0]
		var victim: PlayerPawn = pair[1]
		if holder.powerup == Powerup.Kind.SPIKES and holder.latched == null and holder.active() and holder.invuln_left <= 0.0 and victim.invuln_left <= 0.0 and victim.gripped_by == null and holder.grab_block_left <= 0.0 and victim.grab_block_left <= 0.0:

			_emit("grip", {"a": id_of(holder), "b": id_of(victim)})
			break
	_on_pawn_bumped(a, speed, b)


func _on_pawn_bumped(attacker: PlayerPawn, speed: float, victim: PlayerPawn) -> void:
	if speed < 2.0:
		return

	if attacker.ground_velocity().length() < victim.ground_velocity().length():
		var t := attacker
		attacker = victim
		victim = t
	var a := id_of(attacker)
	var b := id_of(victim)
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	var now := Time.get_ticks_msec()
	if now - int(_last_hits.get(key, -100000)) < HIT_DEDUP_MS:
		return
	_last_hits[key] = now
	var strength := clampf((speed - 2.0) / 8.0, 0.0, 1.0) * clampf(attacker.hit_multiplier(), 1.0, 2.0) / 2.0 + 0.2
	var pos := (victim.global_position + attacker.global_position) * 0.5 + Vector3.UP * 0.8
	_emit("hit", {"pos": pos, "s": clampf(strength, 0.0, 1.0), "a": a, "b": b})

func _process(delta: float) -> void:
	if not _loaded:
		return
	_follow_proxies()
	_update_music()
	_animate_bombs(delta)
	if camera == null:
		return

	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if (phase == Phase.PUSH or phase == Phase.SHRINK) and not _lite():
		_perf_frames += 1
		_perf_secs += real_delta
	_cam_focus = _cam_focus.lerp(_follow_point(), minf(1.0, delta * CAMERA_FOLLOW_RATE))
	var fit_target := _fit_dist(_cam_focus)
	_fit = fit_target if _fit < 0.0 else lerpf(_fit, fit_target, minf(1.0, real_delta * FIT_EASE))
	var dist := _camera_dist()

	camera.position = _cam_focus + _cam_dir * dist
	if _victor != null and is_instance_valid(_victor):
		# Swing down and orbit the winner while the results come in.
		_victory_t = minf(1.0, _victory_t + real_delta / 1.4)
		_victory_yaw += real_delta * VICTORY_ORBIT
		var e := smoothstep(0.0, 1.0, _victory_t)
		var elev := deg_to_rad(lerpf(CAMERA_ELEVATION_DEG, VICTORY_ELEVATION_DEG, e))
		var dir := Vector3(0, sin(elev), cos(elev)).rotated(Vector3.UP, _victory_yaw * e)
		var target := _victor.global_position
		target.y = maxf(target.y, 0.0) + 0.9
		var look := (_cam_focus + Vector3.UP * 0.9).lerp(target, e)
		camera.look_at_from_position(look + dir * lerpf(dist, minf(dist, VICTORY_DIST), e),
				look, Vector3.UP)
	if _trauma > 0.0:
		var shake := _trauma * _trauma * SHAKE_MAX
		camera.position += camera.global_basis.x * randf_range(-1.0, 1.0) * shake + camera.global_basis.y * randf_range(-1.0, 1.0) * shake

		_trauma = maxf(0.0, _trauma - real_delta * SHAKE_DECAY)
	if _weather != null:

		_weather.global_position = Vector3(_cam_focus.x, 0.0, _cam_focus.z) + _weather_offset
	if _sun != null:

		_sun.directional_shadow_max_distance = dist * 1.6 + 10.0


func net_report() -> String:
	var clock: Net.Clock = _host_clock
	if mode == Mode.HOST:
		clock = null
		for c: Net.Clock in _clocks.values():
			clock = c
	var out := ""
	for k: String in net_stats:
		out += " %s=%d" % [k, net_stats[k]]
	if clock != null:
		out += " delay=%dms jitter=%dms interval=%dms" % [clock.delay() * 1000.0,
				clock.jitter * 1000.0, clock.interval * 1000.0]
	return out


func _follow_proxies() -> void:
	for id: int in pawns:
		var pawn: PlayerPawn = pawns[id]
		if not pawn.remote_controlled:
			continue
		var clock: Net.Clock = _host_clock if mode == Mode.CLIENT else _clocks.get(id)
		if clock != null:
			pawn.follow_net(clock.render_time())

func _snap_camera() -> void:
	_cam_focus = _follow_point()
	_fit = _fit_dist(_cam_focus)
	camera.position = _cam_focus + _cam_dir * _camera_dist()

func _roster() -> Dictionary:
	if net != null and net.role != Net.Role.OFFLINE:
		return net.players

	return {
		1: Net._entry("You", local_char, false),
		-1: Net._entry("Rocky", Characters.random_of_class(PlayerPawn.WeightClass.HEAVY), true),
		-2: Net._entry("Zippy", Characters.random_of_class(PlayerPawn.WeightClass.LIGHT), true),
		-3: Net._entry("Bo", Characters.random_of_class(PlayerPawn.WeightClass.NORMAL), true),
	}

func _my_id() -> int:
	return net.my_id() if net != null and net.role != Net.Role.OFFLINE else 1

func _spawn_pawns() -> void:
	var roster := _roster()
	var ids := roster.keys()
	ids.sort()
	var spawns := arena.get_spawn_points(ids.size())
	for i in ids.size():
		var id: int = ids[i]
		var info: Dictionary = roster[id]
		var pawn := PlayerPawn.new()
		pawn.player_name = info["name"]
		pawn.character = info.get("char", "")
		pawn.weight_class = Characters.class_of(pawn.character) if Characters.valid(pawn.character) else info["class"]

		pawn.is_bot = info["bot"]
		pawn.lives = START_LIVES
		pawn.position = spawns[i]
		pawn.freeze = true
		pawn.remote_controlled = not _simulates(id)
		pawn.referee = _is_sim()
		if pawn.remote_controlled:
			pawn.push_net_state(0.0, spawns[i], Vector3.ZERO)
		else:

			pawn.shoved.connect(_on_pawn_shoved.bind(pawn))
			pawn.stomped.connect(_on_pawn_stomped.bind(pawn))
			pawn.broke_free.connect(_on_pawn_broke_free.bind(pawn))
			pawn.pushed.connect(_on_local_push.bind(pawn))
			if _is_sim():
				pawn.fell.connect(_on_pawn_fell)
		add_child(pawn)
		pawns[id] = pawn
		if _is_sim() and pawn.is_bot:
			var brain := BotBrain.new()
			brain.game = self
			pawn.add_child(brain)
	if pawns.has(_my_id()) and not _is_dedicated():
		local_pawn = pawns[_my_id()]
	_snap_camera()

func _build_ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.use_pressed.connect(_on_use_pressed)
	hud.menu_pressed.connect(open_menu)
	if local_pawn != null:
		controls = TouchControls.new()
		controls.pawn = local_pawn
		controls.camera = camera
		controls.arena = arena
		controls.blocker = hud.slot
		controls.push_committed.connect(_on_push_committed)
		controls.bomb_thrown.connect(_on_bomb_thrown)
		controls.jump_aimed.connect(_on_jump_aimed)
		controls.use_pressed.connect(_on_use_pressed)
		controls.editing_done.connect(func() -> void: open_menu(true))

		controls.process_mode = Node.PROCESS_MODE_ALWAYS
		var ui_layer := CanvasLayer.new()
		ui_layer.add_child(controls)
		add_child(ui_layer)
		hud.set_lives(local_pawn.lives)
	else:
		hud.set_lives(-1)
	_update_alive_count()


func _playing() -> bool:
	return phase == Phase.PUSH or phase == Phase.SHRINK


func _feed_local_input(_delta: float) -> void:
	if controls == null or local_pawn == null or auto_local:
		return
	local_pawn.move_input = controls.move_vector() if _playing() and local_pawn.alive else Vector2.ZERO


func _send_state(delta: float) -> void:
	_state_accum += delta
	if _state_accum < 1.0 / Net.STATE_HZ:
		return
	_state_accum = 0.0
	if local_pawn != null:
		net.request_state.rpc_id(1, _make_state(local_pawn))

func _on_push_committed(direction: Vector3) -> void:
	if not _playing() or local_pawn == null:
		return
	if local_pawn.try_push(direction):
		GameAudio.play("flick")


func _on_local_push(dir: Vector3, pawn: PlayerPawn) -> void:
	if mode == Mode.HOST:
		net.game_event.rpc("push", {"id": id_of(pawn), "dir": dir})
	elif mode == Mode.CLIENT:
		net.request_push.rpc_id(1, dir)


func _on_use_pressed() -> void:
	if local_pawn == null:
		return
	if local_pawn.can_use():
		if mode == Mode.CLIENT:
			net.request_use.rpc_id(1)
		else:
			apply_use(_my_id())
	elif local_pawn.can_cancel():
		if mode == Mode.CLIENT:
			net.request_cancel.rpc_id(1)
		else:
			apply_cancel(_my_id())


func apply_cancel(peer_id: int) -> void:
	if not _is_sim() or not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if pawn.can_cancel():
		_emit("cancel", {"id": peer_id})

func _on_bomb_thrown(target: Vector3) -> void:
	if not _playing():
		return
	if mode == Mode.CLIENT:
		net.request_bomb.rpc_id(1, target)
	else:
		apply_bomb(_my_id(), target)

func _on_jump_aimed(target: Vector3) -> void:
	if not _playing():
		return
	if mode == Mode.CLIENT:
		net.request_jump.rpc_id(1, target)
	else:
		apply_jump(_my_id(), target)


func bot_use(pawn: PlayerPawn) -> void:
	if mode == Mode.CLIENT:
		net.request_use.rpc_id(1)
	else:
		apply_use(id_of(pawn))

func bot_bomb(pawn: PlayerPawn, target: Vector3) -> void:
	if mode == Mode.CLIENT:
		net.request_bomb.rpc_id(1, target)
	else:
		apply_bomb(id_of(pawn), target)

func bot_jump(pawn: PlayerPawn, target: Vector3) -> void:
	if mode == Mode.CLIENT:
		net.request_jump.rpc_id(1, target)
	else:
		apply_jump(id_of(pawn), target)


func apply_jump(peer_id: int, target: Vector3) -> void:
	if not _is_sim() or not _playing() or not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if not pawn.can_jump():
		return
	var from := pawn.global_position
	var leap := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if not leap.is_finite() or leap.length_squared() < 0.0001:
		return
	var dist := clampf(leap.length(), Powerup.JUMP_MIN_RANGE, Powerup.JUMP_MAX_RANGE)
	var to := Vector3(from.x, 0.0, from.z) + leap.normalized() * dist
	var time := Powerup.jump_time(dist)
	_jump_ms[peer_id] = Time.get_ticks_msec() + int(time * 1000.0)
	_emit("jump", {"id": peer_id, "dir": leap.normalized(), "to": to, "t": time})


func apply_push(peer_id: int, direction: Vector3) -> void:
	if not _is_sim() or not _playing() or not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if not pawn.alive or not direction.is_finite():
		return
	pawn.cooldown_left = pawn.stats().cooldown
	_push_ms[peer_id] = Time.get_ticks_msec()
	pawn.start_push_pose(direction)
	net.game_event.rpc("push", {"id": peer_id, "dir": direction})


func apply_use(peer_id: int) -> void:
	if not _is_sim() or (phase != Phase.PUSH and phase != Phase.SHRINK):
		return
	if not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if pawn.can_use():
		_emit("use", {"id": peer_id, "kind": pawn.held})


func apply_bomb(peer_id: int, target: Vector3) -> void:
	if not _is_sim() or not _playing():
		return
	if not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if not pawn.alive or pawn.powerup != Powerup.Kind.BOMB:
		return
	var from := pawn.global_position
	var throw := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if not throw.is_finite() or throw.length_squared() < 0.0001:
		return
	var dist := clampf(throw.length(), Powerup.BOMB_MIN_RANGE, Powerup.BOMB_MAX_RANGE)
	var to := Vector3(from.x, 0.0, from.z) + throw.normalized() * dist
	var time := Powerup.bomb_flight_time(dist)
	_bombs_due.append([time, to])
	_emit("throw", {"id": peer_id, "from": from + Vector3.UP * (pawn.height() + 0.45),
			"to": to, "t": time})


func _tick_bombs(delta: float) -> void:
	for i in range(_bombs_due.size() - 1, -1, -1):
		_bombs_due[i][0] -= delta
		if _bombs_due[i][0] <= 0.0:
			var to: Vector3 = _bombs_due[i][1]
			_bombs_due.remove_at(i)
			if arena.contains(to):
				_emit("hole", {"pos": to, "r": Powerup.hole_radius()})


func _animate_bombs(delta: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var b: Dictionary = _flying[i]
		b["t"] += delta
		var u: float = b["t"] / b["time"]
		var node: Node3D = b["node"]
		var marker: Node3D = b["marker"]
		if u < 1.0:
			node.position = Powerup.bomb_arc(b["from"], b["to"], u)
			node.rotation.x += delta * 9.0
			var s := lerpf(2.2, 1.0, u)
			marker.scale = Vector3(s, 0.2, s)
			marker.visible = arena.contains(b["to"])
			continue
		if marker != null:
			marker.queue_free()
			b["marker"] = null
		if u < 1.6 and not arena.contains(b["to"]):

			node.position.y -= 16.0 * delta
			continue
		node.queue_free()
		_flying.remove_at(i)

func drop_player(peer_id: int) -> void:
	if pawns.has(peer_id) and pawns[peer_id].alive:
		var pawn: PlayerPawn = pawns[peer_id]
		pawn.alive = false
		pawn.lives = 0
		_emit("out", {"id": peer_id, "reason": "left"})
		_check_win()


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0
	match phase:
		Phase.COUNTDOWN:
			for p: PlayerPawn in pawns.values():
				p.freeze = true
				p.move_input = Vector2.ZERO
		Phase.PUSH:
			if _is_sim():
				for p: PlayerPawn in pawns.values():
					p.freeze = p.remote_controlled
				_plan_drops()
			_emit("announce", {"text": "PUSH 'EM OFF!"})
		Phase.SHRINK:
			_emit("announce", {"text": "THE MAP IS SHRINKING!", "hold": 2.5})
		Phase.OVER:
			for p: PlayerPawn in pawns.values():
				p.move_input = Vector2.ZERO
			var winner := _last_alive()
			var winner_name := "" if winner == null else winner.player_name
			_emit("over", {"winner": winner_name,
					"id": 0 if winner == null else id_of(winner)})


func _on_phase_synced(old_phase: Phase) -> void:
	if local_pawn == null or old_phase == phase:
		return
	match phase:
		Phase.LOADING, Phase.COUNTDOWN:
			local_pawn.freeze = true
			local_pawn.move_input = Vector2.ZERO
		Phase.PUSH, Phase.SHRINK:
			if local_pawn.alive and not local_pawn.in_air():
				local_pawn.freeze = false
		Phase.OVER:
			local_pawn.move_input = Vector2.ZERO


func _all_loaded() -> bool:
	if phase_time >= LOAD_TIMEOUT:
		return true
	for id: int in pawns:
		var pawn: PlayerPawn = pawns[id]
		if id > 1 and not pawn.is_bot and not net.ready_peers.has(id):
			return false
	return true

func _physics_process(delta: float) -> void:
	if not _loaded:
		return
	phase_time += delta
	_update_hud()
	_prune_holes()
	_crumble_edge(delta)
	_feed_local_input(delta)
	PlayerPawn.resolve_contacts(pawns.values(), _touching, _on_contact)
	_tick_holes()
	if mode == Mode.CLIENT:
		_send_state(delta)
		return
	_tick_bombs(delta)
	_check_proxy_falls()
	match phase:
		Phase.LOADING:
			if mode == Mode.SOLO or _all_loaded():
				_set_phase(Phase.COUNTDOWN)
		Phase.COUNTDOWN:
			if phase_time >= COUNTDOWN_SECS:
				_set_phase(Phase.PUSH)
		Phase.PUSH:
			_tick_drops(delta)
			_tick_pickups()
			if phase_time >= push_secs:
				_set_phase(Phase.SHRINK)
		Phase.SHRINK:
			arena.shrink_factor = 1.0 - phase_time * SHRINK_RATE
			if phase_time >= LEFTOVER_SECS and not _drops.is_empty():
				_emit("clear_drops", {})
			_tick_pickups()
			_check_win()
		Phase.OVER:
			if phase_time >= RESTART_DELAY and not _hold_finish:
				_finish()
	if mode == Mode.HOST:
		_snapshot_accum += delta
		if _snapshot_accum >= 1.0 / Net.SNAPSHOT_HZ:
			_snapshot_accum = 0.0
			net.send_snapshot(_make_snapshot())


func _check_proxy_falls() -> void:
	for pawn: PlayerPawn in pawns.values():
		if pawn.remote_controlled and pawn.alive and pawn.global_position.y < -4.0:
			pawn.alive = false
			pawn.detach()
			if pawn.gripped_by != null:
				pawn.gripped_by.detach()
			_on_pawn_fell(pawn)

func _update_hud() -> void:
	match phase:
		Phase.LOADING:

			hud.set_timer_text("WAITING FOR PLAYERS")
		Phase.COUNTDOWN:
			var n := maxi(int(ceil(COUNTDOWN_SECS - phase_time)), 1)
			if n != _last_countdown:
				_last_countdown = n
				GameAudio.play("tick")
			hud.set_timer_text(str(n))
		Phase.PUSH:
			var remaining := maxf(push_secs - phase_time, 0.0)
			hud.set_timer_text("%d:%02d" % [int(remaining / 60.0), int(remaining) % 60],
					remaining < 15.0)
		Phase.SHRINK:
			hud.set_timer_text("SUDDEN DEATH", true)
		Phase.OVER:
			hud.set_timer_text("")
	if local_pawn != null:
		hud.set_powerup(_powerup_text())
		var p := local_pawn
		var frac := 0.0
		if p.powerup >= 0:
			frac = p.powerup_left / float(Powerup.DURATION[p.powerup]) if Powerup.timed(p.powerup) else 1.0

		var playing := phase == Phase.PUSH or phase == Phase.SHRINK
		hud.set_slot(p.held, p.powerup, frac, p.can_use() and playing,
				p.can_cancel() and playing)

func _powerup_text() -> String:
	var p := local_pawn
	if p.in_air():
		return "JUMPING!"
	if p.gripped_by != null:
		return "STUCK ON SPIKES!" if p.grip_left > 0.0 else "STUCK — move or push to break free!"
	if p.held >= 0 and p.powerup < 0:
		return "%s ready · tap the button to use it" % Powerup.NAMES[p.held]
	var cancel := " · tap button to cancel" if p.can_cancel() else ""
	match p.powerup:
		Powerup.Kind.GLOVES:
			return "GLOVES · pushes hit ×%s · %ds%s" % [str(Powerup.GLOVES_HIT_MULT),
					ceili(p.powerup_left), cancel]
		Powerup.Kind.SPIKES:
			return "SPIKES · touch someone to grab them · %ds%s" % [ceili(p.powerup_left), cancel]
		Powerup.Kind.BOMB:
			return "BOMB · pull the THROW stick to aim, release to throw · %ds%s" % [
					ceili(p.powerup_left), cancel]
		Powerup.Kind.DASH:
			return "DASH · full speed, instant turns · %ds%s" % [ceili(p.powerup_left), cancel]
		Powerup.Kind.SHOES:
			if p.in_air():
				return "JUMPING!"
			return "JUMPER SHOES · pull the JUMP stick to aim, release to leap over anyone%s" % cancel

	return ""

## Credits whoever last hit `victim_id`, if recently enough, with the knockout.
func _credit_ko(victim_id: int) -> void:
	if not _last_attacker.has(victim_id):
		return
	var rec: Array = _last_attacker[victim_id]
	_last_attacker.erase(victim_id)
	var by: int = rec[0]
	if by == victim_id or not pawns.has(by) or not pawns.has(victim_id):
		return
	if Time.get_ticks_msec() - int(rec[1]) > KO_CREDIT_MS:
		return
	_kos[by] = int(_kos.get(by, 0)) + 1
	var mine: bool = local_pawn != null and pawns[by] == local_pawn
	hud.feed((pawns[by] as PlayerPawn).player_name, (pawns[victim_id] as PlayerPawn).player_name, mine)
	if mine:
		hud.ko_popup(_kos[by])
		GameAudio.play("go", -2.0, 1.7)
		add_shake(0.35)


func _my_place(winner_id: int) -> int:
	var me := _my_id()
	if me == winner_id:
		return 1
	var at := _out_order.find(me)
	return pawns.size() - at if at >= 0 else 0


func _begin_victory(winner_id: int, winner_name: String) -> void:
	if pawns.has(winner_id) and not _lite():
		_victor = pawns[winner_id]
		Fx.confetti(self, _victor.global_position + Vector3.UP * 1.2)
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func() -> void:
			if _victor != null and is_instance_valid(_victor):
				Fx.confetti(self, _victor.global_position + Vector3.UP * 1.6))
	if mode != Mode.HOST:
		Engine.time_scale = VICTORY_SLOWMO
		get_tree().create_timer(VICTORY_SLOWMO_SECS, true, false, true).timeout.connect(
				func() -> void: Engine.time_scale = 1.0)
	if local_pawn == null:
		return
	var payout := Progress.record_match({"place": _my_place(winner_id), "players": pawns.size(),
			"kos": int(_kos.get(_my_id(), 0)), "powerups": _powerups_used,
			"online": mode != Mode.SOLO})
	var args := OS.get_cmdline_user_args()
	var scripted := "--autotest" in args and not "--results" in args
	_hold_finish = mode == Mode.SOLO and not scripted
	var place := _my_place(winner_id)
	get_tree().create_timer(RESULTS_DELAY, true, false, true).timeout.connect(func() -> void:
		if not is_inside_tree() or _results != null:
			return
		_hide_menu()
		_results = ResultsScreen.new()
		_results.place = place
		_results.players = pawns.size()
		_results.winner_name = winner_name
		_results.payout = payout
		_results.interactive = _hold_finish
		_results.continued.connect(func() -> void: Ads.after_match(_finish))
		add_child(_results)
		if not args.is_empty():
			print("TEST_RESULTS place=%d coins=%d xp=%d wallet=%d hold=%s" % [place,
					payout["coins"], payout["xp"], Progress.coins, _hold_finish])
			if "--autocontinue" in args:
				get_tree().create_timer(1.0, true, false, true).timeout.connect(_results._on_continue))


func _finish() -> void:
	if net != null and net.role == Net.Role.HOST:
		net.end_match()
	elif mode == Mode.SOLO:
		match_finished.emit()

func _on_pawn_fell(pawn: PlayerPawn) -> void:
	var id := id_of(pawn)
	if not OS.get_cmdline_user_args().is_empty():

		var hit_age := 99.0
		for key: String in _last_hits:
			var ids := key.split(":")
			if int(ids[0]) == id or int(ids[1]) == id:
				hit_age = minf(hit_age, (Time.get_ticks_msec() - int(_last_hits[key])) / 1000.0)
		print("TEST_FALL t=%.1f phase=%s %s lives_before=%d last_hit=%.1fs ago" % [phase_time,
				Phase.keys()[phase], pawn.player_name, pawn.lives, hit_age])
	var respawns_allowed := phase == Phase.PUSH or phase == Phase.COUNTDOWN
	if respawns_allowed:
		pawn.lives -= 1
	else:
		pawn.lives = 0
	if pawn.lives > 0:
		_emit("fell", {"id": id, "lives": pawn.lives})
		get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn.bind(pawn))
	else:
		_emit("out", {"id": id, "reason": "fell"})
		_check_win()

func _respawn(pawn: PlayerPawn) -> void:
	if phase == Phase.OVER:
		return
	if phase == Phase.SHRINK:

		pawn.lives = 0
		_emit("out", {"id": id_of(pawn), "reason": "fell"})
		_check_win()
		return
	var pos := _safe_point(arena.inner_radius() * 0.5)
	var seq := (pawn.net_seq + 1) & 255
	pawn.respawn_at(pos, seq)
	_emit("respawn", {"id": id_of(pawn), "pos": pos, "lives": pawn.lives, "seq": seq})


func _safe_point(ring: float) -> Vector3:
	for attempt in 12:
		var a := randf() * TAU
		var d := sqrt(randf()) * ring
		var pos := Vector3(cos(a) * d, 1.2, sin(a) * d)
		if not _over_hole(pos, 1.0):
			return pos
	return Vector3(0.0, 1.2, 0.0)

func id_of(pawn: PlayerPawn) -> int:
	return pawns.find_key(pawn)

func _alive_count() -> int:
	var n := 0
	for p: PlayerPawn in pawns.values():
		if p.alive:
			n += 1
	return n

func _last_alive() -> PlayerPawn:
	for p: PlayerPawn in pawns.values():
		if p.alive:
			return p
	return null

func _update_alive_count() -> void:
	hud.set_alive(_alive_count(), pawns.size())

func _check_win() -> void:
	if phase != Phase.OVER and _alive_count() <= 1:
		_set_phase(Phase.OVER)


func _plan_drops() -> void:
	var kinds := DROP_SET.duplicate()
	kinds.shuffle()
	var slice := (DROP_WINDOW.y - DROP_WINDOW.x) / kinds.size()
	_drop_schedule.clear()
	for i in kinds.size():
		var t := DROP_WINDOW.x + slice * (i + randf_range(0.1, 0.9))
		_drop_schedule.append([t, kinds[i]])

func _tick_drops(_delta: float) -> void:
	while not _drop_schedule.is_empty() and phase_time >= _drop_schedule[0][0]:
		var entry: Array = _drop_schedule.pop_front()
		var pos := _drop_point()
		_emit("drop", {"pid": _next_drop_id, "kind": entry[1], "pos": pos})
		_next_drop_id += 1

func _tick_pickups() -> void:
	for pid: int in _drops.keys():
		var drop: Powerup = _drops[pid]
		if not drop.landed:
			continue
		for id: int in pawns:
			var pawn: PlayerPawn = pawns[id]
			if not pawn.can_collect():
				continue
			var d := pawn.global_position - drop.global_position
			d.y = 0.0
			if d.length() <= pawn.radius() + Powerup.PICKUP_REACH:
				_emit("pickup", {"pid": pid, "id": id, "kind": drop.kind})
				break


func _drop_point() -> Vector3:
	for attempt in 12:
		var pos := arena.random_point(DROP_MARGIN)
		if not _over_hole(pos, 1.0):
			return pos
	return arena.random_point(DROP_MARGIN)


func _tick_holes() -> void:
	if _holes.is_empty():
		return
	for pawn: PlayerPawn in pawns.values():
		if not pawn.remote_controlled and pawn.alive and pawn.has_floor_collision() and pawn.global_position.y < 1.0 and _over_hole(pawn.global_position, 0.0):

			pawn.set_floor_collision(false)

func _over_hole(pos: Vector3, margin: float) -> bool:
	for hole: Dictionary in _holes:
		var d: Vector3 = pos - hole["pos"]
		d.y = 0.0
		if d.length() < hole["r"] + margin:
			return true
	return false


func _prune_holes() -> void:
	if _holes.is_empty():
		return
	for i in range(_holes.size() - 1, -1, -1):
		var hole: Dictionary = _holes[i]
		if not arena.contains(hole["pos"]):
			(hole["node"] as Node3D).queue_free()
			_holes.remove_at(i)
			arena.set_holes(_holes)

func _remove_drop(pid: int) -> void:
	if _drops.has(pid):
		_drops[pid].queue_free()
		_drops.erase(pid)


func _emit(kind: String, payload: Dictionary) -> void:
	if net != null and net.role == Net.Role.HOST:
		net.send_event(kind, payload)
	else:
		apply_event(kind, payload)

func apply_event(kind: String, payload: Dictionary) -> void:
	if not _loaded:
		_pending_events.append([kind, payload])
		return
	if _log_events:
		print("TEST_EVENT t=%.2f %s %s" % [phase_time, kind, payload])
	match kind:
		"push":

			if pawns.has(payload["id"]) and pawns[payload["id"]].remote_controlled:
				(pawns[payload["id"]] as PlayerPawn).start_push_pose(payload["dir"])
		"jump":

			if pawns.has(payload["id"]):
				var jumper: PlayerPawn = pawns[payload["id"]]
				jumper.clear_powerup()
				if jumper.remote_controlled:
					jumper.start_jump_pose(payload["dir"], payload["t"])
				else:
					jumper.start_jump(payload["to"], payload["t"])
		"knock":

			if not pawns.has(payload["id"]):
				return
			var victim: PlayerPawn = pawns[payload["id"]]
			if payload.has("by"):
				_last_attacker[payload["id"]] = [payload["by"], Time.get_ticks_msec()]
			if payload.has("d"):
				if victim.gripped_by != null:
					victim.gripped_by.detach()
				victim.detach()
				victim.grab_block_left = Powerup.STOMP_GRAB_BLOCK
				victim.ghost_left = PlayerPawn.stomp_slide_time()
				if pawns.has(payload.get("by", 0)):
					(pawns[payload["by"]] as PlayerPawn).ghost_left = PlayerPawn.stomp_slide_time()
				if not victim.remote_controlled:
					victim.throw_back(payload["dir"], payload["d"])
			elif not victim.remote_controlled:
				victim.take_shove(payload["v"])
			if not victim.remote_controlled:
				net_stats["knocks_taken"] += 1
		"grip":
			if pawns.has(payload["a"]) and pawns.has(payload["b"]):
				(pawns[payload["a"]] as PlayerPawn).latch(pawns[payload["b"]])
		"release":
			if pawns.has(payload["id"]):
				var freed: PlayerPawn = pawns[payload["id"]]
				if freed.gripped_by != null:
					freed.gripped_by.detach()
		"throw":

			if pawns.has(payload["id"]):
				(pawns[payload["id"]] as PlayerPawn).clear_powerup()
			var bomb := Powerup.build_model(Powerup.Kind.BOMB)
			bomb.scale = Vector3.ONE * 0.8
			bomb.position = payload["from"]
			add_child(bomb)
			var marker := Powerup.landing_marker(Powerup.hole_radius())
			marker.position = Vector3(payload["to"].x, 0.04, payload["to"].z)
			add_child(marker)
			_flying.append({"node": bomb, "marker": marker, "from": payload["from"],
					"to": payload["to"], "t": 0.0, "time": payload["t"]})
			GameAudio.play("flick", 0.0, 0.7)
		"announce":
			hud.announce(payload["text"], payload.get("hold", 1.6))
			GameAudio.play("go")
		"fell":
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.alive = false
			pawn.lives = payload["lives"]
			hud.announce(pawn.player_name + " fell!", 1.0)
			GameAudio.play("fall")
			Fx.fall_splash(self, pawn.global_position)
			_credit_ko(payload["id"])
			if pawn == local_pawn:
				hud.set_lives(pawn.lives)
		"respawn":
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.lives = payload["lives"]
			GameAudio.play("tick", -6.0, 1.3)
			if mode == Mode.CLIENT:
				pawn.respawn_at(payload["pos"], payload.get("seq", -1))
			if pawn == local_pawn:
				hud.set_lives(pawn.lives)
		"out":
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.alive = false
			pawn.lives = 0
			pawn.visible = false
			pawn.freeze = true
			pawn.clear_powerup()
			pawn.held = -1
			var why: String = payload.get("reason", "fell")
			hud.announce(pawn.player_name + (" left!" if why == "left" else " is OUT!"), 1.4)
			if not _out_order.has(payload["id"]):
				_out_order.append(payload["id"])
			if why != "left":
				GameAudio.play("fall", 0.0, 0.8)
				_credit_ko(payload["id"])
			if pawn == local_pawn:
				hud.set_lives(0)
		"over":
			phase = Phase.OVER
			phase_time = 0.0
			var winner: String = payload["winner"]
			var local_won: bool = local_pawn != null and pawns.get(payload.get("id", 0)) == local_pawn
			hud.announce("DRAW!" if winner.is_empty() else ("YOU WIN!" if local_won
					else winner + " WINS!"), RESULTS_DELAY)
			if controls != null:
				controls.visible = false
			hud.slot.visible = false
			GameAudio.play("win")
			var winner_id: int = payload.get("id", 0)
			if pawns.has(winner_id):
				(pawns[winner_id] as PlayerPawn).cheer()
			_begin_victory(winner_id, winner)
		"drop":
			var drop := Powerup.new()
			drop.kind = payload["kind"]
			drop.position = payload["pos"]
			add_child(drop)
			_drops[payload["pid"]] = drop
		"pickup":

			if _drops.has(payload["pid"]):
				var d: Powerup = _drops[payload["pid"]]
				Fx.sparkle(self, d.global_position, Powerup.COLORS[d.kind]
						if d.kind != Powerup.Kind.BOMB else Color(1.0, 0.6, 0.2))
			_remove_drop(payload["pid"])
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.held = payload["kind"]
			if pawn == local_pawn:
				GameAudio.play("tick", 0.0, 1.6)
		"use":
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.held = -1
			pawn.give_powerup(payload["kind"])
			GameAudio.play("go", -4.0, 1.3)
			if pawn == local_pawn:
				_powerups_used += 1
		"cancel":
			var pawn: PlayerPawn = pawns[payload["id"]]
			pawn.clear_powerup()
			if pawn == local_pawn:
				GameAudio.play("tick", -2.0, 0.7)
		"clear_drops":
			for pid: int in _drops.keys():
				_remove_drop(pid)
		"hole":
			var node := Powerup.make_hole(payload["r"], arena.wall_color())
			node.position = Vector3(payload["pos"].x, 0.0, payload["pos"].z)
			add_child(node)
			_holes.append({"pos": payload["pos"], "r": payload["r"], "node": node})
			arena.set_holes(_holes)
			hud.announce("KABOOM!", 0.8)
			GameAudio.play("bump", 3.0, 0.55)
			Fx.explosion(self, payload["pos"])
			_shake_at(payload["pos"], 0.9)
		"hit":
			var pos: Vector3 = payload["pos"]
			var s: float = payload["s"]
			Fx.hit(self, pos, s)
			if s >= 0.35:
				Fx.shockwave(self, pos, s)
			_last_attacker[payload["b"]] = [payload["a"], Time.get_ticks_msec()]
			if pawns.has(payload["b"]) and pawns.has(payload["a"]):
				(pawns[payload["b"]] as PlayerPawn).start_hit_pose(
						(pawns[payload["a"]] as PlayerPawn).global_position)

			var ours: bool = (pawns.has(payload["a"]) and not pawns[payload["a"]].remote_controlled) or (pawns.has(payload["b"]) and not pawns[payload["b"]].remote_controlled)

			if mode == Mode.CLIENT and not ours:
				GameAudio.play("bump", linear_to_db(clampf(0.3 + s, 0.3, 1.0)), randf_range(0.9, 1.1))
			var mine: bool = local_pawn != null and (id_of(local_pawn) == payload["a"]
					or id_of(local_pawn) == payload["b"])
			if mine:
				add_shake(0.25 + 0.45 * s)
				if s >= HIT_STOP_MIN:
					_hit_stop()
			else:
				_shake_at(pos, 0.12 * s)
	_update_alive_count()


func _make_snapshot() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(SNAP_HEADER + SNAP_PER_PAWN * pawns.size())
	b.encode_u8(0, phase)
	b.encode_float(1, phase_time)
	b.encode_float(5, arena.shrink_factor)
	b.encode_u8(9, pawns.size())
	b.encode_u32(10, Time.get_ticks_msec() & 4294967295)
	var now := Net.Clock.now()
	var o := SNAP_HEADER
	for id: int in pawns:
		var p: PlayerPawn = pawns[id]
		var pos := p.global_position
		var vel := p.linear_velocity
		if p.remote_controlled:
			vel = p.net_vel
			if _latest.has(id):
				var st: Array = _latest[id]
				vel = st[2]
				pos = (st[1] as Vector3) + vel * clampf(now - float(st[0]), 0.0, 0.1)
		b.encode_s32(o, id)
		b.encode_u8(o + 4, p.net_seq)
		b.encode_float(o + 5, pos.x)
		b.encode_float(o + 9, pos.y)
		b.encode_float(o + 13, pos.z)
		b.encode_half(o + 17, vel.x)
		b.encode_half(o + 19, vel.y)
		b.encode_half(o + 21, vel.z)
		b.encode_u8(o + 23, (p.powerup + 1) | ((p.held + 1) << 3) | ((1 if p.alive else 0) << 6))
		b.encode_u8(o + 24, clampi(roundi(p.cooldown_left * 100.0), 0, 255))
		b.encode_u8(o + 25, clampi(ceili(p.powerup_left * 10.0), 0, 255))
		o += SNAP_PER_PAWN
	return b

func apply_snapshot(b: PackedByteArray) -> void:
	if not _loaded or b.size() < SNAP_HEADER:
		return
	var n := b.decode_u8(9)
	if b.size() < SNAP_HEADER + n * SNAP_PER_PAWN:
		return
	var host_t := b.decode_u32(10) / 1000.0
	_host_clock.sample(host_t)
	net_stats["snaps"] += 1
	var old_phase := phase
	phase = b.decode_u8(0) as Phase
	phase_time = b.decode_float(1)
	arena.shrink_factor = b.decode_float(5)
	_on_phase_synced(old_phase)
	for i in n:
		var o := SNAP_HEADER + i * SNAP_PER_PAWN
		var id := b.decode_s32(o)
		if not pawns.has(id):
			continue
		var pawn: PlayerPawn = pawns[id]
		var flags := b.decode_u8(o + 23)
		pawn.sync_powerup((flags & 7) - 1, b.decode_u8(o + 25) / 10.0)
		pawn.held = ((flags >> 3) & 7) - 1
		if not pawn.remote_controlled:
			continue
		pawn.cooldown_left = b.decode_u8(o + 24) / 100.0
		var seq := b.decode_u8(o + 4)
		var pos := Vector3(b.decode_float(o + 5), b.decode_float(o + 9), b.decode_float(o + 13))
		if seq != pawn.net_seq:
			if not PlayerPawn.seq_newer(seq, pawn.net_seq):
				continue
			pawn.net_seq = seq
			pawn.clear_net()
			pawn.global_position = pos
		pawn.push_net_state(host_t, pos,
				Vector3(b.decode_half(o + 17), b.decode_half(o + 19), b.decode_half(o + 21)))
		if (flags & 64) != 0 and not pawn.alive:
			pawn.alive = true
		if pawn.alive:
			pawn.visible = true


func _make_state(p: PlayerPawn) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(STATE_SIZE)
	b.encode_u32(0, Time.get_ticks_msec() & 4294967295)
	b.encode_u8(4, p.net_seq)
	var pos := p.global_position
	var vel := p.linear_velocity
	b.encode_float(5, pos.x)
	b.encode_float(9, pos.y)
	b.encode_float(13, pos.z)
	b.encode_half(17, vel.x)
	b.encode_half(19, vel.y)
	b.encode_half(21, vel.z)
	b.encode_u8(23, 0)
	return b


func apply_client_state(peer_id: int, b: PackedByteArray) -> void:
	if not _loaded or b.size() < STATE_SIZE or not pawns.has(peer_id):
		return
	var pawn: PlayerPawn = pawns[peer_id]
	if not pawn.remote_controlled or b.decode_u8(4) != pawn.net_seq:
		return
	var t := b.decode_u32(0) / 1000.0
	if not _clocks.has(peer_id):
		_clocks[peer_id] = Net.Clock.new()
	var clock: Net.Clock = _clocks[peer_id]
	clock.sample(t)
	net_stats["states"] += 1
	var pos := Vector3(b.decode_float(5), b.decode_float(9), b.decode_float(13))
	var vel := Vector3(b.decode_half(17), b.decode_half(19), b.decode_half(21))
	if not pos.is_finite() or not vel.is_finite():
		return
	pawn.push_net_state(t, pos, vel)
	_latest[peer_id] = [clock.to_local(t), pos, vel]
