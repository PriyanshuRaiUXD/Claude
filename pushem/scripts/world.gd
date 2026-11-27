class_name WorldTheme
extends RefCounted


enum Kind {LAVA, SNOW, WINDY}

const NAMES := {
	Kind.LAVA: "Lava",
	Kind.SNOW: "Snow",
	Kind.WINDY: "Windy",
}


const PALETTES := {
	Kind.LAVA: {
		"shader": "res://shaders/lava.gdshader",

		"sky_top": Color(0.42, 0.16, 0.08),
		"sky_horizon": Color(0.85, 0.36, 0.12),
		"sky_ground": Color(0.4, 0.09, 0.02),
		"sun": Color(1.0, 0.8, 0.6),
		"sun_energy": 1.0,
		"ambient": Color(1.0, 0.55, 0.3),
		"ambient_energy": 0.45,
		"lite_bg": Color(0.35, 0.06, 0.02),

		"fog": Color(0.2, 0.05, 0.015),
		"fog_height": -20.0,
		"fog_height_density": 0.006,
		"grade": Vector3(1.0, 1.08, 1.12),
		"exposure": 1.0,
		"glow_threshold": 0.95,
		"glow_intensity": 1.1,
		"swatch": Color(1.0, 0.5, 0.12),
	},
	Kind.SNOW: {
		"shader": "res://shaders/snow.gdshader",
		"sky_top": Color(0.38, 0.55, 0.85),
		"sky_horizon": Color(0.78, 0.85, 0.94),
		"sky_ground": Color(0.6, 0.68, 0.78),
		"sun": Color(0.95, 0.97, 1.0),
		"sun_energy": 0.95,
		"ambient": Color(0.7, 0.8, 0.95),
		"ambient_energy": 0.4,
		"lite_bg": Color(0.5, 0.68, 0.82),
		"fog": Color(0.38, 0.5, 0.66),
		"fog_height": -20.0,
		"fog_height_density": 0.005,
		"grade": Vector3(1.0, 1.08, 0.95),
		"exposure": 0.85,
		"glow_threshold": 1.5,
		"glow_intensity": 0.6,
		"swatch": Color(0.78, 0.92, 1.0),
	},
	Kind.WINDY: {
		"shader": "res://shaders/cliff_wind.gdshader",
		"sky_top": Color(0.32, 0.52, 0.88),
		"sky_horizon": Color(0.75, 0.83, 0.92),
		"sky_ground": Color(0.24, 0.32, 0.17),
		"sun": Color(1.0, 0.98, 0.92),
		"sun_energy": 1.15,
		"ambient": Color(0.65, 0.72, 0.85),
		"ambient_energy": 0.4,
		"lite_bg": Color(0.2, 0.36, 0.15),
		"fog": Color(0.42, 0.55, 0.62),
		"fog_height": -20.0,
		"fog_height_density": 0.0045,
		"grade": Vector3(1.0, 1.08, 1.15),
		"exposure": 1.0,
		"glow_threshold": 1.2,
		"glow_intensity": 0.7,
		"swatch": Color(0.62, 0.78, 0.98),
	},
}


const MENU_BACKDROP := Kind.WINDY
const MENU_ACCENT := Color(0.93, 0.95, 0.98)
const MENU_DIM := Color(0.66, 0.75, 0.9)
const MENU_PANEL := Color(0.09, 0.13, 0.21, 0.74)
const MENU_BUTTON := Color(0.16, 0.22, 0.33, 0.88)
const MENU_FIELD := Color(0.06, 0.09, 0.15, 0.9)

static var _shaders := {}

static func shader_for(kind: Kind) -> Shader:
	if not _shaders.has(kind):
		_shaders[kind] = load(PALETTES[kind]["shader"]) as Shader
	return _shaders[kind]


static func make_backdrop(kind: Kind) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := shader_for(kind)
	if shader != null:
		rect.material = _material(shader)
	else:
		push_warning("WorldTheme: shader for %s failed to load" % NAMES[kind])
		rect.color = PALETTES[kind]["lite_bg"]
	return rect


static func _material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("octaves", Settings.quality()["octaves"])
	return mat


static func retarget_backdrop(rect: ColorRect, kind: Kind) -> void:
	var shader := shader_for(kind)
	if shader != null:
		rect.material = _material(shader)


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = MENU_PANEL
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 18
	sb.content_margin_bottom = 22
	return sb

static func _box(color: Color, radius := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func style_button(b: Button, tint := MENU_ACCENT) -> void:
	var normal := _box(MENU_BUTTON)
	var hover := _box(MENU_BUTTON.lightened(0.12))
	var pressed := _box(Color(tint.r, tint.g, tint.b, 0.92))
	pressed.border_width_bottom = 0
	var disabled := _box(Color(MENU_BUTTON.r, MENU_BUTTON.g, MENU_BUTTON.b, 0.4))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_hover_color", tint.lightened(0.2))
	b.add_theme_color_override("font_disabled_color", Color(tint, 0.35))

	var on_fill := Color(0.06, 0.09, 0.15) if tint.get_luminance() > 0.55 else Color.WHITE
	b.add_theme_color_override("font_pressed_color", on_fill)
	b.add_theme_color_override("font_hover_pressed_color", on_fill)
	b.add_theme_color_override("font_focus_color", tint)

static func style_line_edit(e: LineEdit) -> void:
	var box := _box(MENU_FIELD)
	e.add_theme_stylebox_override("normal", box)
	e.add_theme_stylebox_override("focus", box)
	e.add_theme_color_override("font_color", MENU_ACCENT)
	e.add_theme_color_override("caret_color", MENU_ACCENT)

static func style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = MENU_FIELD
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = MENU_DIM
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)


static func style_tree(node: Node) -> void:
	for child in node.get_children():
		if child is Button and not child.has_theme_stylebox_override("normal"):
			style_button(child)
		elif child is LineEdit:
			style_line_edit(child)
		elif child is HSlider:
			style_slider(child)
		style_tree(child)

static func title_label(text: String, size := 60) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", MENU_ACCENT)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.14, 0.8))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
