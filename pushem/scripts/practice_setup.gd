class_name PracticeSetup
extends Control


signal start_requested(map: Arena.Shape, world: WorldTheme.Kind)

var _map: Arena.Shape
var _world: WorldTheme.Kind

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_map = clampi(Settings.last_map, 0, Arena.SHAPE_NAMES.size() - 1) as Arena.Shape
	_world = clampi(Settings.last_world, 0, WorldTheme.NAMES.size() - 1) as WorldTheme.Kind

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -90
	add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.96)
	style.set_border_width_all(4)
	style.border_color = UiKit.INK
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	root.add_child(UiKit.title("PRACTICE", 52, UiKit.YELLOW))
	root.add_child(UiKit.label("You against 3 bots", 22, WorldTheme.MENU_DIM))

	root.add_child(UiKit.label("MAP", 24, WorldTheme.MENU_DIM))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation", 12)
	root.add_child(maps)
	var map_group := ButtonGroup.new()
	for shape: Arena.Shape in Arena.SHAPE_NAMES:
		var b := _toggle(Arena.SHAPE_NAMES[shape], map_group, shape == _map, WorldTheme.MENU_ACCENT)
		b.pressed.connect(func() -> void: _map = shape)
		maps.add_child(b)

	root.add_child(UiKit.label("WORLD", 24, WorldTheme.MENU_DIM))
	var worlds := HBoxContainer.new()
	worlds.add_theme_constant_override("separation", 12)
	root.add_child(worlds)
	var world_group := ButtonGroup.new()
	for kind: WorldTheme.Kind in WorldTheme.NAMES:
		var b := _toggle(WorldTheme.NAMES[kind], world_group, kind == _world,
				WorldTheme.PALETTES[kind]["swatch"])
		b.pressed.connect(func() -> void: _world = kind)
		worlds.add_child(b)

	var go := UiKit.chunky("START", UiKit.YELLOW, 48, Vector2(300, 104))
	go.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	go.offset_left = -324
	go.offset_top = -124
	go.offset_right = -24
	go.offset_bottom = -20
	go.pressed.connect(_start)
	add_child(go)
	UiKit.pulse.call_deferred(go, 0.035)

	UiKit.corner_close(self, close)
	UiKit.close_on_outside_tap(self, panel, close)
	UiKit.pop_in.call_deferred(panel)

func close() -> void:
	queue_free()

func _start() -> void:
	Settings.last_map = _map
	Settings.last_world = _world
	Settings.save()
	start_requested.emit(_map, _world)

func _toggle(text: String, group: ButtonGroup, on: bool, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 30)
	b.custom_minimum_size = Vector2(170, 64)
	WorldTheme.style_button(b, tint)
	return b
