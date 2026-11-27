extends SceneTree


const SIZE := 256
const OUT_DIR := "res://assets/portraits/"

func _initialize() -> void:
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	for id: String in Characters.LIST:
		await _render(id)
	print("PORTRAITS_DONE")
	quit()

func _render(id: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.95)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 160, 0)
	rim.light_energy = 1.2
	rim.light_color = Color(1.0, 0.9, 0.7)
	vp.add_child(rim)

	var model := Characters.instantiate(id, true)
	var h: float = PlayerPawn.STATS[Characters.class_of(id)]["height"]
	if model != null:
		var pivot := Node3D.new()
		pivot.rotation_degrees.y = -22.0
		pivot.add_child(model)
		vp.add_child(pivot)
		var ap := Characters.animation_player(model)
		if ap != null and ap.has_animation("Idle"):
			ap.play("Idle")
			ap.advance(0.4)
			ap.pause()

	var cam := Camera3D.new()
	cam.fov = 30.0
	var target := Vector3(0.0, h * 0.8, 0.0)
	vp.add_child(cam)
	cam.look_at_from_position(target + Vector3(0.0, h * 0.06, h * 1.05), target, Vector3.UP)
	cam.current = true

	for i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + id + ".png"))
	print("PORTRAIT %s" % id)
	vp.queue_free()
