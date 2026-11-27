class_name BrowseScreen
extends Control


var net: Net

signal joined
signal cancelled

var _list: VBoxContainer
var _hint: Label
var _code := ""
var _code_field: Button
var _code_error: Label

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
	root.add_theme_constant_override("separation", 16)
	panel.add_child(root)

	root.add_child(WorldTheme.title_label("JOIN A GAME", 52))

	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 12)
	root.add_child(code_row)

	_code_field = TextEntry.field(34, Vector2(300, 64))
	_code_field.pressed.connect(_edit_code)
	_show_code()
	code_row.add_child(_code_field)
	var go := Button.new()
	go.text = "  Join  "
	go.add_theme_font_size_override("font_size", 32)
	go.custom_minimum_size = Vector2(0, 64)
	WorldTheme.style_button(go, Color(0.45, 0.9, 0.6))
	go.pressed.connect(_join_code)
	code_row.add_child(go)
	_code_error = Label.new()
	_code_error.add_theme_font_size_override("font_size", 22)
	_code_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_code_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_code_error)

	_hint = Label.new()
	_hint.text = "Searching for hosts on your Wi-Fi…"
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.custom_minimum_size = Vector2(620, 200)
	root.add_child(_list)

	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 30)
	back.custom_minimum_size = Vector2(0, 70)
	back.pressed.connect(func() -> void:
		net.stop_browsing()
		cancelled.emit())
	root.add_child(back)

	WorldTheme.style_tree(self)
	net.hosts_updated.connect(_refresh)
	net.start_browsing()

func _edit_code() -> void:
	TextEntry.ask(self, "GAME CODE", _code, func(t: String) -> void:
		_code = t.strip_edges().to_upper()
		_code_error.text = ""
		_show_code()
		if not _code.is_empty():
			_join_code(), 7, "e.g. K7Q-M2P", true, "Join")

func _show_code() -> void:
	_code_field.text = _code if not _code.is_empty() else "GAME CODE"
	_code_field.modulate.a = 1.0 if not _code.is_empty() else 0.6

func _join_code() -> void:
	if _code.is_empty():
		_edit_code()
		return
	var err := net.join_code(_code)
	if err.is_empty():
		joined.emit()
	else:
		_code_error.text = err


func go_back() -> void:
	net.stop_browsing()
	cancelled.emit()

func _refresh(hosts: Dictionary) -> void:
	for child in _list.get_children():
		child.queue_free()
	if hosts.size() > 0:
		_hint.text = "Tap a game to join:"
	for ip: String in hosts:
		var info: Dictionary = hosts[ip]
		var b := Button.new()
		var code := str(info.get("code", ""))
		b.text = "%s's game — %d/%d players%s" % [info["name"], info["players"], info["max"],
				("  ·  " + JoinCode.pretty(code)) if not code.is_empty() else ""]
		b.add_theme_font_size_override("font_size", 30)
		b.custom_minimum_size = Vector2(0, 80)
		WorldTheme.style_button(b, Color(0.45, 0.9, 0.6))
		b.pressed.connect(func() -> void:
			if net.join(ip) == OK:
				joined.emit())
		_list.add_child(b)
