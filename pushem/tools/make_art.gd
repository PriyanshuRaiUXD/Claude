extends SceneTree


const NINJA := "female_ninja"


const BG_INNER := Color(0.05, 0.47, 0.55)
const BG_OUTER := Color(0.01, 0.12, 0.17)
const TITLE := Color(1.0, 0.84, 0.04)
const TITLE_SHADOW := Color(0.85, 0.12, 0.2)
const OUTLINE := Color(0.05, 0.03, 0.1)

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await _render("icon.png", Vector2i(1024, 1024), _icon_layout, false)
	await _render("icon_foreground.png", Vector2i(432, 432), _foreground_layout, true)
	await _render("icon_background.png", Vector2i(432, 432), func(_v: SubViewport) -> void: pass,
			false, true)
	await _render("splash.png", Vector2i(1920, 1080), _splash_layout, false)
	print("ART_DONE")
	quit()


func _render(file: String, size: Vector2i, layout: Callable, transparent: bool,
		bg_only := false) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_8X
	vp.msaa_2d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	if not transparent:
		var bg_layer := CanvasLayer.new()
		bg_layer.layer = -1
		vp.add_child(bg_layer)

		bg_layer.add_child(_background(size, Vector2(0.5, 0.5) if file == "splash.png"
				else Vector2(0.62, 0.55)))

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS if not transparent else Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.7, 1.0)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	if not bg_only:
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-35, -40, 0)
		key.light_energy = 1.25
		key.light_color = Color(1.0, 0.95, 0.88)
		vp.add_child(key)

		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-15, 150, 0)
		rim.light_energy = 1.6
		rim.light_color = Color(1.0, 0.8, 0.3)
		vp.add_child(rim)
		vp.add_child(_ninja(62.0 if file == "splash.png" else -62.0))
		layout.call(vp)

	for i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://" + file)
	img.save_png(path)
	print("ART saved %s %s" % [file, size])
	vp.queue_free()

func _background(size: Vector2i, center: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, BG_INNER)
	g.set_color(1, BG_OUTER)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = center + Vector2(0.63, 0.55)
	tex.width = size.x
	tex.height = size.y
	var rect := TextureRect.new()
	rect.texture = tex
	rect.size = Vector2(size)
	return rect


func _ninja(yaw: float) -> Node3D:
	var pivot := Node3D.new()
	var model := Characters.instantiate(NINJA, true)
	if model == null:
		push_error("make_art: %s failed to load" % NINJA)
		return pivot
	var ap := Characters.animation_player(model)
	if ap != null:
		ap.stop()
	for part: String in PlayerPawn.POSE_KICK:
		var node := model.find_child(part, true, false) as Node3D
		if node != null:
			node.quaternion = Quaternion.from_euler(PlayerPawn.POSE_KICK[part])
	pivot.add_child(model)
	pivot.rotation_degrees = Vector3(0, yaw, 0)
	pivot.position.y = PlayerPawn.KICK_HOP * 0.6
	return pivot

func _camera(vp: SubViewport, eye: Vector3, target: Vector3, fov: float, shift := Vector2.ZERO) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.h_offset = shift.x
	cam.v_offset = shift.y
	vp.add_child(cam)
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true

func _title(vp: SubViewport, text: String, font_size: int, pos: Vector2, width: float,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	vp.add_child(layer)
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 1.1

	for pass_i in 2:
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = align
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", TITLE_SHADOW if pass_i == 0 else TITLE)
		l.add_theme_color_override("font_outline_color", OUTLINE)
		l.add_theme_constant_override("outline_size", int(font_size * 0.14))
		var drop := Vector2(font_size, font_size) * 0.045 if pass_i == 0 else Vector2.ZERO
		l.position = pos + drop
		l.size = Vector2(width, font_size * 1.3)
		layer.add_child(l)


func _icon_layout(vp: SubViewport) -> void:
	var s := float(vp.size.x)
	_camera(vp, Vector3(0.0, 0.75, 3.1), Vector3(0.0, 0.62, 0.0), 34.0, Vector2(-0.3, 0.22))
	_title(vp, "PUSH'", int(s * 0.27), Vector2(0, s * 0.02), s)
	_title(vp, "EM", int(s * 0.34), Vector2(s * 0.04, s * 0.56), s * 0.5)


func _foreground_layout(vp: SubViewport) -> void:
	var s := float(vp.size.x)
	var inset := s * 0.19
	var inner := s - 2.0 * inset
	_camera(vp, Vector3(0.0, 0.75, 4.6), Vector3(0.0, 0.62, 0.0), 34.0, Vector2(-0.3, 0.28))
	_title(vp, "PUSH'", int(inner * 0.27), Vector2(inset, inset + inner * 0.0), inner)
	_title(vp, "EM", int(inner * 0.34), Vector2(inset + inner * 0.03, inset + inner * 0.55), inner * 0.5)


func _splash_layout(vp: SubViewport) -> void:
	var w := float(vp.size.x)
	var h := float(vp.size.y)
	_camera(vp, Vector3(0.0, 0.75, 3.3), Vector3(0.0, 0.62, 0.0), 32.0, Vector2(0.6, 0.0))
	_title(vp, "PUSH'", int(h * 0.3), Vector2(w * 0.42, h * 0.12), w * 0.55)
	_title(vp, "EM", int(h * 0.36), Vector2(w * 0.42, h * 0.46), w * 0.55)
