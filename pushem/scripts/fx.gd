class_name Fx
extends RefCounted


static var world: int = WorldTheme.Kind.WINDY

static var _dot: Texture2D
static var _mats := {}

static func _burst_scale() -> float:
	return [0.5, 1.0, 1.25][Settings.effects]


static func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.85))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_dot = tex
	return _dot


static func _material(additive: bool, glow: float) -> StandardMaterial3D:
	var key := "%s_%s" % [additive, glow]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = _dot_texture()
		m.albedo_color = Color(glow, glow, glow, 1.0)
		m.disable_receive_shadows = true
		_mats[key] = m
	return _mats[key]

static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	return g

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	return c


static func _emitter(spec: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, int(spec.get("amount", 8)))
	p.lifetime = spec.get("life", 0.6)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * spec.get("size", 0.3)
	quad.material = _material(spec.get("additive", false), spec.get("glow", 1.0))
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = spec.get("dir", Vector3.UP)
	p.spread = spec.get("spread", 180.0)
	p.flatness = spec.get("flat", 0.0)
	p.initial_velocity_min = spec.get("vmin", 1.0)
	p.initial_velocity_max = spec.get("vmax", 3.0)
	p.gravity = spec.get("gravity", Vector3.ZERO)
	p.damping_min = spec.get("damping", 0.0)
	p.damping_max = spec.get("damping", 0.0)
	p.explosiveness = spec.get("explosive", 1.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _curve(spec.get("grow", [Vector2(0, 1), Vector2(1, 1)]))
	p.color_ramp = _ramp(spec.get("colors", [Color.WHITE, Color(1, 1, 1, 0)]))
	var r: float = spec.get("radius", 0.0)
	if r > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = r
	return p

static func _burst(parent: Node, pos: Vector3, spec: Dictionary) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var s := spec.duplicate()
	s["amount"] = float(spec.get("amount", 8)) * _burst_scale()
	var p := _emitter(s)
	p.one_shot = true
	_launch(parent, p, pos)


static func _launch(parent: Node, p: CPUParticles3D, pos: Vector3) -> void:
	p.emitting = false
	p.position = (parent as Node3D).to_local(pos) if parent is Node3D else pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _dust() -> Array:
	match world:
		WorldTheme.Kind.LAVA:
			return [Color(0.28, 0.2, 0.17, 0.7), Color(0.15, 0.1, 0.08, 0.0)]
		WorldTheme.Kind.SNOW:
			return [Color(1.0, 1.0, 1.0, 0.85), Color(0.9, 0.95, 1.0, 0.0)]
	return [Color(0.58, 0.47, 0.33, 0.7), Color(0.5, 0.42, 0.3, 0.0)]


static func dash_dust(parent: Node, pos: Vector3, heading: Vector3) -> void:
	var back := -heading
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.001 else Vector3.BACK
	var dust := _dust()
	_burst(parent, pos + Vector3.UP * 0.15, {
		"amount": 9, "life": 0.55, "size": 0.45,
		"dir": (back + Vector3.UP * 0.35).normalized(), "spread": 35.0,
		"vmin": 1.5, "vmax": 3.5, "damping": 4.0, "gravity": Vector3(0, 0.6, 0),
		"grow": [Vector2(0, 0.4), Vector2(1, 1.4)], "colors": dust, "radius": 0.2,
	})
	if world == WorldTheme.Kind.LAVA:
		_burst(parent, pos + Vector3.UP * 0.2, {
			"amount": 5, "life": 0.5, "size": 0.1, "additive": true, "glow": 2.0,
			"dir": (back + Vector3.UP).normalized(), "spread": 40.0,
			"vmin": 2.0, "vmax": 4.0, "gravity": Vector3(0, -5, 0),
			"colors": [Color(1, 0.6, 0.2, 1), Color(1, 0.2, 0.0, 0)],
		})


static func hit(parent: Node, pos: Vector3, strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	_burst(parent, pos, {
		"amount": 8 + 14 * s, "life": 0.4, "size": 0.12, "additive": true, "glow": 2.2,
		"spread": 180.0, "vmin": 3.0, "vmax": 6.0 + 5.0 * s, "gravity": Vector3(0, -9, 0),
		"damping": 2.0,
		"colors": [Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0)],
	})
	_burst(parent, pos, {
		"amount": 1, "life": 0.16, "size": 0.9 + 1.1 * s, "additive": true, "glow": 2.0,
		"spread": 0.0, "vmin": 0.0, "vmax": 0.0,
		"grow": [Vector2(0, 0.3), Vector2(1, 1.3)],
		"colors": [Color(1, 0.95, 0.8, 0.9), Color(1, 0.8, 0.5, 0)],
	})

static func explosion(parent: Node, pos: Vector3) -> void:
	var p := pos + Vector3.UP * 0.3

	_burst(parent, p, {
		"amount": 18, "life": 0.7, "size": 1.3, "additive": true, "glow": 2.4,
		"spread": 180.0, "vmin": 1.5, "vmax": 5.0, "damping": 3.0,
		"gravity": Vector3(0, 2.5, 0), "radius": 0.4,
		"grow": [Vector2(0, 0.5), Vector2(0.3, 1.2), Vector2(1, 1.6)],
		"colors": [Color(1, 0.9, 0.55, 1), Color(1, 0.45, 0.08, 0.9), Color(0.4, 0.1, 0.02, 0)],
	})

	var chunk: Color
	match world:
		WorldTheme.Kind.LAVA:
			chunk = Color(0.12, 0.08, 0.06)
		WorldTheme.Kind.SNOW:
			chunk = Color(0.92, 0.96, 1.0)
		_:
			chunk = Color(0.42, 0.32, 0.22)
	_burst(parent, p, {
		"amount": 16, "life": 1.1, "size": 0.22, "dir": Vector3.UP, "spread": 55.0,
		"vmin": 6.0, "vmax": 11.0, "gravity": Vector3(0, -20, 0),
		"colors": [Color(chunk, 1.0), Color(chunk, 1.0), Color(chunk, 0.0)],
	})

	_burst(parent, p + Vector3.UP * 0.5, {
		"amount": 10, "life": 1.8, "size": 1.8, "spread": 180.0, "vmin": 0.5, "vmax": 1.6,
		"damping": 1.0, "gravity": Vector3(0, 1.2, 0), "radius": 0.6, "explosive": 0.8,
		"grow": [Vector2(0, 0.4), Vector2(1, 1.5)],
		"colors": [Color(0.25, 0.22, 0.2, 0.0), Color(0.25, 0.22, 0.2, 0.55),
				Color(0.35, 0.33, 0.32, 0.0)],
	})

static func land_puff(parent: Node, pos: Vector3) -> void:
	_burst(parent, pos + Vector3.UP * 0.1, {
		"amount": 10, "life": 0.45, "size": 0.3, "dir": Vector3.RIGHT, "spread": 180.0,
		"flat": 1.0, "vmin": 2.0, "vmax": 3.0, "damping": 5.0,
		"grow": [Vector2(0, 0.5), Vector2(1, 1.3)], "colors": _dust(),
	})

static func sparkle(parent: Node, pos: Vector3, color: Color) -> void:
	var c := color.lightened(0.3)
	_burst(parent, pos + Vector3.UP * 0.4, {
		"amount": 14, "life": 0.6, "size": 0.14, "additive": true, "glow": 2.0,
		"dir": Vector3.UP, "spread": 70.0, "vmin": 1.0, "vmax": 3.0, "damping": 1.5,
		"colors": [Color(c, 1.0), Color(1, 1, 1, 0.8), Color(c, 0.0)],
	})


static func crumble(parent: Node, pos: Vector3, outward: Vector3, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.amount = maxi(1, int(4 * _burst_scale()))
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.9
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.35, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	box.material = mat
	p.mesh = box
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = (outward + Vector3.DOWN * 0.3).normalized()
	p.spread = 30.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -14, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	_launch(parent, p, pos)
	var dust := _dust()
	_burst(parent, pos, {
		"amount": 3, "life": 0.7, "size": 0.7, "dir": outward, "spread": 40.0,
		"vmin": 0.3, "vmax": 1.0, "gravity": Vector3(0, -1.5, 0),
		"grow": [Vector2(0, 0.5), Vector2(1, 1.4)], "colors": dust,
	})


static func ambient(kind: int) -> CPUParticles3D:
	if Settings.effects == 0:
		return null
	var more := Settings.effects == 2
	var p: CPUParticles3D
	match kind:
		WorldTheme.Kind.LAVA:

			p = _emitter({
				"amount": 110 if more else 60, "life": 5.0, "size": 0.09,
				"additive": true, "glow": 2.2, "dir": Vector3.UP, "spread": 25.0,
				"vmin": 0.6, "vmax": 1.6, "explosive": 0.0,
				"colors": [Color(1, 0.5, 0.1, 0), Color(1, 0.55, 0.15, 1),
						Color(1, 0.3, 0.05, 0.8), Color(0.6, 0.1, 0.0, 0)],
			})
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(22, 2, 22)
			p.position = Vector3(0, 1.0, 0)
		WorldTheme.Kind.SNOW:

			p = _emitter({
				"amount": 320 if more else 160, "life": 9.0, "size": 0.1,
				"dir": Vector3(0.3, -1.0, 0.1).normalized(), "spread": 10.0,
				"vmin": 1.6, "vmax": 2.6, "explosive": 0.0,
				"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.9),
						Color(1, 1, 1, 0)],
			})
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(26, 1, 26)
			p.position = Vector3(0, 14.0, 0)
		_:

			p = _emitter({
				"amount": 80 if more else 40, "life": 4.0, "size": 0.13,
				"dir": Vector3(1.0, 0.1, 0.25).normalized(), "spread": 15.0,
				"vmin": 3.0, "vmax": 6.0, "explosive": 0.0,
				"colors": [Color(0.4, 0.55, 0.2, 0), Color(0.4, 0.55, 0.2, 1),
						Color(0.55, 0.42, 0.25, 1), Color(0.55, 0.42, 0.25, 0)],
			})
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(26, 3, 26)
			p.position = Vector3(-8.0, 2.5, 0)
			p.angular_velocity_min = -180.0
			p.angular_velocity_max = 180.0
	p.local_coords = false
	p.preprocess = p.lifetime
	p.emitting = true
	return p


## Flat expanding ring on the ground — sells the weight of a hit.
static func shockwave(parent: Node, pos: Vector3, strength: float, color := Color(1, 0.95, 0.8)) -> void:
	if parent == null or not parent.is_inside_tree() or Settings.effects == 0:
		return
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 4
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.85)
	mat.disable_receive_shadows = true
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.3, 0.12, 0.3)
	parent.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.08, pos.z)
	var reach := 1.4 + 2.6 * clampf(strength, 0.0, 1.0)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(reach, 0.05, reach), 0.32).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


## Where a fighter drops out of the arena: a tall themed plume.
static func fall_splash(parent: Node, pos: Vector3) -> void:
	var at := Vector3(pos.x, minf(pos.y, 0.0), pos.z)
	var hot := world == WorldTheme.Kind.LAVA
	var cols: Array = [Color(1, 0.85, 0.4, 1), Color(1, 0.4, 0.05, 0.9), Color(0.5, 0.08, 0.0, 0)] if hot else (
			[Color(1, 1, 1, 0.95), Color(0.85, 0.93, 1.0, 0.8), Color(0.8, 0.9, 1.0, 0)]
			if world == WorldTheme.Kind.SNOW else
			[Color(0.9, 0.95, 1.0, 0.8), Color(0.75, 0.82, 0.9, 0.5), Color(0.7, 0.8, 0.9, 0)])
	_burst(parent, at, {
		"amount": 22, "life": 0.9, "size": 0.35, "additive": hot, "glow": 2.2 if hot else 1.0,
		"dir": Vector3.UP, "spread": 22.0, "vmin": 5.0, "vmax": 12.0,
		"gravity": Vector3(0, -16, 0), "radius": 0.5,
		"grow": [Vector2(0, 1.0), Vector2(1, 0.3)], "colors": cols,
	})


## Victory confetti raining over a point.
static func confetti(parent: Node, pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := _emitter({
		"amount": 90.0 * _burst_scale(), "life": 3.2, "size": 0.2,
		"dir": Vector3.UP, "spread": 60.0, "vmin": 4.0, "vmax": 9.0,
		"gravity": Vector3(0, -6.5, 0), "damping": 1.2, "explosive": 0.85, "radius": 0.6,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)],
	})
	p.color_initial_ramp = _ramp([Color(1.0, 0.3, 0.35), Color(1.0, 0.8, 0.15),
			Color(0.3, 0.9, 0.45), Color(0.25, 0.65, 1.0), Color(0.8, 0.45, 1.0)])
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.one_shot = true
	_launch(parent, p, pos)
