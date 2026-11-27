class_name Hud
extends CanvasLayer


signal use_pressed
signal menu_pressed

var slot: PowerupSlot

var _timer_label: Label
var _lives_label: Label
var _alive_label: Label
var _announce_label: Label
var _powerup_label: Label
var _fps_label: Label
var _fps_accum := 0.0
var _announce_tween: Tween
var _feed: VBoxContainer
var _ko_label: Label
var _ko_tween: Tween

func _ready() -> void:

	_timer_label = _make_label(64, Color.WHITE)
	_place(_timer_label, Control.PRESET_CENTER_TOP, -100, 8, 100, 90)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_lives_label = _make_label(40, Color(1.0, 0.45, 0.5))
	_place(_lives_label, Control.PRESET_TOP_LEFT, 18, 10, 318, 70)

	_alive_label = _make_label(40, Color(0.75, 0.85, 1.0))
	_place(_alive_label, Control.PRESET_TOP_RIGHT, -400, 10, -98, 70)
	_alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_announce_label = _make_label(110, Color.WHITE)
	_place(_announce_label, Control.PRESET_CENTER, -560, -90, 560, 90)
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announce_label.modulate.a = 0.0

	_fps_label = _make_label(24, Color(0.75, 1.0, 0.75))
	_place(_fps_label, Control.PRESET_TOP_RIGHT, -400, 62, -98, 96)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.visible = Settings.show_fps

	_powerup_label = _make_label(30, Color(1.0, 0.85, 0.4))
	_place(_powerup_label, Control.PRESET_CENTER_BOTTOM, -470, -64, 470, -14)
	_powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_feed, Control.PRESET_TOP_LEFT, 18, 74, 438, 190)
	add_child(_feed)

	_ko_label = _make_label(76, Color(1.0, 0.82, 0.2))
	_place(_ko_label, Control.PRESET_CENTER_TOP, -300, 104, 300, 200)
	_ko_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ko_label.modulate.a = 0.0

	slot = PowerupSlot.new()

	var size := 124.0
	_place(slot, Control.PRESET_BOTTOM_RIGHT, -24.0 - size, -250.0 - size, -24.0, -250.0)
	slot.pressed.connect(func() -> void: use_pressed.emit())
	add_child(slot)

	var gear := GearButton.new()
	_place(gear, Control.PRESET_TOP_RIGHT, -84, 12, -16, 80)
	gear.pressed.connect(func() -> void: menu_pressed.emit())
	add_child(gear)

func _process(delta: float) -> void:
	if not _fps_label.visible:
		return
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _place(c: Control, preset: Control.LayoutPreset, left: float, top: float,
		right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom

func set_timer_text(text: String, warning := false) -> void:
	_timer_label.text = text
	_timer_label.add_theme_color_override(
		"font_color", Color(1.0, 0.35, 0.3) if warning else Color.WHITE)

func set_lives(count: int) -> void:
	if count < 0:
		_lives_label.text = ""
	else:
		_lives_label.text = "♥".repeat(count) if count > 0 else "☠"


func set_powerup(text: String) -> void:
	if _powerup_label.text != text:
		_powerup_label.text = text


func set_slot(held: int, active: int, fraction: float, usable: bool,
		cancelable: bool) -> void:
	slot.update(held, active, fraction, usable, cancelable)

func set_alive(count: int, total: int) -> void:
	_alive_label.text = "%d/%d alive" % [count, total]

## One line in the knockout feed: "Rocky  KO  Bo".
func feed(attacker: String, victim: String, mine := false) -> void:
	var l := Label.new()
	l.text = "%s  KO  %s" % [attacker, victim]
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2) if mine else Color(0.92, 0.95, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(l)
	while _feed.get_child_count() > 3:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## Punchy centre pop for the local player's knockouts.
func ko_popup(count: int) -> void:
	if _ko_tween != null:
		_ko_tween.kill()
	_ko_label.text = "KO!" if count <= 1 else "KO x%d!" % count
	_ko_label.pivot_offset = _ko_label.size / 2.0
	_ko_label.scale = Vector2.ONE * 1.7
	_ko_label.modulate.a = 1.0
	_ko_tween = create_tween()
	_ko_tween.tween_property(_ko_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ko_tween.tween_interval(0.9)
	_ko_tween.tween_property(_ko_label, "modulate:a", 0.0, 0.35)


func announce(text: String, hold_secs := 1.6) -> void:
	if _announce_tween != null:
		_announce_tween.kill()
	_announce_label.text = text
	_announce_label.modulate.a = 1.0
	_announce_tween = create_tween()
	_announce_tween.tween_interval(hold_secs)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.5)


class GearButton:
	extends Button

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5
		var hot := is_pressed() or is_hovered()
		draw_circle(c, r, Color(0.06, 0.09, 0.15, 0.85 if hot else 0.7))
		var col := Color(0.93, 0.95, 0.98)
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			var side := d.orthogonal() * r * 0.13
			draw_colored_polygon(PackedVector2Array([c + d * r * 0.42 - side,
					c + d * r * 0.72 - side, c + d * r * 0.72 + side, c + d * r * 0.42 + side]), col)
		draw_circle(c, r * 0.5, col)
		draw_circle(c, r * 0.22, Color(0.06, 0.09, 0.15))


class PowerupSlot:
	extends Button

	var kind := -1
	var active := false
	var cancelable := false
	var fraction := 0.0

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		visible = false

	func update(held: int, running: int, frac: float, usable: bool, can_cancel: bool) -> void:
		var new_kind := held if held >= 0 else running
		var new_active := held < 0 and running >= 0
		visible = new_kind >= 0
		disabled = not can_cancel if new_active else not usable
		if new_kind != kind or new_active != active or can_cancel != cancelable or absf(frac - fraction) > 0.01:

			kind = new_kind
			active = new_active
			cancelable = can_cancel
			fraction = frac
			queue_redraw()

	func _draw() -> void:
		if kind < 0:
			return
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5
		var alpha := 0.55 if active else 1.0
		draw_circle(c, r, Color(0.06, 0.09, 0.15, 0.78))
		if active:
			draw_arc(c, r - 5.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 48,
					Color(0.66, 0.75, 0.9), 7.0, true)
		else:
			draw_arc(c, r - 5.0, 0.0, TAU, 48, Color(1.0, 0.8, 0.3), 6.0, true)
		_draw_icon(c + Vector2(0.0, -10.0), r * 0.42, alpha)
		var font := get_theme_default_font()
		var caption: String = "TAP"
		if active:
			caption = "CANCEL" if cancelable else "ACTIVE"
		draw_string(font, Vector2(0.0, size.y - 22.0), caption,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, alpha))

	func _draw_icon(c: Vector2, s: float, alpha: float) -> void:
		var col: Color = Powerup.COLORS[kind]
		col.a = alpha
		match kind:
			Powerup.Kind.GLOVES:
				draw_rect(Rect2(c - Vector2(s * 0.75, s * 0.8), Vector2(s * 1.4, s * 1.25)), col)
				draw_circle(c + Vector2(s * 0.75, -s * 0.05), s * 0.32, col.lightened(0.15))
				draw_rect(Rect2(c + Vector2(-s * 0.7, s * 0.5), Vector2(s * 1.3, s * 0.4)),
						Color(0.95, 0.9, 0.75, alpha))
			Powerup.Kind.SPIKES:
				for i in 8:
					var a := TAU * i / 8.0
					var d := Vector2(cos(a), sin(a))
					var side := d.orthogonal() * s * 0.22
					draw_colored_polygon(PackedVector2Array([
							c + d * s * 1.15, c + d * s * 0.45 + side, c + d * s * 0.45 - side]),
							Color(0.8, 0.82, 0.86, alpha))
				draw_circle(c, s * 0.6, Color(0.4, 0.42, 0.46, alpha))
			Powerup.Kind.BOMB:
				draw_line(c + Vector2(s * 0.35, -s * 0.6), c + Vector2(s * 0.7, -s * 1.05),
						Color(0.85, 0.78, 0.6, alpha), 4.0)
				draw_circle(c + Vector2(s * 0.75, -s * 1.1), s * 0.18, Color(1.0, 0.6, 0.1, alpha))
				draw_circle(c, s * 0.8, Color(0.1, 0.1, 0.12, alpha))
				draw_arc(c, s * 0.8, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * alpha), 2.0, true)
			Powerup.Kind.DASH:
				draw_colored_polygon(PackedVector2Array([
						c + Vector2(s * 0.25, -s * 1.1), c + Vector2(-s * 0.6, s * 0.1),
						c + Vector2(-s * 0.05, s * 0.1), c + Vector2(-s * 0.3, s * 1.1),
						c + Vector2(s * 0.6, -s * 0.15), c + Vector2(s * 0.05, -s * 0.15)]), col)
			Powerup.Kind.SHOES:

				draw_colored_polygon(PackedVector2Array([
						c + Vector2(-s * 0.75, -s * 0.75), c + Vector2(-s * 0.2, -s * 0.75),
						c + Vector2(-s * 0.05, -s * 0.25), c + Vector2(s * 0.75, -s * 0.05),
						c + Vector2(s * 0.95, s * 0.3), c + Vector2(-s * 0.8, s * 0.3)]), col)
				draw_rect(Rect2(c + Vector2(-s * 0.85, s * 0.3), Vector2(s * 1.85, s * 0.22)),
						Color(0.96, 0.96, 0.98, alpha))
				var spring := Color(1.0, 0.85, 0.25, alpha)
				for i in 3:
					var y := s * (0.62 + 0.18 * i)
					draw_line(c + Vector2(-s * 0.3, y), c + Vector2(s * 0.3, y + s * 0.09), spring, 3.0)
				for i in 3:
					var y := -s * (0.55 - 0.35 * i)
					draw_line(c + Vector2(-s * 1.25, y), c + Vector2(-s * 0.9, y),
							Color(1, 1, 1, 0.7 * alpha), 3.0)
