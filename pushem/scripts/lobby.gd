class_name LobbyScreen
extends Control


var net: Net
var is_host := false

signal left

var _roster: VBoxContainer
var _start_button: Button
var _status: Label
var _code_label: Label
var _backdrop: ColorRect
var _backdrop_world: WorldTheme.Kind
var _scroll: DragScroll
var _map_buttons := {}
var _world_buttons := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_backdrop_world = net.world
	_backdrop = WorldTheme.make_backdrop(_backdrop_world)
	add_child(_backdrop)

	_scroll = DragScroll.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 10
	_scroll.offset_bottom = -10
	add_child(_scroll)
	var center_box := VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_scroll.add_child(center_box)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.set_border_width_all(4)
	style.border_color = UiKit.INK
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var title := UiKit.title("LOBBY — YOU ARE HOSTING" if is_host else "LOBBY", 48)
	root.add_child(title)
	UiKit.wobble.call_deferred(title, 1.2, 3.6)

	_code_label = UiKit.title("", 46, UiKit.YELLOW)
	root.add_child(_code_label)
	if is_host:
		root.add_child(_note("Friends tap JOIN GAME and type this code (or pick your game from the list)."))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	_roster.custom_minimum_size = Vector2(540, 0)
	left.add_child(_roster)
	if is_host:
		left.add_child(_bot_row())

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	columns.add_child(side)
	if is_host:
		_build_host_controls(side)
	else:
		_build_client_controls(side)

	var room := Control.new()
	room.custom_minimum_size = Vector2(0, 96)
	center_box.add_child(room)

	WorldTheme.style_tree(self)

	UiKit.corner_close(self, go_back)
	if is_host:
		_start_button = UiKit.chunky("START", UiKit.YELLOW, 50, Vector2(300, 104))
		_start_button.pressed.connect(func() -> void: net.start_match())
		UiKit.pulse.call_deferred(_start_button, 0.035)
	else:
		_start_button = null
	var corner: Control = _start_button if is_host else UiKit.title("WAITING FOR HOST…", 32)
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.offset_left = -344
	corner.offset_top = -124
	corner.offset_right = -24
	corner.offset_bottom = -20
	if corner is Label:
		(corner as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		(corner as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(corner)
	net.lobby_changed.connect(_refresh)
	_refresh()


func go_back() -> void:
	for child in get_children():
		if child is CharacterPicker:
			child.queue_free()
			return
	var more := "Everyone in your lobby will be sent back to the menu." if is_host else ""
	ConfirmBox.ask(self, "Leave the lobby?", func() -> void:
		net.leave()
		left.emit(), "Leave", more)


func _guard(action: Callable) -> Callable:
	return func() -> void:
		if not _scroll.just_dragged():
			action.call()

func _build_host_controls(side: VBoxContainer) -> void:
	side.add_child(_caption("Map"))
	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_grid.add_theme_constant_override("h_separation", 10)
	map_grid.add_theme_constant_override("v_separation", 8)
	side.add_child(map_grid)
	var group := ButtonGroup.new()
	for shape: Arena.Shape in Arena.SHAPE_NAMES:
		var b := Button.new()
		b.text = Arena.SHAPE_NAMES[shape]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = shape == net.map_shape
		b.add_theme_font_size_override("font_size", 24)
		b.custom_minimum_size = Vector2(170, 52)
		b.pressed.connect(func() -> void:
			if _scroll.just_dragged():
				_map_buttons[net.map_shape].button_pressed = true
				return
			net.set_map(shape))
		_map_buttons[shape] = b
		map_grid.add_child(b)

	side.add_child(_caption("World"))
	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 10)
	side.add_child(world_row)
	var world_group := ButtonGroup.new()
	for kind: WorldTheme.Kind in WorldTheme.NAMES:
		var b := Button.new()
		b.text = WorldTheme.NAMES[kind]
		b.toggle_mode = true
		b.button_group = world_group
		b.button_pressed = kind == net.world
		b.add_theme_font_size_override("font_size", 24)
		b.custom_minimum_size = Vector2(110, 52)
		WorldTheme.style_button(b, WorldTheme.PALETTES[kind]["swatch"])
		b.pressed.connect(func() -> void:
			if _scroll.just_dragged():
				_world_buttons[net.world].button_pressed = true
				return
			net.set_world(kind))
		_world_buttons[kind] = b
		world_row.add_child(b)

	var play_toggle := CheckButton.new()
	play_toggle.text = "Play on this device"
	play_toggle.button_pressed = net.host_is_player
	play_toggle.add_theme_font_size_override("font_size", 24)
	play_toggle.toggled.connect(func(on: bool) -> void: net.set_host_plays(on))
	side.add_child(play_toggle)

	var lite_toggle := CheckButton.new()
	lite_toggle.text = "Lite rendering"
	lite_toggle.button_pressed = net.lite_render
	lite_toggle.add_theme_font_size_override("font_size", 24)
	lite_toggle.toggled.connect(func(on: bool) -> void: net.lite_render = on)
	side.add_child(lite_toggle)


func _bot_row() -> HBoxContainer:
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 10)
	var add_bot := Button.new()
	add_bot.text = "+ Add bot"
	add_bot.add_theme_font_size_override("font_size", 24)
	add_bot.custom_minimum_size = Vector2(170, 52)
	add_bot.pressed.connect(_guard(func() -> void: net.add_bot()))
	bot_row.add_child(add_bot)
	var clear_bots := Button.new()
	clear_bots.text = "Clear bots"
	clear_bots.add_theme_font_size_override("font_size", 24)
	clear_bots.custom_minimum_size = Vector2(170, 52)
	clear_bots.pressed.connect(_guard(func() -> void: net.remove_bots()))
	bot_row.add_child(clear_bots)
	return bot_row


func _build_client_controls(side: VBoxContainer) -> void:
	side.add_child(_caption("Your fighter"))
	var change := UiKit.chunky("", UiKit.BLUE, 26, Vector2(320, 64))
	var label_it := func() -> void:
		change.text = "%s · CHANGE" % Characters.display_name(net.local_char).to_upper()
	label_it.call()
	change.pressed.connect(_guard(func() -> void:
		_open_picker(net.local_char, func(id: String) -> void:
			Settings.fighter = id
			Settings.save()
			net.set_local_fighter(id)
			label_it.call())))
	side.add_child(change)

func _open_picker(current: String, on_pick: Callable) -> void:
	var picker := CharacterPicker.new()
	picker.current = current
	picker.picked.connect(on_pick)
	add_child(picker)

func _refresh() -> void:
	if net.world != _backdrop_world:
		_backdrop_world = net.world
		WorldTheme.retarget_backdrop(_backdrop, _backdrop_world)
	_code_label.text = ("GAME CODE   " + JoinCode.pretty(net.game_code)) if not net.game_code.is_empty() else ""

	for child in _roster.get_children():
		child.queue_free()
	_roster.add_child(_caption("Players"))
	for id: int in net.players:
		_roster.add_child(_roster_row(id, net.players[id]))
	var n := net.players.size()
	_status.text = "%d / %d players — %s · %s" % [n, Net.MAX_PLAYERS,
			Arena.SHAPE_NAMES[net.map_shape], WorldTheme.NAMES[net.world]]
	if _start_button != null:
		_start_button.disabled = n < 2


func _roster_row(id: int, p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var wclass: int = p["class"]
	var face := UiKit.Avatar.new(48)
	var char_id: String = p.get("char", "")
	face.show_texture(UiKit.portrait(char_id), UiKit.avatar_tint(char_id))
	row.add_child(face)
	var label := Label.new()

	var tag := ("" if is_host else "  [bot]") if p["bot"] else ("  (you)" if id == net.my_id() else "")
	label.text = "%s · %s%s" % [p["name"], Characters.display_name(p.get("char", "")), tag]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color",
			(PlayerPawn.STATS[wclass]["color"] as Color).lightened(0.45))
	label.add_theme_color_override("font_outline_color", UiKit.INK)
	label.add_theme_constant_override("outline_size", 5)
	row.add_child(label)
	if is_host and p["bot"]:
		var change := Button.new()
		change.text = "Change"
		change.add_theme_font_size_override("font_size", 20)
		change.custom_minimum_size = Vector2(104, 44)
		WorldTheme.style_button(change)
		change.pressed.connect(_guard(func() -> void:
			_open_picker(p.get("char", ""), func(char_id: String) -> void:
				net.set_bot_character(id, char_id))))
		row.add_child(change)
		var remove := Button.new()
		remove.text = "Remove"
		remove.add_theme_font_size_override("font_size", 20)
		remove.custom_minimum_size = Vector2(104, 44)
		WorldTheme.style_button(remove, Color(1.0, 0.55, 0.45))
		remove.pressed.connect(_guard(func() -> void: net.remove_bot(id)))
		row.add_child(remove)
	return row

func _caption(text: String) -> Label:
	return UiKit.label(text.to_upper(), 24, WorldTheme.MENU_DIM)

func _note(text: String) -> Label:
	var l := UiKit.label(text, 20, WorldTheme.MENU_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
