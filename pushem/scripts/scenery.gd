class_name WorldScenery
extends Node3D


const TERRAIN_RADIUS := 1400.0


const GRID := [[40, 90], [72, 160], [110, 240]]

const PROP_SIDES := [5, 7, 9]
const CLOUD_LAYERS := [1, 2, 3]
const CLOUD_OCTAVES := [2, 3, 4]
const PROP_SCALE := [0.3, 0.6, 1.0]

const GLACIER_CLEAR := 70.0


const WORLDS := {
	WorldTheme.Kind.LAVA: {
		"floor": -132.0, "liquid": -122.0, "mound": 27.0, "rough": 10.0, "ridge": 75.0,
		"seed": 11,
		"cloud_lit": Color(0.55, 0.22, 0.08), "cloud_shade": Color(0.07, 0.04, 0.035),
		"wind": Vector2(2.5, 1.0),
		"clouds": [[-30.0, 0.58, 0.55, 0.011], [-55.0, 0.52, 0.5, 0.008], [-85.0, 0.52, 0.45, 0.006]],
	},
	WorldTheme.Kind.SNOW: {
		"floor": -142.0, "liquid": -138.0, "mound": 0.0, "rough": 3.0, "ridge": 25.0,
		"seed": 23,
		"cloud_lit": Color(0.92, 0.95, 1.0), "cloud_shade": Color(0.5, 0.6, 0.74),
		"wind": Vector2(4.0, 1.2),
		"clouds": [[-28.0, 0.6, 0.5, 0.012], [-52.0, 0.54, 0.55, 0.008], [-82.0, 0.52, 0.5, 0.006]],
	},
	WorldTheme.Kind.WINDY: {
		"floor": -145.0, "liquid": -143.5, "mound": 28.0, "rough": 14.0, "ridge": 95.0,
		"seed": 37,
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.58, 0.65, 0.74),
		"wind": Vector2(6.0, 1.5),
		"clouds": [[-28.0, 0.6, 0.9, 0.011], [-50.0, 0.57, 0.85, 0.008], [-78.0, 0.57, 0.8, 0.006]],
	},
}


const NOISE_LIB := "\nfloat hash2(vec2 p) {\n\tuvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));\n\tuint h = q.x * 1664525u + q.y * 1013904223u;\n\th ^= h >> 16u;\n\th *= 2246822519u;\n\th ^= h >> 13u;\n\th *= 3266489917u;\n\th ^= h >> 16u;\n\treturn float(h >> 8u) * (1.0 / 16777216.0);\n}\n\nfloat noise2(vec2 p) {\n\tvec2 i = floor(p);\n\tvec2 f = fract(p);\n\tvec2 u = f * f * (3.0 - 2.0 * f);\n\tfloat a = hash2(i);\n\tfloat b = hash2(i + vec2(1.0, 0.0));\n\tfloat c = hash2(i + vec2(0.0, 1.0));\n\tfloat d = hash2(i + vec2(1.0, 1.0));\n\treturn mix(mix(a, b, u.x), mix(c, d, u.x), u.y);\n}\n\n// Normalised to 0..1 whatever the octave count, so thresholds (crust,\n// cloud cover) look the same on Low as on High; only the detail changes.\nfloat fbm2(vec2 p, int oct) {\n\tfloat v = 0.0;\n\tfloat amp = 0.5;\n\tfor (int i = 0; i < oct; i++) {\n\t\tv += amp * noise2(p);\n\t\tp = p * 2.07 + vec2(17.1, 5.3);\n\t\tamp *= 0.5;\n\t}\n\treturn v / (1.0 - 2.0 * amp);\n}\n\n// Distance to the nearest Voronoi cell border: 0 on a crack.\nfloat voronoi_edge(vec2 p) {\n\tvec2 n = floor(p);\n\tvec2 f = fract(p);\n\tfloat d1 = 8.0;\n\tfloat d2 = 8.0;\n\tfor (int j = -1; j <= 1; j++) {\n\t\tfor (int i = -1; i <= 1; i++) {\n\t\t\tvec2 g = vec2(float(i), float(j));\n\t\t\tvec2 o = vec2(hash2(n + g), hash2(n + g + vec2(41.0, 17.0)));\n\t\t\tfloat d = length(g + o - f);\n\t\t\tif (d < d1) { d2 = d1; d1 = d; }\n\t\t\telse if (d < d2) { d2 = d; }\n\t\t}\n\t}\n\treturn d2 - d1;\n}\n"


const TERRAIN_SHADER := "\nshader_type spatial;\nrender_mode cull_back, shadows_disabled;\n\nuniform int detail = 1;\nuniform int style = 0;\nuniform float liquid = -40.0;\n\nvarying vec3 wp;\n\n__NOISE__\n\nvoid vertex() {\n\twp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nvoid fragment() {\n\tvec3 col = COLOR.rgb;\n\tif (detail > 0) {\n\t\tcol *= mix(0.72, 1.18, fbm2(wp.xz * 0.03, detail + 1));\n\t\tif (detail > 1) {\n\t\t\tcol *= mix(0.88, 1.08, noise2(wp.xz * 0.25));\n\t\t}\n\t}\n\tALBEDO = col;\n\tROUGHNESS = style == 1 ? 0.7 : 0.95;\n\tif (style == 0) {\n\t\tfloat g = 1.0 - smoothstep(liquid, liquid + 2.0, wp.y);\n\t\tEMISSION = vec3(1.0, 0.24, 0.03) * g * g * 1.4;\n\t\tif (detail > 0) {\n\t\t\t// Rivers: thin channels fanning out from the mountain (noise\n\t\t\t// sampled on the outward direction, so they run radially),\n\t\t\t// with pulses flowing down toward the sea.\n\t\t\tfloat r = length(wp.xz);\n\t\t\tvec2 dir = wp.xz / max(r, 1.0);\n\t\t\tfloat rv = fbm2(dir * 7.0 + wp.xz * 0.006, 2);\n\t\t\tfloat river = 1.0 - smoothstep(0.01, 0.028, abs(rv - 0.5));\n\t\t\triver *= smoothstep(liquid + 1.0, liquid + 4.0, wp.y) * (1.0 - smoothstep(160.0, 260.0, r));\n\t\t\tfloat pulse = 0.75 + 0.25 * sin(r * 0.15 - TIME * 1.5);\n\t\t\tALBEDO = mix(ALBEDO, vec3(0.2, 0.04, 0.01), river);\n\t\t\tEMISSION += vec3(1.0, 0.3, 0.04) * river * 1.6 * pulse;\n\t\t}\n\t} else if (style == 1 && detail > 0 && wp.y > -20.0) {\n\t\t// Crevasses: thin blue cracks across the glacier.\n\t\tfloat e = voronoi_edge(wp.xz * 0.035);\n\t\tALBEDO = mix(vec3(0.05, 0.16, 0.3), ALBEDO, smoothstep(0.0, 0.05, e));\n\t}\n}\n"


const LAVA_SHADER := "\nshader_type spatial;\nrender_mode cull_back, shadows_disabled;\n\nuniform int detail = 1;\n\nvarying vec3 wp;\n\n__NOISE__\n\nvoid vertex() {\n\twp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nvoid fragment() {\n\tvec2 p = wp.xz;\n\tvec2 q = p * 0.012 + vec2(TIME * 0.006, TIME * 0.002);\n\tvec2 warp = vec2(0.0);\n\tfloat flow = 0.5;\n\tif (detail > 0) {\n\t\twarp = vec2(fbm2(q * 0.7 + TIME * 0.01, 2), fbm2(q * 0.7 + vec2(5.2, 1.3) - TIME * 0.008, 2));\n\t\t// Streaks stretched along the flow, sliding through the molten rock.\n\t\tflow = fbm2(vec2(p.x * 0.05, p.y * 0.014) + warp * 3.0 + vec2(TIME * 0.08, 0.0), 2);\n\t}\n\tfloat c = fbm2(q + warp * 1.8, detail + 2);\n\tfloat crust = smoothstep(0.47, 0.53, c);\n\t// Hot seam just outside each floe.\n\tfloat rim = smoothstep(0.41, 0.47, c) * (1.0 - crust);\n\tfloat pulse = 0.9 + 0.1 * sin(TIME * 1.2 + c * 14.0);\n\tvec3 molten = mix(vec3(0.85, 0.12, 0.01), vec3(1.0, 0.45, 0.06), flow);\n\tvec3 crust_col = mix(vec3(0.02, 0.01, 0.008), vec3(0.06, 0.025, 0.015), noise2(p * 0.04));\n\tALBEDO = mix(molten * 0.25, crust_col, crust);\n\tEMISSION = molten * (1.0 - crust) * (0.8 + rim * 1.4) * pulse;\n\tROUGHNESS = 0.85;\n}\n"


const ICE_SHADER := "\nshader_type spatial;\nrender_mode cull_back, shadows_disabled;\n\nuniform int detail = 1;\n\nvarying vec3 wp;\n\n__NOISE__\n\nvoid vertex() {\n\twp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nvoid fragment() {\n\tvec2 p = wp.xz;\n\tfloat n = fbm2(p * 0.012, detail + 2);\n\tvec3 col = mix(vec3(0.03, 0.12, 0.22), vec3(0.18, 0.38, 0.52), n);\n\tfloat dust = smoothstep(0.5, 0.68, fbm2(p * 0.005 + 3.0, 3));\n\tif (detail > 0) {\n\t\tfloat e = voronoi_edge(p * 0.02);\n\t\tfloat crack = 1.0 - smoothstep(0.0, 0.035, e);\n\t\tcol = mix(col, vec3(0.55, 0.68, 0.8), crack * 0.7);\n\t}\n\tcol = mix(col, vec3(0.62, 0.68, 0.77), dust);\n\tALBEDO = col;\n\tROUGHNESS = mix(0.08, 0.75, dust);\n\tSPECULAR = 0.6;\n}\n"


const WATER_SHADER := "\nshader_type spatial;\nrender_mode cull_back, shadows_disabled;\n\nuniform int detail = 1;\n\nvarying vec3 wp;\n\n__NOISE__\n\nvoid vertex() {\n\twp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nvoid fragment() {\n\tvec2 p = wp.xz;\n\tfloat n = fbm2(p * 0.008 + TIME * 0.01, 2);\n\tALBEDO = mix(vec3(0.015, 0.06, 0.08), vec3(0.03, 0.14, 0.16), n);\n\tif (detail > 0) {\n\t\tvec2 q = p * 0.12 + vec2(TIME * 0.4, TIME * 0.15);\n\t\tfloat h0 = fbm2(q, detail + 1);\n\t\tfloat hx = fbm2(q + vec2(0.4, 0.0), detail + 1);\n\t\tfloat hz = fbm2(q + vec2(0.0, 0.4), detail + 1);\n\t\tvec3 wn = normalize(vec3((h0 - hx) * 3.0, 1.0, (h0 - hz) * 3.0));\n\t\tNORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);\n\t}\n\tROUGHNESS = 0.12;\n\tSPECULAR = 0.7;\n}\n"


const CLOUD_SHADER := "\nshader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n\nuniform vec3 color_lit = vec3(1.0);\nuniform vec3 color_shade = vec3(0.6);\nuniform float cover = 0.55;\nuniform float opacity = 0.8;\nuniform float scale = 0.015;\nuniform vec2 wind = vec2(2.0, 0.5);\nuniform float seed = 0.0;\nuniform int octaves = 3;\nuniform float fade_radius = 600.0;\n\nvarying vec3 wp;\n\n__NOISE__\n\nvoid vertex() {\n\twp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n\nvoid fragment() {\n\tvec2 p = (wp.xz + wind * TIME) * scale + vec2(seed);\n\tfloat n = fbm2(p, octaves);\n\tfloat a = smoothstep(cover, cover + 0.2, n);\n\tif (a < 0.003) {\n\t\tdiscard;\n\t}\n\tALBEDO = mix(color_shade, color_lit, smoothstep(cover, cover + 0.4, n));\n\tALPHA = a * opacity * (1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(wp.xz)));\n}\n"


var world: WorldTheme.Kind = WorldTheme.Kind.WINDY


var rim := 40.0

var _p: Dictionary
var _hills := FastNoiseLite.new()
var _peaks := FastNoiseLite.new()
var _patches := FastNoiseLite.new()
var _detail := 1
static var _shader_cache := {}


var build_in_steps := false

func _ready() -> void:
	_p = WORLDS[world]
	var seed_base: int = _p["seed"]
	_hills.seed = seed_base
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.004
	_hills.fractal_octaves = 4
	_peaks.seed = seed_base + 1
	_peaks.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_peaks.frequency = 0.003
	_peaks.fractal_octaves = 3
	_patches.seed = seed_base + 2
	_patches.frequency = 0.008
	_patches.fractal_octaves = 2

	if not build_in_steps:
		for step in steps():
			step.call()


func steps() -> Array[Callable]:
	var detail: int = clampi(int(Settings.quality().get("world_detail", 1)), 0, 2)
	_detail = detail
	return [_build_terrain.bind(detail), _build_liquid.bind(detail), _build_props,
			_build_clouds.bind(detail)]

static func _shader(key: String, code: String) -> Shader:
	if not _shader_cache.has(key):
		var s := Shader.new()
		s.code = code.replace("__NOISE__", NOISE_LIB)
		_shader_cache[key] = s
	return _shader_cache[key]

static func _material(key: String, code: String, detail: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(key, code)
	mat.set_shader_parameter("detail", detail)
	return mat

static func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	if world == WorldTheme.Kind.SNOW:
		return _glacier_height(x, z, r)
	var y: float = _p["floor"]
	y += float(_p["mound"]) * (1.0 - smoothstep(60.0, 220.0, r))
	y += _hills.get_noise_2d(x, z) * float(_p["rough"]) * smoothstep(20.0, 80.0, r)
	var ridge := smoothstep(280.0, 700.0, r)
	if ridge > 0.0:
		y += float(_p["ridge"]) * ridge * (0.45 + 0.55 * (_peaks.get_noise_2d(x, z) * 0.5 + 0.5))
	return y


func _glacier_height(x: float, z: float, r: float) -> float:
	var edge := rim + Arena.GLACIER_CAP
	var plateau := -1.8 + _hills.get_noise_2d(x, z) * float(_p["rough"]) * smoothstep(edge, edge + 60.0, r)

	plateau += float(_p["ridge"]) * smoothstep(280.0, 700.0, r) * (0.45 + 0.55 * (_peaks.get_noise_2d(x, z) * 0.5 + 0.5))

	return lerpf(float(_p["floor"]), plateau, smoothstep(edge - 22.0, edge - 8.0, r))

func _normal_at(x: float, z: float) -> Vector3:
	var e := 4.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e,
			height(x, z - e) - height(x, z + e)).normalized()


func _ground_color(x: float, y: float, z: float, n: Vector3) -> Color:
	var liquid: float = _p["liquid"]
	var patch := _patches.get_noise_2d(x, z) * 0.5 + 0.5
	var steep := 1.0 - smoothstep(0.62, 0.85, n.y)
	var above := y - liquid
	match world:
		WorldTheme.Kind.LAVA:
			var basalt := Color(0.025, 0.019, 0.016).lerp(Color(0.07, 0.05, 0.04), patch)
			var ash := Color(0.12, 0.105, 0.1)
			var c := basalt.lerp(ash, (1.0 - steep) * smoothstep(15.0, 70.0, above) * 0.5)

			return c.lerp(Color(0.22, 0.05, 0.015), 1.0 - smoothstep(0.0, 8.0, above))
		WorldTheme.Kind.SNOW:
			var snow := Color(0.5, 0.56, 0.66).lerp(Color(0.66, 0.71, 0.8), patch)
			var ice := Color(0.12, 0.26, 0.42).lerp(Color(0.3, 0.45, 0.6), patch)
			return snow.lerp(ice, steep * 0.85)

	var grass := Color(0.045, 0.13, 0.025).lerp(Color(0.12, 0.24, 0.045), patch)
	if patch > 0.72:
		grass = grass.lerp(Color(0.24, 0.22, 0.07), 0.5)
	var rock := Color(0.1, 0.085, 0.065).lerp(Color(0.2, 0.17, 0.13), patch)
	var c := grass.lerp(rock, steep)
	c = c.lerp(Color(0.7, 0.72, 0.76), smoothstep(-85.0, -65.0, y) * (1.0 - steep * 0.6))
	return c.lerp(Color(0.16, 0.14, 0.08), 1.0 - smoothstep(0.3, 1.5, above))

func _build_terrain(detail: int) -> void:
	var rings: int = GRID[detail][0]
	var segs: int = GRID[detail][1]
	var total := (rings + 1) * segs
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(total)
	normals.resize(total)
	colors.resize(total)

	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for s in segs:
		cs.append(cos(TAU * s / segs))
		sn.append(sin(TAU * s / segs))
	for i in rings + 1:
		var r := TERRAIN_RADIUS * pow(float(i) / rings, 1.7)
		for s in segs:
			var x := cs[s] * r
			var z := sn[s] * r
			verts[i * segs + s] = Vector3(x, height(x, z), z)

	for i in rings + 1:
		for s in segs:
			var k := i * segs + s
			var n := Vector3.UP
			if i > 0:
				var tangent := verts[i * segs + (s + 1) % segs] - verts[i * segs + (s - 1 + segs) % segs]
				var radial := verts[mini(i + 1, rings) * segs + s] - verts[(i - 1) * segs + s]
				n = tangent.cross(radial).normalized()
				if n.y < 0.0:
					n = -n
			normals[k] = n
			var v := verts[k]
			colors[k] = _ground_color(v.x, v.y, v.z, n)
	indices.resize(rings * segs * 6)
	var o := 0
	for i in rings:
		for s in segs:
			var a := i * segs + s
			var b := i * segs + (s + 1) % segs
			var c := (i + 1) * segs + s
			var d := (i + 1) * segs + (s + 1) % segs

			indices[o] = a
			indices[o + 1] = c
			indices[o + 2] = b
			indices[o + 3] = b
			indices[o + 4] = c
			indices[o + 5] = d
			o += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := _material("terrain", TERRAIN_SHADER, detail)
	mat.set_shader_parameter("style", int(world))
	mat.set_shader_parameter("liquid", float(_p["liquid"]))
	add_child(_instance(mesh, mat))

func _build_liquid(detail: int) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * TERRAIN_RADIUS * 2.0
	var mat: ShaderMaterial
	match world:
		WorldTheme.Kind.LAVA:
			mat = _material("lava", LAVA_SHADER, detail)
		WorldTheme.Kind.SNOW:
			mat = _material("ice", ICE_SHADER, detail)
		_:
			mat = _material("water", WATER_SHADER, detail)
	var mi := _instance(plane, mat)
	mi.position.y = _p["liquid"]
	add_child(mi)


static func _cone(radius: float, h: float, base_y: float, segments: int, color: Color,
		st: SurfaceTool) -> void:
	var tip := Vector3(0, base_y + h, 0)
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
		var nrm := (p1 - tip).cross(p0 - tip).normalized()
		st.set_color(color)
		st.set_normal(nrm)
		st.add_vertex(tip)
		st.add_vertex(p0)
		st.add_vertex(p1)


static func _pine_mesh(foliage: Color, cap: Color, sides := 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(0.06, 0.3, 0.0, 5, Color(0.12, 0.07, 0.035), st)
	_cone(0.32, 0.55, 0.15, sides, foliage, st)
	_cone(0.22, 0.45, 0.5, sides, cap, st)
	return st.commit()

static func _spire_mesh(base := Color(0.05, 0.035, 0.03)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bottom := 0.5
	var top := 0.22
	for s in 6:
		var a0 := TAU * s / 6.0
		var a1 := TAU * (s + 1) / 6.0
		var b0 := Vector3(cos(a0) * bottom, -0.3, sin(a0) * bottom)
		var b1 := Vector3(cos(a1) * bottom, -0.3, sin(a1) * bottom)
		var t0 := Vector3(cos(a0) * top, 1.0, sin(a0) * top)
		var t1 := Vector3(cos(a1) * top, 1.0, sin(a1) * top)
		var nrm := (t0 - b0).cross(b1 - b0).normalized()
		if nrm.dot(b0 + b1) < 0.0:
			nrm = -nrm
		st.set_color(base)
		st.set_normal(nrm)
		for v: Vector3 in [b0, b1, t0, b1, t1, t0]:
			st.add_vertex(v)
		st.set_normal(Vector3.UP)
		for v: Vector3 in [t0, t1, Vector3(0, 1.05, 0)]:
			st.add_vertex(v)
	return st.commit()


func _scatter(rng: RandomNumberGenerator, count: int, rmin: float, rmax: float,
		smin: float, smax: float, ok: Callable, sink := 0.0, squash := 1.0,
		yrange := Vector2(-INF, INF)) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var tries := count * 5
	while out.size() < count and tries > 0:
		tries -= 1
		var r := sqrt(lerpf(rmin * rmin, rmax * rmax, rng.randf()))
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		var y := height(x, z)
		if y < yrange.x or y > yrange.y:
			continue
		var n := _normal_at(x, z)
		if not ok.call(x, y, z, n):
			continue
		var s := rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * squash, s))
		out.append(Transform3D(basis, Vector3(x, y - sink * s, z)))
	return out

func _multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D],
		tint_from := Color.WHITE, tint_to := Color.WHITE, seed := 0) -> void:
	if xforms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tint_from.lerp(tint_to, rng.randf()))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

static func _vertex_color_mat(rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m

func _build_props() -> void:
	var k: float = PROP_SCALE[Settings.scenery]
	var liquid: float = _p["liquid"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_p["seed"]) * 977
	var forest := _patches
	match world:
		WorldTheme.Kind.LAVA:

			var spires := _scatter(rng, int(160 * k), 80.0, 450.0, 16.0, 45.0,
					func(_x: float, _y: float, _z: float, _n: Vector3) -> bool: return true,
					0.0, 1.0, Vector2(-INF, liquid + 10.0))

			for i in spires.size():
				var t := spires[i]
				spires[i] = Transform3D(t.basis * Basis.from_scale(Vector3(0.45, 1.0, 0.45)),
						Vector3(t.origin.x, minf(t.origin.y, liquid), t.origin.z))
			_multimesh(_spire_mesh(), _vertex_color_mat(), spires,
					Color(0.8, 0.8, 0.8), Color(1.4, 1.2, 1.1), 3)
		WorldTheme.Kind.SNOW:

			var seracs := _scatter(rng, int(260 * k), rim + GLACIER_CLEAR, 420.0, 2.5, 7.0,
					func(x: float, _y: float, z: float, _n: Vector3) -> bool:
						return forest.get_noise_2d(x, z) > -0.2,
					0.15, 1.0, Vector2(-6.0, INF))
			for i in seracs.size():
				var t := seracs[i]
				var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
						rng.randf_range(0.05, 0.35))
				seracs[i] = Transform3D(lean * t.basis * Basis.from_scale(Vector3(1.6, 1.0, 1.6)),
						t.origin)
			var ice := StandardMaterial3D.new()
			ice.vertex_color_use_as_albedo = true
			ice.roughness = 0.25
			_multimesh(_spire_mesh(Color(0.26, 0.45, 0.66)), ice, seracs, Color(0.8, 0.85, 0.9), Color(1.15, 1.15, 1.1), 5)
		_:

			var pines := _scatter(rng, int(2400 * k), 90.0, 500.0, 6.0, 11.0,
					func(x: float, _y: float, z: float, n: Vector3) -> bool:
						return n.y > 0.8 and forest.get_noise_2d(x, z) < 0.05,
					0.0, 1.0, Vector2(liquid + 2.5, -95.0))
			_multimesh(_pine_mesh(Color(0.05, 0.16, 0.05), Color(0.07, 0.2, 0.06), PROP_SIDES[_detail]),
					_vertex_color_mat(), pines, Color(0.75, 0.85, 0.75), Color(1.15, 1.1, 1.0), 7)


func _build_clouds(detail: int) -> void:
	var layers: Array = _p["clouds"]
	var count: int = mini(CLOUD_LAYERS[detail], layers.size())
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 1300.0
	for i in count:
		var spec: Array = layers[i]
		var mat := ShaderMaterial.new()
		mat.shader = _shader("cloud", CLOUD_SHADER)
		mat.set_shader_parameter("color_lit", _p["cloud_lit"])
		mat.set_shader_parameter("color_shade", _p["cloud_shade"])
		mat.set_shader_parameter("cover", spec[1])
		mat.set_shader_parameter("opacity", spec[2])
		mat.set_shader_parameter("scale", spec[3])

		mat.set_shader_parameter("wind", (_p["wind"] as Vector2) * (1.0 - 0.25 * i))
		mat.set_shader_parameter("seed", 13.7 * (i + 1))
		mat.set_shader_parameter("octaves", CLOUD_OCTAVES[detail])

		mat.render_priority = count - i
		var mi := _instance(plane, mat)
		mi.position.y = spec[0]
		add_child(mi)
