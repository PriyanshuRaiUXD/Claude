class_name SettingsScreen
extends Control


signal closed

const SLIDER_WIDTH := 300.0

const QUALITY_HINTS := {
	Settings.Quality.LOW: "For older phones: lower resolution, no shadows, simpler world",
	Settings.Quality.MEDIUM: "Balanced: full resolution, shadows, detailed world",
	Settings.Quality.HIGH: "Sharpest: extra anti-aliasing, fine shadows, richest world",
}
const RECOMMENDED_TINT := Color(0.6, 0.95, 0.65)

var _quality_hint: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(WorldTheme.make_backdrop(WorldTheme.MENU_BACKDROP))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WorldTheme.panel_style())
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	root.add_child(WorldTheme.title_label("SETTINGS", 40))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	root.add_child(columns)
	var left := _column(columns)
	var right := _column(columns)

	left.add_child(_heading("CONTROLS"))
	_slider_row(left, "Map zoom", 0.0, 1.0, 0.05, Settings.zoom,
			func(v: float) -> void: Settings.zoom = v,
			func(v: float) -> String:
				if v < 0.15:
					return "Far"
				if v > 0.85:
					return "Close"
				return "%d%%" % roundi(v * 100.0))
	left.add_child(_small_label("The camera always follows your fighter."))

	left.add_child(_small_label("Left thumb: move stick."))
	left.add_child(_small_label("Right thumb: push — drag to aim, release."))
	left.add_child(_small_label("Powerup button sits above the push stick."))

	left.add_child(_heading("DETAIL"))
	_detail_row(left, "Scenery", Settings.scenery,
			func(v: int) -> void: Settings.scenery = v)
	_detail_row(left, "Effects", Settings.effects,
			func(v: int) -> void: Settings.effects = v)
	left.add_child(_small_label("Lower these for more FPS. Applies next match."))

	right.add_child(_heading("GRAPHICS"))
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 12)
	right.add_child(quality_row)
	var quality_group := ButtonGroup.new()
	var recommended := DeviceProfile.recommended_quality()
	for level: Settings.Quality in Settings.QUALITY_NAMES:
		var b := _choice(Settings.QUALITY_NAMES[level], quality_group, Settings.graphics == level)
		if level == recommended:
			WorldTheme.style_button(b, RECOMMENDED_TINT)
		b.pressed.connect(func() -> void:
			Settings.graphics = level
			Settings.apply_graphics(get_viewport())
			_quality_hint.text = QUALITY_HINTS[level])
		quality_row.add_child(b)
	_quality_hint = _small_label(QUALITY_HINTS[Settings.graphics])
	right.add_child(_quality_hint)

	var rec := _small_label("Recommended for this device: %s" % Settings.QUALITY_NAMES[recommended])
	rec.add_theme_color_override("font_color", RECOMMENDED_TINT)
	right.add_child(rec)
	var why := DeviceProfile.describe()
	if not why.is_empty():
		var device := _small_label(why)
		device.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		device.custom_minimum_size.x = SLIDER_WIDTH + 100
		right.add_child(device)

	right.add_child(_caption("FPS cap"))
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 8)
	right.add_child(fps_row)
	var fps_group := ButtonGroup.new()
	for cap: int in Settings.FPS_CAPS:
		var b := _choice("Max" if cap == 0 else str(cap), fps_group, Settings.fps_cap == cap)
		b.custom_minimum_size = Vector2(72, 46)
		b.pressed.connect(func() -> void:
			Settings.fps_cap = cap
			Settings.apply_graphics(get_viewport()))
		fps_row.add_child(b)
	var show_fps := CheckButton.new()
	show_fps.text = "Show FPS counter in game"
	show_fps.button_pressed = Settings.show_fps
	show_fps.add_theme_font_size_override("font_size", 22)
	show_fps.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	show_fps.add_theme_color_override("font_pressed_color", WorldTheme.MENU_ACCENT)
	show_fps.toggled.connect(func(on: bool) -> void: Settings.show_fps = on)
	right.add_child(show_fps)

	right.add_child(_heading("AUDIO"))
	_slider_row(right, "Music", 0.0, 1.0, 0.05, Settings.music_volume,
			func(v: float) -> void:
				Settings.music_volume = v
				GameAudio.apply_volumes()
				GameAudio.preview_music(),
			_percent)
	_slider_row(right, "Sound", 0.0, 1.0, 0.05, Settings.sfx_volume,
			func(v: float) -> void:
				Settings.sfx_volume = v
				GameAudio.apply_volumes()
				GameAudio.play("tick"),
			_percent)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)

	var reset := Button.new()
	reset.text = "  Reset defaults  "
	reset.add_theme_font_size_override("font_size", 26)
	reset.custom_minimum_size = Vector2(0, 58)
	reset.pressed.connect(func() -> void:
		Settings.reset_defaults()
		GameAudio.apply_volumes()
		Settings.apply_graphics(get_viewport())
		Settings.save()

		var again := SettingsScreen.new()
		again.closed.connect(func() -> void: closed.emit())
		get_parent().add_child(again)
		queue_free())
	row.add_child(reset)

	var back := Button.new()
	back.text = "  Back  "
	back.add_theme_font_size_override("font_size", 32)
	back.custom_minimum_size = Vector2(0, 58)
	back.pressed.connect(func() -> void:
		Settings.save()
		closed.emit())
	row.add_child(back)

	WorldTheme.style_tree(self)


func go_back() -> void:
	Settings.save()
	closed.emit()

func _column(parent: Container) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(SLIDER_WIDTH + 110, 0)
	parent.add_child(col)
	return col

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", WorldTheme.MENU_ACCENT)
	return l

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	return l

func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	return l

func _choice(text: String, group: ButtonGroup, selected: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = selected
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(120, 50)
	WorldTheme.style_button(b)
	return b


func _detail_row(parent: VBoxContainer, label_text: String, value: int,
		on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var caption := _caption(label_text)
	caption.custom_minimum_size = Vector2(96, 0)
	row.add_child(caption)
	var group := ButtonGroup.new()
	for level in 3:
		var b := _choice(["Low", "Med", "High"][level], group, value == level)
		b.custom_minimum_size = Vector2(92, 44)
		b.pressed.connect(func() -> void: on_pick.call(level))
		row.add_child(b)

func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)

func _slider_row(parent: VBoxContainer, label_text: String, lo: float, hi: float,
		step: float, value: float, on_change: Callable, fmt: Callable) -> void:
	parent.add_child(_caption(label_text))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := Label.new()
	readout.text = fmt.call(value)
	readout.add_theme_font_size_override("font_size", 24)
	readout.add_theme_color_override("font_color", WorldTheme.MENU_ACCENT)
	readout.custom_minimum_size = Vector2(90, 0)
	row.add_child(readout)

	slider.value_changed.connect(func(v: float) -> void:
		readout.text = fmt.call(v)
		on_change.call(v))
