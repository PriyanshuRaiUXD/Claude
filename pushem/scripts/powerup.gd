class_name Powerup
extends Node3D


enum Kind {GLOVES, SPIKES, BOMB, DASH, SHOES}

const NAMES := {
	Kind.GLOVES: "GLOVES",
	Kind.SPIKES: "SPIKES",
	Kind.BOMB: "BOMB",
	Kind.DASH: "DASH",
	Kind.SHOES: "JUMPER SHOES",
}
const COLORS := {
	Kind.GLOVES: Color(0.9, 0.15, 0.15),
	Kind.SPIKES: Color(0.75, 0.78, 0.82),
	Kind.BOMB: Color(0.12, 0.12, 0.14),
	Kind.DASH: Color(1.0, 0.82, 0.12),
	Kind.SHOES: Color(0.25, 0.8, 1.0),
}

const DURATION := {
	Kind.GLOVES: 10.0,
	Kind.SPIKES: 10.0,
	Kind.BOMB: 8.0,
	Kind.DASH: 6.0,
	Kind.SHOES: 1.0,
}
const GLOVES_HIT_MULT := 2.5

const BOMB_MIN_RANGE := 2.5
const BOMB_MAX_RANGE := 14.0

const JUMP_MIN_RANGE := 2.0
const JUMP_MAX_RANGE := 9.0
const JUMP_STOMP_DISTANCE := 5.0

const STOMP_GRAB_BLOCK := 2.0

const CANCEL_DELAY := 2.0
const GRIP_TIME := 1.0
const HOLE_SCALE := 1.65
const PICKUP_REACH := 1.0

const FALL_TIME := 3.0
const FALL_HEIGHT := 18.0

const MODEL_SCALE := 1.6
const HOVER_Y := 1.0

var kind: Kind = Kind.GLOVES

var landed := false

var _model: Node3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _fall_left := FALL_TIME
var _t := randf() * TAU


static func timed(k: int) -> bool:
	return k != Kind.SHOES


static func jump_time(distance: float) -> float:
	return 0.5 + 0.04 * distance


static func jump_arc(from: Vector3, to: Vector3, u: float) -> Vector3:
	var flat := Vector3(from.x - to.x, 0.0, from.z - to.z).length()
	var peak := 2.0 + 0.15 * flat
	return from.lerp(to, u) + Vector3.UP * (4.0 * peak * u * (1.0 - u))


static func bomb_flight_time(distance: float) -> float:
	return 0.9 + 0.05 * distance


static func bomb_arc(from: Vector3, to: Vector3, u: float) -> Vector3:
	var flat := Vector3(from.x - to.x, 0.0, from.z - to.z).length()
	var peak := 2.0 + 0.3 * flat
	return from.lerp(to, u) + Vector3.UP * (4.0 * peak * u * (1.0 - u))


static func hole_radius() -> float:
	return PlayerPawn.STATS[PlayerPawn.WeightClass.HEAVY]["radius"] * HOLE_SCALE


func _ready() -> void:
	_model = build_model(kind)
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position.y = FALL_HEIGHT
	add_child(_model)

	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.55
	ring.rings = 32
	_marker.mesh = ring
	_marker.position.y = 0.03
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint: Color = Color(1.0, 0.55, 0.15) if kind == Kind.BOMB else COLORS[kind].lightened(0.3)
	_marker_mat.albedo_color = tint
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.01
	disc.radial_segments = 24
	_shadow.mesh = disc
	_shadow.position.y = 0.02
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

func _process(delta: float) -> void:
	_t += delta
	if not landed:
		_fall_left = maxf(0.0, _fall_left - delta)
		var k := 1.0 - _fall_left / FALL_TIME

		_model.position.y = lerpf(FALL_HEIGHT, HOVER_Y, k * k)
		_model.rotation.y += delta * 6.0
		var pulse := 0.5 + 0.5 * sin(_t * 10.0)
		var s := lerpf(2.4, 1.0, k)
		_marker.scale = Vector3(s, 0.2, s)
		_marker_mat.albedo_color.a = lerpf(0.3, 0.85, k) * lerpf(0.7, 1.0, pulse)
		var sh := lerpf(0.3, 1.0, k)
		_shadow.scale = Vector3(sh, 1.0, sh)
		_shadow_mat.albedo_color.a = lerpf(0.12, 0.5, k)
		if _fall_left == 0.0:
			landed = true
			_shadow.visible = false
			GameAudio.play("bump", -10.0, 1.7)
			Fx.land_puff(get_parent(), global_position)
		return
	_model.rotation.y += delta * 2.0
	_model.position.y = HOVER_Y + sin(_t * 3.0) * 0.12

	var beat := 0.5 + 0.5 * sin(_t * 4.0)
	_marker.scale = Vector3(2.1 + 0.2 * beat, 0.2, 2.1 + 0.2 * beat)
	_marker_mat.albedo_color.a = lerpf(0.35, 0.7, beat)


static func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func _part(mesh: Mesh, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, emission)
	mi.position = pos
	return mi


static func build_model(k: Kind) -> Node3D:
	var root := Node3D.new()
	match k:
		Kind.GLOVES:
			var glove := BoxMesh.new()
			glove.size = Vector3(0.55, 0.45, 0.55)
			root.add_child(_part(glove, COLORS[k]))
			var thumb := BoxMesh.new()
			thumb.size = Vector3(0.22, 0.2, 0.22)
			root.add_child(_part(thumb, COLORS[k].lightened(0.15), Vector3(0.3, 0.12, 0.0)))
			var cuff := CylinderMesh.new()
			cuff.top_radius = 0.2
			cuff.bottom_radius = 0.2
			cuff.height = 0.14
			root.add_child(_part(cuff, Color(0.95, 0.9, 0.75), Vector3(0.0, -0.28, 0.0)))
		Kind.SPIKES:
			var ball := SphereMesh.new()
			ball.radius = 0.3
			ball.height = 0.6
			root.add_child(_part(ball, Color(0.35, 0.37, 0.4)))
			for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
					Vector3.FORWARD, Vector3.BACK,
					Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(),
					Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = 0.09
				spike.height = 0.42
				var mi := _part(spike, COLORS[k], dir * 0.4)
				if dir == Vector3.DOWN:
					mi.rotation.x = PI
				elif dir != Vector3.UP:
					mi.basis = Basis(Quaternion(Vector3.UP, dir))
				root.add_child(mi)
		Kind.BOMB:
			var body := SphereMesh.new()
			body.radius = 0.38
			body.height = 0.76
			root.add_child(_part(body, COLORS[k]))
			var fuse := CylinderMesh.new()
			fuse.top_radius = 0.04
			fuse.bottom_radius = 0.04
			fuse.height = 0.26
			root.add_child(_part(fuse, Color(0.8, 0.75, 0.6), Vector3(0.0, 0.45, 0.0)))
			var spark := SphereMesh.new()
			spark.radius = 0.08
			spark.height = 0.16
			root.add_child(_part(spark, Color(1.0, 0.6, 0.1), Vector3(0.0, 0.6, 0.0), 3.0))
		Kind.DASH:

			var bar := BoxMesh.new()
			bar.size = Vector3(0.16, 0.42, 0.12)
			for seg: Array in [[Vector3(0.08, 0.3, 0.0), -0.55],
					[Vector3(-0.02, 0.0, 0.0), 0.9], [Vector3(-0.1, -0.3, 0.0), -0.55]]:
				var mi := _part(bar, COLORS[k], seg[0], 1.6)
				mi.rotation.z = seg[1]
				root.add_child(mi)
		Kind.SHOES:

			var sole := BoxMesh.new()
			sole.size = Vector3(0.34, 0.09, 0.66)
			root.add_child(_part(sole, Color(0.96, 0.96, 0.98), Vector3(0.0, -0.2, 0.04)))
			var upper := BoxMesh.new()
			upper.size = Vector3(0.3, 0.34, 0.36)
			root.add_child(_part(upper, COLORS[k], Vector3(0.0, 0.0, -0.1)))
			var toe := BoxMesh.new()
			toe.size = Vector3(0.3, 0.17, 0.3)
			root.add_child(_part(toe, COLORS[k], Vector3(0.0, -0.08, 0.22)))
			var stripe := BoxMesh.new()
			stripe.size = Vector3(0.32, 0.06, 0.2)
			root.add_child(_part(stripe, Color(1.0, 1.0, 1.0), Vector3(0.0, 0.05, -0.02)))
			var coil := TorusMesh.new()
			coil.inner_radius = 0.08
			coil.outer_radius = 0.13
			for y: float in [-0.3, -0.38]:
				root.add_child(_part(coil, Color(1.0, 0.85, 0.25), Vector3(0.0, y, 0.0), 0.8))
			var wing := BoxMesh.new()
			wing.size = Vector3(0.03, 0.16, 0.3)
			for side: float in [-1.0, 1.0]:
				var w := _part(wing, Color(1.0, 1.0, 1.0), Vector3(side * 0.18, 0.12, -0.2), 0.6)
				w.rotation = Vector3(-0.6, 0.0, side * -0.35)
				root.add_child(w)
	return root


static func landing_marker(radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.12
	ring.outer_radius = radius
	ring.rings = 40
	marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 1.5
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return marker


static func make_hole(radius: float, wall_color: Color) -> Node3D:
	var root := Node3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = Arena.FLOOR_THICKNESS
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 40
	var wall := MeshInstance3D.new()
	wall.mesh = tube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wall_color
	mat.roughness = 1.0

	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = -Arena.FLOOR_THICKNESS / 2.0
	root.add_child(wall)
	return root
