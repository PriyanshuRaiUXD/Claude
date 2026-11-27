class_name Arena
extends Node3D


enum Shape {SQUARE, RECTANGLE, CIRCLE, HEXAGON}

const FLOOR_THICKNESS := 1.2
const SHAPE_NAMES := {
	Shape.SQUARE: "Square",
	Shape.RECTANGLE: "Rectangle",
	Shape.CIRCLE: "Circle",
	Shape.HEXAGON: "Hexagon",
}


const MOUNTAIN_RINGS := [
	[2.5, 0.3, 0.3],
	[6.0, 2.6, 1.6],
	[13.0, 7.5, 3.0],
	[30.0, 17.0, 5.0],
	[60.0, 20.0, 5.0],
	[150.0, 34.0, 9.0],
]


const RING_SEGMENT := [1.6, 0.8, 0.45]
const BAND_ROWS := [1, 3, 5]
const CIRCLE_DRAW_SIDES := [64, 128, 192]
const RIM_ROWS := [1, 3, 5]
const ROCK_NOISE := [0.0, 0.7, 1.0]
const RIM_BEVEL := 0.32
const CIRCLE_SIDES := 64

const HULL_STEP := 0.002

const MAX_HOLES := 8
const SURFACE := Color(1, 0, 0)
const CLIFF := Color(0, 0, 0)

const TERRAIN_SHADER := "\nshader_type spatial;\nrender_mode __CULL__;\n\nuniform vec4 holes[8];  // xy = hole centre (world x, z), z = radius\nuniform int hole_count = 0;\nuniform int style = 0;  // WorldTheme.Kind: 0 lava, 1 snow, 2 windy\nuniform int detail = 2;  // 0 low .. 2 high (Graphics setting)\n// Sudden death: the mountain's top rows slide in with the platform. UV\n// holds how far a vertex moves at shrink 0 (zero for everything fixed),\n// so shrinking is a uniform, not a mesh rebuild.\nuniform float shrink = 1.0;\n\nvarying vec3 world_pos;\nvarying float follow;\n\nvoid vertex() {\n\tVERTEX.xz -= UV * (1.0 - shrink);\n\tfollow = UV2.x;\n\tworld_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nfloat hash3(vec3 p) {\n\tuvec3 q = uvec3(ivec3(floor(p)));\n\tuint h = q.x * 1664525u + q.y * 1013904223u + q.z * 2654435761u;\n\th ^= h >> 16u;\n\th *= 2246822519u;\n\th ^= h >> 13u;\n\th *= 3266489917u;\n\th ^= h >> 16u;\n\treturn float(h >> 8u) * (1.0 / 16777216.0);\n}\n\nfloat noise3(vec3 p) {\n\tvec3 i = floor(p);\n\tvec3 f = fract(p);\n\tvec3 u = f * f * (3.0 - 2.0 * f);\n\tfloat a = mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), u.x);\n\tfloat b = mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), u.x);\n\tfloat c = mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), u.x);\n\tfloat d = mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), u.x);\n\treturn mix(mix(a, b, u.y), mix(c, d, u.y), u.z);\n}\n\nfloat fbm3(vec3 p) {\n\tfloat v = 0.0;\n\tfloat amp = 0.5;\n\tfor (int i = 0; i < 3; i++) {\n\t\tv += amp * noise3(p);\n\t\tp = p * 2.03 + vec3(17.1, 5.3, 11.7);\n\t\tamp *= 0.5;\n\t}\n\treturn v;\n}\n\n// Distance to the nearest Voronoi cell border: 0 on a crack / stone seam.\nfloat voronoi_edge(vec2 p) {\n\tvec2 n = floor(p);\n\tvec2 f = fract(p);\n\tfloat d1 = 8.0;\n\tfloat d2 = 8.0;\n\tfor (int j = -1; j <= 1; j++) {\n\t\tfor (int i = -1; i <= 1; i++) {\n\t\t\tvec2 g = vec2(float(i), float(j));\n\t\t\tvec2 c = n + g;\n\t\t\tvec2 o = vec2(hash3(vec3(c, 0.0)), hash3(vec3(c, 5.0)));\n\t\t\tfloat d = length(g + o - f);\n\t\t\tif (d < d1) { d2 = d1; d1 = d; }\n\t\t\telse if (d < d2) { d2 = d; }\n\t\t}\n\t}\n\treturn d2 - d1;\n}\n\nvoid fragment() {\n\tfor (int i = 0; i < hole_count; i++) {\n\t\tif (distance(world_pos.xz, holes[i].xy) < holes[i].z) {\n\t\t\tdiscard;\n\t\t}\n\t}\n\tvec3 wp = world_pos;\n\tbool surface = COLOR.r > 0.5;\n\tfloat rim = COLOR.g;  // > 0 on the platform's rounded lip\n\tif (follow > 0.01 && shrink < 0.999) {\n\t\t// The sliding rows were lit for the full-size mountain: as the top\n\t\t// pulls in, blend toward the true facet normal.\n\t\tvec3 fn = normalize(cross(dFdy(world_pos), dFdx(world_pos)));\n\t\tif (dot(fn, CAMERA_POSITION_WORLD - world_pos) < 0.0) {\n\t\t\tfn = -fn;\n\t\t}\n\t\tNORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(fn, 0.0)).xyz,\n\t\t\t\tfollow * clamp((1.0 - shrink) * 4.0, 0.0, 1.0)));\n\t}\n\tfloat n = fbm3(wp * 0.35);\n\tvec3 col;\n\tvec3 emit = vec3(0.0);\n\tfloat rough = 0.9;\n\n\tif (style == 0) {\n\t\tif (surface) {\n\t\t\t// Cooled basalt crust split by glowing lava cracks.\n\t\t\tcol = mix(vec3(0.05, 0.035, 0.03), vec3(0.14, 0.09, 0.07), n);\n\t\t\tfloat e = voronoi_edge(wp.xz * 0.26);\n\t\t\t// Only some seams are open: the rest stay dark, cooled crust.\n\t\t\tfloat open_seam = smoothstep(0.35, 0.55, fbm3(vec3(wp.x * 0.12, 7.0, wp.z * 0.12)));\n\t\t\tfloat crack = (1.0 - smoothstep(0.0, 0.045, e)) * mix(0.25, 1.0, open_seam);\n\t\t\tif (detail > 0) {\n\t\t\t\tfloat fine = 1.0 - smoothstep(0.0, 0.03, voronoi_edge(wp.xz * 0.9 + 13.0));\n\t\t\t\tcrack = max(crack, fine * smoothstep(0.55, 0.7, n) * 0.6);\n\t\t\t}\n\t\t\tfloat pulse = 0.7 + 0.3 * sin(TIME * 2.0 + n * 9.0);\n\t\t\tvec3 lava = mix(vec3(1.0, 0.22, 0.02), vec3(1.0, 0.65, 0.15), crack * pulse);\n\t\t\tcol = mix(col, lava, crack);\n\t\t\tcol += vec3(0.18, 0.03, 0.0) * (1.0 - smoothstep(0.0, 0.18, e)) * open_seam * 0.5;\n\t\t\temit = lava * crack * 0.8 * pulse;\n\t\t} else {\n\t\t\t// Volcano flank: dark rock with lava streams creeping down.\n\t\t\tfloat m = fbm3(wp * vec3(0.5, 0.18, 0.5));\n\t\t\tcol = mix(vec3(0.07, 0.05, 0.045), vec3(0.2, 0.13, 0.1), m);\n\t\t\tfloat stream = smoothstep(0.6, 0.68,\n\t\t\t\t\tfbm3(vec3(wp.x * 0.35, wp.y * 0.06 + TIME * 0.08, wp.z * 0.35)));\n\t\t\tvec3 lava = vec3(1.0, 0.35, 0.05);\n\t\t\tcol = mix(col, lava, stream);\n\t\t\temit = lava * stream * 1.8;\n\t\t}\n\t} else if (style == 1) {\n\t\tif (surface) {\n\t\t\t// Packed snow with soft drifts and glints.\n\t\t\t// (Colours here are linear light, as ALBEDO expects.)\n\t\t\tcol = mix(vec3(0.3, 0.38, 0.52), vec3(0.62, 0.68, 0.77), smoothstep(0.25, 0.75, n));\n\t\t\t// Wind-carved drifts: soft blue-shadowed ridges.\n\t\t\tfloat drift = fbm3(vec3(wp.x * 0.09 + wp.z * 0.05, 1.0, wp.z * 0.3));\n\t\t\tcol *= mix(0.8, 1.05, smoothstep(0.35, 0.65, drift));\n\t\t\tif (detail > 0) {\n\t\t\t\tfloat glint = step(0.985, hash3(vec3(floor(wp.x * 18.0), floor(wp.z * 18.0),\n\t\t\t\t\t\tfloor(TIME * 3.0))));\n\t\t\t\tcol += vec3(glint * 0.6);\n\t\t\t}\n\t\t\trough = 0.55;\n\t\t} else {\n\t\t\t// Ice cliff with a snow cap along the top.\n\t\t\tfloat m = fbm3(wp * vec3(0.6, 0.12, 0.6));\n\t\t\tcol = mix(vec3(0.08, 0.22, 0.42), vec3(0.4, 0.6, 0.8), m);\n\t\t\tfloat cap = smoothstep(-1.8, -0.6, wp.y);\n\t\t\tcol = mix(col, vec3(0.62, 0.68, 0.78), cap);\n\t\t\trough = mix(0.25, 0.6, cap);\n\t\t}\n\t} else {\n\t\tif (surface) {\n\t\t\t// Rocky summit: stone slabs, seams, and tufts of grass.\n\t\t\tcol = mix(vec3(0.07, 0.042, 0.022), vec3(0.17, 0.105, 0.055), n);\n\t\t\tfloat e = voronoi_edge(wp.xz * 0.55);\n\t\t\tcol *= mix(0.6, 1.0, smoothstep(0.0, 0.08, e));\n\t\t\tfloat grass = smoothstep(0.62, 0.74, fbm3(vec3(wp.x * 0.18, 3.0, wp.z * 0.18)));\n\t\t\tcol = mix(col, vec3(0.05, 0.13, 0.025), grass * 0.75);\n\t\t} else {\n\t\t\t// Layered rock, greening toward the valley.\n\t\t\tfloat strata = 0.5 + 0.5 * sin(wp.y * 2.4 + fbm3(wp * 0.4) * 4.0);\n\t\t\tcol = mix(vec3(0.05, 0.032, 0.02), vec3(0.16, 0.1, 0.06), strata * 0.6 + n * 0.4);\n\t\t\tfloat green = (1.0 - smoothstep(-16.0, -6.0, wp.y)) * smoothstep(0.4, 0.6, fbm3(wp * 0.25));\n\t\t\tcol = mix(col, vec3(0.04, 0.11, 0.02), green);\n\t\t}\n\t}\n\tif (rim > 0.0) {\n\t\t// The lip: worn edge stones, dark in the seams, a little lighter\n\t\t// on the crown.\n\t\tfloat stones = smoothstep(0.0, 0.12, voronoi_edge(wp.xz * 1.1 + 31.0));\n\t\tcol *= mix(1.0, mix(0.5, 1.15, stones), rim);\n\t\temit *= 1.0 - rim * 0.6;\n\t}\n\tALBEDO = col;\n\tROUGHNESS = rough;\n\tEMISSION = emit;\n}\n"


var shape: Shape = Shape.CIRCLE
var world: WorldTheme.Kind = WorldTheme.Kind.WINDY
var shrink_factor := 1.0:
	set(value):
		shrink_factor = clampf(value, 0.05, 1.0)
		if _body != null:
			_rebuild()

var _base_points: PackedVector2Array
var _body: StaticBody3D
var _collision: CollisionShape3D
var _mesh_instance: MeshInstance3D
var _mountain: MeshInstance3D
var _surface_mat: ShaderMaterial
var _cliff_mat: ShaderMaterial
var _hull_shrink := -1.0
var _q := 1
var _rows: Array[PackedVector3Array] = []
var _band_rows := 1
var _noise := FastNoiseLite.new()

static func base_points_for(p_shape: Shape) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match p_shape:
		Shape.SQUARE:
			for corner in [Vector2(-14, -14), Vector2(14, -14), Vector2(14, 14), Vector2(-14, 14)]:
				pts.append(corner)
		Shape.RECTANGLE:
			for corner in [Vector2(-19, -12), Vector2(19, -12), Vector2(19, 12), Vector2(-19, 12)]:
				pts.append(corner)
		Shape.CIRCLE:
			for i in CIRCLE_SIDES:
				var a := TAU * i / CIRCLE_SIDES
				pts.append(Vector2(cos(a), sin(a)) * 16.0)
		Shape.HEXAGON:
			for i in 6:
				var a := TAU * i / 6.0
				pts.append(Vector2(cos(a), sin(a)) * 17.0)
	return pts

static func _terrain_material(cull: String, world_kind: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = TERRAIN_SHADER.replace("__CULL__", cull)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("style", world_kind)
	mat.set_shader_parameter("detail", clampi(Settings.quality()["octaves"] - 3, 0, 2))
	mat.set_shader_parameter("shrink", 1.0)
	return mat

func _ready() -> void:
	_base_points = base_points_for(shape)
	_q = clampi(int(Settings.quality().get("world_detail", 1)), 0, 2)
	_noise.seed = 4271 + int(shape) * 17 + int(world) * 101
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 3

	_surface_mat = _terrain_material("cull_disabled", world)

	_cliff_mat = _terrain_material("cull_back", world)
	set_holes([])

	_body = StaticBody3D.new()

	_body.collision_layer = PlayerPawn.LAYER_FLOOR
	_body.collision_mask = 0
	_collision = CollisionShape3D.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = _surface_mat
	_body.add_child(_collision)
	_body.add_child(_mesh_instance)
	add_child(_body)

	_mountain = MeshInstance3D.new()
	_mountain.material_override = _cliff_mat
	add_child(_mountain)

	_mesh_instance.mesh = _platform_mesh()
	_mountain.mesh = _mountain_mesh()
	_build_props()
	if world == WorldTheme.Kind.SNOW:
		var walls := MeshInstance3D.new()
		walls.mesh = _glacier_walls()
		walls.material_override = _terrain_material("cull_disabled", world)
		walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(walls)
	_rebuild()


func set_holes(holes: Array) -> void:
	var packed := PackedVector4Array()
	packed.resize(MAX_HOLES)
	var n := mini(holes.size(), MAX_HOLES)
	for i in n:
		var pos: Vector3 = holes[i]["pos"]
		packed[i] = Vector4(pos.x, pos.z, holes[i]["r"], 0.0)
	_surface_mat.set_shader_parameter("holes", packed)
	_surface_mat.set_shader_parameter("hole_count", n)


func wall_color() -> Color:
	match world:
		WorldTheme.Kind.LAVA:
			return Color(0.16, 0.09, 0.07)
		WorldTheme.Kind.SNOW:
			return Color(0.5, 0.68, 0.84)
	return Color(0.32, 0.24, 0.16)


func outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in _base_points:
		pts.append(p * shrink_factor)
	return pts


func current_radius() -> float:
	var r := 0.0
	for p in _base_points:
		r = maxf(r, p.length())
	return r * shrink_factor


func inner_radius() -> float:
	return edge_distance(Vector3.ZERO)


func edge_distance(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var n := _base_points.size()
	var best := INF
	for i in n:
		var a := _base_points[i] * shrink_factor
		var b := _base_points[(i + 1) % n] * shrink_factor
		var inward := (b - a).orthogonal().normalized()
		if inward.dot(-a) < 0.0:
			inward = -inward
		best = minf(best, inward.dot(p - a))
	return best


func contains(pos: Vector3, margin := 0.0) -> bool:
	return edge_distance(pos) >= margin


func random_point(margin: float) -> Vector3:
	var reach := current_radius()
	for attempt in 40:
		var pos := Vector3(randf_range(-reach, reach), 0.0, randf_range(-reach, reach))
		if contains(pos, margin):
			return pos
	return Vector3.ZERO

func get_spawn_points(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ring := inner_radius() * 0.62
	for i in count:
		var a := TAU * i / count - PI / 2.0
		out.append(Vector3(cos(a) * ring, 1.2, sin(a) * ring))
	return out

func _rebuild() -> void:
	var s := shrink_factor
	_mesh_instance.scale = Vector3(s, 1.0, s)
	_cliff_mat.set_shader_parameter("shrink", s)
	if absf(s - _hull_shrink) < HULL_STEP and s > 0.0501 and s < 0.9999:
		return
	_hull_shrink = s
	if shape == Shape.CIRCLE:

		var cyl := _collision.shape as CylinderShape3D
		if cyl == null:
			cyl = CylinderShape3D.new()
			cyl.height = FLOOR_THICKNESS
			_collision.shape = cyl
			_collision.position.y = -FLOOR_THICKNESS * 0.5
		cyl.radius = 16.0 * s
		return

	var hull := PackedVector3Array()
	for p in _base_points:
		hull.append(Vector3(p.x * s, 0.0, p.y * s))
		hull.append(Vector3(p.x * s, -FLOOR_THICKNESS, p.y * s))
	var hull_shape: ConvexPolygonShape3D = _collision.shape
	if hull_shape == null:
		hull_shape = ConvexPolygonShape3D.new()
		hull_shape.points = hull
		_collision.shape = hull_shape
	else:
		hull_shape.points = hull


func _draw_outline() -> PackedVector2Array:
	if shape != Shape.CIRCLE:
		return _base_points
	var pts := PackedVector2Array()
	var n: int = CIRCLE_DRAW_SIDES[_q]
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * 16.0)
	return pts


static func _edge_normal(a: Vector2, b: Vector2) -> Vector2:
	var n := (b - a).orthogonal().normalized()
	return n if n.dot(a + b) > 0.0 else -n


const RIM_BAND := 0.55


func _platform_mesh() -> ArrayMesh:
	var pts := _draw_outline()
	var n := pts.size()
	var smooth := shape == Shape.CIRCLE
	var rows: int = RIM_ROWS[_q]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	var miter := PackedVector2Array()
	var mlen := PackedFloat32Array()
	for i in n:
		var n0 := _edge_normal(pts[(i - 1 + n) % n], pts[i])
		var n1 := _edge_normal(pts[i], pts[(i + 1) % n])
		var mv := (n0 + n1).normalized()
		miter.append(mv)
		mlen.append(1.0 / maxf(mv.dot(n1), 0.35))
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	colors.append(SURFACE)
	uvs.append(Vector2.ZERO)
	for i in n:
		var ia := i
		var ib := (i + 1) % n
		var side := _edge_normal(pts[ia], pts[ib])
		var cols: Array[PackedInt32Array] = []
		for k: int in [ia, ib]:
			var p := pts[k]
			var out := miter[k] if smooth else side
			var col := PackedInt32Array()

			var profile: Array = [[RIM_BEVEL + RIM_BAND, 0.0, 0.0, 0.0]]
			for r in rows + 1:
				var th := PI * 0.5 * float(r) / rows
				profile.append([RIM_BEVEL * (1.0 - sin(th)), -RIM_BEVEL * (1.0 - cos(th)), th,
						0.65 + 0.35 * float(r) / rows])
			for step: Array in profile:
				var inset: float = step[0]
				var q := p - miter[k] * inset * mlen[k]
				var th: float = step[2]
				col.append(verts.size())
				verts.append(Vector3(q.x, step[1], q.y))
				normals.append(Vector3(out.x * sin(th), cos(th), out.y * sin(th)).normalized())
				colors.append(Color(1.0, step[3], 0.0))
				uvs.append(Vector2.ZERO)
			for y: float in [-RIM_BEVEL, -FLOOR_THICKNESS]:
				col.append(verts.size())
				verts.append(Vector3(p.x, y, p.y))
				normals.append(Vector3(out.x, 0.0, out.y))
				colors.append(CLIFF)
				uvs.append(Vector2.ZERO)
			cols.append(col)
		var ca := cols[0]
		var cb := cols[1]
		idx.append_array([0, ca[0], cb[0]])
		var lip_end := rows + 1
		for r in ca.size() - 1:
			if r == lip_end:
				continue
			idx.append_array([ca[r], ca[r + 1], cb[r]])
			idx.append_array([cb[r], ca[r + 1], cb[r + 1]])
	return _commit(verts, normals, colors, uvs, PackedVector2Array(), idx)

static func _commit(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		idx: PackedInt32Array) -> ArrayMesh:
	if uv2s.is_empty():
		uv2s.resize(verts.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _densify(pts: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var steps := maxi(1, int(ceil(a.distance_to(b) / spacing)))
		for s in steps:
			out.append(a.lerp(b, float(s) / steps))
	return out


func _ring_noise(angle: float, k: int, freq: float) -> float:
	return clampf(_noise.get_noise_2d(cos(angle) * freq + k * 41.3,
			sin(angle) * freq - k * 17.9) * 0.75 + 0.5, 0.0, 1.0)


func _mountain_rings(top_ring: PackedVector2Array) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	var top := PackedVector3Array()
	for p in top_ring:
		top.append(Vector3(p.x, -FLOOR_THICKNESS, p.y))
	rings.append(top)
	for k in MOUNTAIN_RINGS.size():
		var spec: Array = MOUNTAIN_RINGS[k]
		var ring := PackedVector3Array()
		var freq := 1.8 + k * 0.6
		for p in top_ring:
			var dir := p.normalized() if p.length_squared() > 0.0001 else Vector2.RIGHT
			var ang := atan2(p.y, p.x)
			var out: float = spec[1] + (_ring_noise(ang, k, freq) - 0.5) * 2.0 * spec[2]
			var q := p + dir * maxf(out, 0.1)
			ring.append(Vector3(q.x, -FLOOR_THICKNESS - spec[0]
					-_ring_noise(ang, k + 9, freq * 1.3) * spec[2] * 0.5, q.y))
		rings.append(ring)
	return rings

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _mountain_mesh() -> ArrayMesh:
	var top_ring := _densify(_draw_outline(), RING_SEGMENT[_q])
	var rings := _mountain_rings(top_ring)
	var m := top_ring.size()
	var sub: int = BAND_ROWS[_q]
	var rough: float = ROCK_NOISE[_q]
	_band_rows = sub
	_rows.clear()
	var follow_rows := PackedFloat32Array()
	for b in rings.size() - 1:
		for j in sub:
			var t := float(j) / sub
			var row := PackedVector3Array()
			row.resize(m)
			for i in m:
				if sub == 1:
					row[i] = rings[b][i]
					continue
				row[i] = _catmull(rings[maxi(b - 1, 0)][i], rings[b][i], rings[b + 1][i],
						rings[mini(b + 2, rings.size() - 1)][i], t)
			_rows.append(row)
			follow_rows.append(1.0 if b == 0 else (1.0 - t if b == 1 else 0.0))
	_rows.append(rings[rings.size() - 1])
	follow_rows.append(0.0)

	if rough > 0.0:
		for r in _rows.size():
			var row := _rows[r]
			for i in m:
				var v := row[i]
				var depth := clampf((-v.y - FLOOR_THICKNESS - 0.8) / 10.0, 0.0, 1.0)
				if depth <= 0.0:
					continue
				var dir := Vector3(v.x, 0.0, v.z).normalized()
				var nz := _noise.get_noise_3d(v.x * 0.14, v.y * 0.2, v.z * 0.14)
				nz += 0.45 * _noise.get_noise_3d(v.x * 0.45 + 9.0, v.y * 0.55, v.z * 0.45)
				row[i] = v + dir * nz * rough * (0.8 + depth * 2.2) * depth
			_rows[r] = row
	var rows_n := _rows.size()
	var total := rows_n * m
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(total)
	normals.resize(total)
	colors.resize(total)
	uvs.resize(total)
	uv2s.resize(total)
	for r in rows_n:
		var up := _rows[maxi(r - 1, 0)]
		var dn := _rows[mini(r + 1, rows_n - 1)]
		var row := _rows[r]
		for i in m:
			var v := row[i]
			var tangent := row[(i + 1) % m] - row[(i - 1 + m) % m]
			var nrm := (dn[i] - up[i]).cross(tangent).normalized()
			if nrm.dot(Vector3(v.x, 0.0, v.z)) < 0.0:
				nrm = -nrm
			var k := r * m + i
			verts[k] = v
			normals[k] = nrm
			colors[k] = CLIFF
			uvs[k] = top_ring[i] * follow_rows[r]
			uv2s[k] = Vector2(follow_rows[r], 0.0)
	var idx := PackedInt32Array()
	idx.resize((rows_n - 1) * m * 6)
	var o := 0
	for r in rows_n - 1:
		for i in m:
			var j := (i + 1) % m
			var a := r * m + i
			var b := r * m + j
			var c := (r + 1) * m + i
			var d := (r + 1) * m + j
			idx[o] = a
			idx[o + 1] = c
			idx[o + 2] = b
			idx[o + 3] = b
			idx[o + 4] = c
			idx[o + 5] = d
			o += 6
	return _commit(verts, normals, colors, uvs, uv2s, idx)


func random_edge_point() -> Array:
	var n := _base_points.size()
	var i := randi() % n
	var p := _base_points[i].lerp(_base_points[(i + 1) % n], randf()) * shrink_factor
	var out := Vector3(p.x, 0.0, p.y)
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.RIGHT
	return [Vector3(p.x, -0.25, p.y), out]


func rock_color() -> Color:
	match world:
		WorldTheme.Kind.LAVA:
			return Color(0.13, 0.09, 0.07)
		WorldTheme.Kind.SNOW:
			return Color(0.86, 0.91, 0.97)
	return Color(0.36, 0.26, 0.17)


const PROP_DENSITY := [0.25, 0.6, 1.0]

static func _mat(color: Color, rough := 0.95, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


const PROP_SIDES := [[7, 4, 6], [10, 6, 9], [14, 8, 12]]

func _rock_mesh(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = PROP_SIDES[_q][0]
	s.rings = PROP_SIDES[_q][1]
	return s

func _build_props() -> void:
	var density: float = PROP_DENSITY[Settings.scenery]
	var shadows: bool = Settings.scenery == 2 and Settings.quality()["shadows"]
	var rings := _rows
	var sides: int = PROP_SIDES[_q][2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + int(shape) * 31 + int(world) * 131
	match world:
		WorldTheme.Kind.LAVA:
			_scatter(rings, rng, _rock_mesh(1.0), _mat(Color(0.11, 0.075, 0.06)),
					int(45 * density), 0.5, 1.8, 0.45, false, 0.35, shadows)
			var pool := CylinderMesh.new()
			pool.top_radius = 1.0
			pool.bottom_radius = 1.0
			pool.height = 0.06
			pool.radial_segments = sides * 2
			_scatter(rings, rng, pool, _mat(Color(1.0, 0.35, 0.05), 1.0, 2.2),
					int(16 * density), 0.8, 2.2, 1.0, false, 0.0, false)
		WorldTheme.Kind.SNOW:
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.35
			crystal.height = 2.4
			crystal.radial_segments = 6
			crystal.rings = 1
			var ice := _mat(Color(0.55, 0.82, 1.0), 0.08, 0.35)
			ice.metallic = 0.2
			_scatter(rings, rng, crystal, ice, int(60 * density), 0.6, 1.9, 1.0, false, 0.2, shadows,
					0.35)
			_scatter(rings, rng, _rock_mesh(1.0), _mat(Color(0.9, 0.94, 1.0), 0.7),
					int(35 * density), 0.8, 2.2, 0.35, false, 0.25, shadows)
		_:

			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.1
			trunk.bottom_radius = 0.14
			trunk.height = 0.9
			trunk.radial_segments = sides
			var foliage := SurfaceTool.new()
			for c in 3:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.75 - c * 0.18
				cone.height = 1.0
				cone.radial_segments = sides + 1
				foliage.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 1.0 + c * 0.55, 0)))
			var xforms := _placements(rings, rng, int(70 * density), 0.8, 1.6, 1.0, true, 0.1)
			_multimesh(trunk, _mat(Color(0.3, 0.18, 0.09)), xforms, shadows, Vector3(0, 0.45, 0))
			_multimesh(foliage.commit(), _mat(Color(0.1, 0.3, 0.12), 0.9), xforms, shadows)
			_scatter(rings, rng, _rock_mesh(0.6), _mat(Color(0.2, 0.42, 0.14), 0.95),
					int(45 * density), 0.6, 1.4, 0.7, true, 0.15, shadows)
			_scatter(rings, rng, _rock_mesh(1.0), _mat(Color(0.4, 0.36, 0.3)),
					int(25 * density), 0.5, 1.5, 0.55, false, 0.3, shadows)


func _placements(rows: Array[PackedVector3Array], rng: RandomNumberGenerator, count: int,
		smin: float, smax: float, yscale: float, upright: bool, sink: float,
		tilt := 0.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for n in count:
		var k := 2 if rng.randf() < 0.75 else 3
		var f := (k + rng.randf_range(0.05, 0.7)) * _band_rows
		var r := mini(int(f), rows.size() - 2)
		var ra: PackedVector3Array = rows[r]
		var rb: PackedVector3Array = rows[r + 1]
		var i := rng.randi() % ra.size()
		var j := (i + 1) % ra.size()
		var u := rng.randf()
		var top := ra[i].lerp(ra[j], u)
		var bottom := rb[i].lerp(rb[j], u)
		var p := top.lerp(bottom, f - r)
		var tangent := (ra[j] - ra[i]).normalized()
		var normal := tangent.cross((bottom - top).normalized()).normalized()
		if normal.y < 0.0:
			normal = -normal
		var s := rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if not upright:
			basis = Basis(Quaternion(Vector3.UP, normal)) * basis
		if tilt > 0.0:
			basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-tilt, tilt))
		basis = basis * Basis.from_scale(Vector3(s, s * yscale, s))
		out.append(Transform3D(basis, p - normal * sink * s))
	return out

func _multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadows: bool,
		offset := Vector3.ZERO) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for n in xforms.size():
		var x := xforms[n]
		mm.set_instance_transform(n, Transform3D(x.basis, x.origin + x.basis * offset))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(inst)

func _scatter(rings: Array[PackedVector3Array], rng: RandomNumberGenerator, mesh: Mesh,
		mat: Material, count: int, smin: float, smax: float, yscale: float, upright: bool,
		sink: float, shadows: bool, tilt := 0.0) -> void:
	_multimesh(mesh, mat, _placements(rings, rng, count, smin, smax, yscale, upright, sink, tilt),
			shadows)


func glacier_radius() -> float:
	var r0 := 0.0
	for p in _base_points:
		r0 = maxf(r0, p.length())
	return r0 * 1.75 + 5.0


const GLACIER_CAP := 60.0


const GLACIER_SIDES := [64, 128, 192]
const GLACIER_ROWS := [1, 2, 4]


func _glacier_walls() -> ArrayMesh:
	var base := glacier_radius()
	var segments: int = GLACIER_SIDES[_q]
	var sub: int = GLACIER_ROWS[_q]

	var heights := [-150.0, -40.0, -14.0, -4.0]
	var control: Array[PackedVector3Array] = []
	for row in heights.size() + 2:
		var ring := PackedVector3Array()
		var k := row - 1
		for i in segments:
			var a := TAU * i / segments
			var r: float
			var y: float
			if row < heights.size() + 1:
				r = base + (_ring_noise(a, k + 60, 7.0) - 0.5) * 6.0 - k * 1.2
				y = heights[row] if row < heights.size() else -1.5 + _ring_noise(a, 42, 9.0) * 4.5
			else:
				r = base + GLACIER_CAP + (_ring_noise(a, 51, 5.0) - 0.5) * 9.0
				y = -1.2 + (_ring_noise(a, 52, 6.0) - 0.5) * 1.5
			ring.append(Vector3(cos(a) * r, y, sin(a) * r))
		control.append(ring)
	var rows: Array[PackedVector3Array] = []
	for b in control.size() - 1:

		var n_sub := sub if b < control.size() - 2 else 1
		for j in n_sub:
			var t := float(j) / n_sub
			var row := PackedVector3Array()
			row.resize(segments)
			for i in segments:
				row[i] = control[b][i] if n_sub == 1 else _catmull(control[maxi(b - 1, 0)][i],
						control[b][i], control[b + 1][i], control[mini(b + 2, control.size() - 2)][i], t)
			rows.append(row)
	rows.append(control[control.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(CLIFF)
	st.set_uv(Vector2.ZERO)
	st.set_uv2(Vector2.ZERO)
	for k in rows.size() - 1:
		var lo := rows[k]
		var hi := rows[k + 1]
		for i in segments:
			var j := (i + 1) % segments

			st.add_vertex(lo[i])
			st.add_vertex(hi[i])
			st.add_vertex(lo[j])
			st.add_vertex(lo[j])
			st.add_vertex(hi[i])
			st.add_vertex(hi[j])
	st.index()
	st.generate_normals()
	return st.commit()
