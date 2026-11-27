class_name GameMenu
extends Control


signal resumed
signal exit_to_menu
signal adjust_stick

const SLIDER_WIDTH := 330.0

var paused_match := true

var _main_page: VBoxContainer
var _options_page: VBoxContainer
var _adjust: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.94)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var pages := VBoxContainer.new()
	panel.add_child(pages)

	_main_page = _build_main()
	pages.add_child(_main_page)
	_options_page = _build_options()
	pages.add_child(_options_page)
	show_page(false)
	WorldTheme.style_tree(self)
	UiKit.close_on_outside_tap(self, panel, close)

func show_page(options: bool) -> void:
	_main_page.visible = not options
	_options_page.visible = options


func go_back() -> void:
	if _options_page.visible:
		show_page(false)
	else:
		close()

func close() -> void:
	Settings.save()
	resumed.emit()

func _build_main() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(WorldTheme.title_label("PAUSED" if paused_match else "MENU", 48))
	if not paused_match:
		page.add_child(_note("The match keeps going while this menu is open."))
	page.add_child(_big_button("Resume", Color(0.45, 0.9, 0.6), close))
	page.add_child(_big_button("Options", WorldTheme.MENU_ACCENT,
			func() -> void: show_page(true)))
	page.add_child(_big_button("Exit to main menu", Color(1.0, 0.78, 0.25),
			func() -> void: exit_to_menu.emit()))
	return page

func _build_options() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(WorldTheme.title_label("OPTIONS", 42))

	_slider(page, "Music volume", 0.0, 1.0, 0.05, Settings.music_volume,
			func(v: float) -> void:
				Settings.music_volume = v
				GameAudio.apply_volumes(),
			_percent)
	_slider(page, "Sound volume", 0.0, 1.0, 0.05, Settings.sfx_volume,
			func(v: float) -> void:
				Settings.sfx_volume = v
				GameAudio.apply_volumes()
				GameAudio.play("tick"),
			_percent)
	_slider(page, "Camera zoom", 0.0, 1.0, 0.05, Settings.zoom,
			func(v: float) -> void: Settings.zoom = v,
			func(v: float) -> String:
				if v < 0.05:
					return "Full map"
				if v > 0.95:
					return "Close"
				return "%d%%" % roundi(v * 100.0))
	page.add_child(_note("Full map keeps the whole arena in view; the camera always stays on you."))

	page.add_child(_caption("Joystick"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var group := ButtonGroup.new()
	for mode: int in [Settings.STICK_FLOATING, Settings.STICK_FIXED]:
		var b := Button.new()
		b.text = "Floating" if mode == Settings.STICK_FLOATING else "Fixed"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.stick_mode == mode
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size = Vector2(150, 56)
		WorldTheme.style_button(b)
		b.pressed.connect(func() -> void:
			Settings.stick_mode = mode
			_adjust.disabled = mode != Settings.STICK_FIXED)
		row.add_child(b)
	_adjust = Button.new()
	_adjust.text = "  Adjust position  "
	_adjust.add_theme_font_size_override("font_size", 24)
	_adjust.custom_minimum_size = Vector2(0, 56)
	_adjust.disabled = Settings.stick_mode != Settings.STICK_FIXED
	WorldTheme.style_button(_adjust)
	_adjust.pressed.connect(func() -> void: adjust_stick.emit())
	row.add_child(_adjust)
	page.add_child(_note("Floating: appears where your left thumb lands. Fixed: stays where you put it."))

	page.add_child(_big_button("Back", WorldTheme.MENU_ACCENT, func() -> void: show_page(false)))
	return page


func _big_button(text: String, tint: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.add_theme_font_size_override("font_size", 32)
	b.custom_minimum_size = Vector2(420, 66)
	WorldTheme.style_button(b, tint)
	b.pressed.connect(on_press)
	return b

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	return l

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)

func _slider(parent: VBoxContainer, label_text: String, lo: float, hi: float, step: float,
		value: float, on_change: Callable, fmt: Callable) -> void:
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
	readout.custom_minimum_size = Vector2(120, 0)
	readout.add_theme_font_size_override("font_size", 24)
	readout.add_theme_color_override("font_color", WorldTheme.MENU_ACCENT)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = fmt.call(v))
