class_name UiKit
extends RefCounted


const INK := Color(0.04, 0.05, 0.12)
const YELLOW := Color(1.0, 0.8, 0.1)
const BLUE := Color(0.22, 0.6, 1.0)
const GREEN := Color(0.32, 0.85, 0.36)
const RED := Color(0.95, 0.3, 0.3)
const PORTRAIT_DIR := "res://assets/portraits/"

static var _custom_avatar: Texture2D


static func title(text: String, size := 56, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, int(size * 0.16)))
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, int(size * 0.08)))
	l.add_theme_constant_override("shadow_outline_size", maxi(6, int(size * 0.16)))
	return l


static func label(text: String, size := 24, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(4, int(size * 0.22)))
	return l

static func _lip_box(fill: Color, lip: float, radius := 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.shadow_color = INK
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, lip)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8 + (6.0 - lip)
	sb.content_margin_bottom = 8 + lip
	return sb


static func chunky(text: String, fill: Color, font_size := 40,
		min_size := Vector2(240, 100), sub := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	style_chunky(b, fill, font_size)
	if not sub.is_empty():

		b.text = ""
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", -4)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_bottom = -6
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		for line: Array in [[text, font_size, Color.WHITE], [sub, int(font_size * 0.5),
				Color(1, 1, 1, 0.92)]]:
			var l := label(line[0], line[1], line[2])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(l)
	return b

static func style_chunky(b: Button, fill: Color, font_size := 40) -> void:
	b.add_theme_stylebox_override("normal", _lip_box(fill, 7.0))
	b.add_theme_stylebox_override("hover", _lip_box(fill.lightened(0.12), 7.0))
	b.add_theme_stylebox_override("pressed", _lip_box(fill.darkened(0.1), 2.0))
	b.add_theme_stylebox_override("hover_pressed", _lip_box(fill.darkened(0.1), 2.0))
	b.add_theme_stylebox_override("disabled", _lip_box(Color(0.42, 0.45, 0.52), 7.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.8, 0.82, 0.86))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", maxi(6, int(font_size * 0.2)))


static func pulse(c: Control, amount := 0.04, period := 1.6) -> void:
	_center_pivot(c)
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tw.tween_property(c, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func wobble(c: Control, degrees := 2.0, period := 3.0) -> void:
	_center_pivot(c)
	c.rotation_degrees = -degrees
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "rotation_degrees", degrees, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tw.tween_property(c, "rotation_degrees", -degrees, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func pop_in(c: Control) -> void:
	_center_pivot(c)
	c.scale = Vector2.ONE * 0.85
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tw.tween_property(c, "modulate:a", 1.0, 0.15)

static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	if not c.resized.is_connected(_on_resized.bind(c)):
		c.resized.connect(_on_resized.bind(c))

static func _on_resized(c: Control) -> void:
	c.pivot_offset = c.size / 2.0


static func portrait(id: String) -> Texture2D:
	var path := PORTRAIT_DIR + id + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func custom_avatar() -> Texture2D:
	if _custom_avatar == null and FileAccess.file_exists(Settings.AVATAR_PATH):
		var img := Image.load_from_file(Settings.AVATAR_PATH)
		if img != null and not img.is_empty():
			_custom_avatar = ImageTexture.create_from_image(img)
	return _custom_avatar

static func reload_custom_avatar() -> void:
	_custom_avatar = null


static func avatar_texture(fighter: String) -> Texture2D:
	if Settings.avatar == Settings.AVATAR_CUSTOM and custom_avatar() != null:
		return custom_avatar()
	if Characters.valid(Settings.avatar):
		return portrait(Settings.avatar)
	return portrait(fighter)


static func avatar_tint(id: String) -> Color:
	if Characters.valid(id):
		return (PlayerPawn.STATS[Characters.class_of(id)]["color"] as Color).lightened(0.15)
	return Color(0.2, 0.3, 0.45)


class Avatar:
	extends Panel

	var _pic: TextureRect
	var _box: StyleBoxFlat

	func _init(side := 96.0) -> void:
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = StyleBoxFlat.new()
		_box.set_corner_radius_all(int(side * 0.18))
		_box.set_border_width_all(maxi(3, int(side * 0.045)))
		_box.border_color = UiKit.INK
		_box.bg_color = Color(0.2, 0.3, 0.45)
		add_theme_stylebox_override("panel", _box)
		_pic = TextureRect.new()
		_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := float(_box.border_width_left)
		_pic.offset_left = inset
		_pic.offset_top = inset
		_pic.offset_right = -inset
		_pic.offset_bottom = -inset
		_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_pic)

	func show_texture(tex: Texture2D, tint: Color) -> void:
		_pic.texture = tex
		_box.bg_color = tint

	func set_border(color: Color) -> void:
		_box.border_color = color

	func show_profile(fighter: String) -> void:
		var custom := Settings.avatar == Settings.AVATAR_CUSTOM and UiKit.custom_avatar() != null
		var id := fighter if not Characters.valid(Settings.avatar) else Settings.avatar
		show_texture(UiKit.avatar_texture(fighter),
				Color(0.12, 0.16, 0.24) if custom else UiKit.avatar_tint(id))


class IconButton:
	extends Button

	var kind := "close"

	func _init(icon_kind := "close", side := 76.0) -> void:
		kind = icon_kind
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(side, side)
		size = custom_minimum_size

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var down := is_pressed()
		var lip := 2.0 if down else 6.0
		var fill := UiKit.RED if kind == "close" else Color(0.2, 0.32, 0.55)
		if is_hovered() and not down:
			fill = fill.lightened(0.12)
		var top := c + Vector2(0, -3.0 + (6.0 - lip) * 0.5)
		draw_circle(top + Vector2(0, lip), r - 2.0, UiKit.INK)
		draw_circle(top, r - 2.0, UiKit.INK)
		draw_circle(top, r - 6.0, fill)
		var w := Color.WHITE
		if kind == "close":
			var k := r * 0.36
			for d: Vector2 in [Vector2(k, k), Vector2(k, -k)]:
				draw_line(top - d, top + d, UiKit.INK, r * 0.34, true)
			for d: Vector2 in [Vector2(k, k), Vector2(k, -k)]:
				draw_line(top - d, top + d, w, r * 0.2, true)
		else:
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var side := d.orthogonal() * r * 0.12
				draw_colored_polygon(PackedVector2Array([top + d * r * 0.3 - side,
						top + d * r * 0.62 - side, top + d * r * 0.62 + side,
						top + d * r * 0.3 + side]), w)
			draw_circle(top, r * 0.42, w)
			draw_circle(top, r * 0.18, fill)


static func corner_close(parent: Control, on_press: Callable) -> IconButton:
	var b := IconButton.new("close")
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2(18, 16)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func close_on_outside_tap(modal: Control, panel: Control, on_close: Callable) -> void:
	for child in modal.get_children():
		if child is ColorRect or child is CenterContainer:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state := {"outside": false}
	modal.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var at := modal.get_global_transform() * mb.position
		var outside := not panel.get_global_rect().has_point(at)
		if mb.pressed:
			state["outside"] = outside
		elif state["outside"] and outside:
			state["outside"] = false
			modal.accept_event()
			on_close.call())
