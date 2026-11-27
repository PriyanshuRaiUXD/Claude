class_name CharacterPreview
extends SubViewportContainer


var character := Characters.DEFAULT:
	set(value):
		character = value
		if _pivot != null:
			_load_model()

var spin_speed := 0.6

var sway := false
var _t := 0.0

var _viewport: SubViewport
var _pivot: Node3D

func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)
	# Cool rim light from behind so the silhouette pops off any backdrop.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 155, 0)
	rim.light_color = Color(0.6, 0.8, 1.0)
	rim.light_energy = 1.3
	rim.light_specular = 1.5
	_viewport.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 60, 0)
	fill.light_color = Color(1.0, 0.86, 0.7)
	fill.light_energy = 0.35
	_viewport.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = 30
	camera.position = Vector3(0, 1.1, 3.9)
	camera.look_at_from_position(camera.position, Vector3(0, 0.92, 0), Vector3.UP)
	_viewport.add_child(camera)

	_pivot = Node3D.new()
	_pivot.rotation.y = randf_range(-0.5, 0.5)
	_viewport.add_child(_pivot)
	_load_model()

func _load_model() -> void:
	for child in _pivot.get_children():
		child.queue_free()
	var model := Characters.instantiate(character)
	if model != null:
		_pivot.add_child(model)

func _process(delta: float) -> void:
	if _pivot == null:
		return
	if sway:
		_t += delta
		_pivot.rotation.y = sin(_t * 0.7) * 0.4
	else:
		_pivot.rotation.y = wrapf(_pivot.rotation.y + delta * spin_speed, -PI, PI)
