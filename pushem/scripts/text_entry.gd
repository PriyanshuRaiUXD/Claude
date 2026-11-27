class_name TextEntry
extends Control


signal done(text: String)

var title := ""
var text := ""
var max_length := 14
var placeholder := ""
var upper := false
var done_text := "Done"

var _edit: LineEdit
var _closed := false


static func ask(parent: Node, box_title: String, current: String, on_done: Callable,
		max_len := 14, hint := "", caps := false, done_label := "Done") -> TextEntry:
	var box := TextEntry.new()
	box.title = box_title
	box.text = current
	box.max_length = max_len
	box.placeholder = hint
	box.upper = caps
	box.done_text = done_label
	box.done.connect(on_done)
	parent.add_child(box)
	return box


static func field(font_size := 28, min_size := Vector2(300, 52)) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = min_size
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	var box := WorldTheme._box(WorldTheme.MENU_FIELD)
	var hot := WorldTheme._box(WorldTheme.MENU_FIELD.lightened(0.12))
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("hover_pressed", hot)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, WorldTheme.MENU_ACCENT)
	return b

func _ready() -> void:
	add_to_group("confirm_box")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and not e.pressed:
			_finish())
	add_child(dim)

	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.98)
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 14
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)
	_edit = LineEdit.new()
	_edit.text = text
	_edit.max_length = max_length
	_edit.placeholder_text = placeholder
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.add_theme_font_size_override("font_size", 40)
	_edit.custom_minimum_size = Vector2(560, 72)
	_edit.select_all_on_focus = true
	WorldTheme.style_line_edit(_edit)
	_edit.text_submitted.connect(func(_t: String) -> void: _finish())
	if upper:
		_edit.text_changed.connect(func(t: String) -> void:
			var caret := _edit.caret_column
			_edit.text = t.to_upper()
			_edit.caret_column = caret)
	row.add_child(_edit)
	var ok := Button.new()
	ok.text = "  %s  " % done_text
	ok.add_theme_font_size_override("font_size", 32)
	ok.custom_minimum_size = Vector2(0, 72)
	ok.focus_mode = Control.FOCUS_NONE
	WorldTheme.style_button(ok, Color(0.45, 0.9, 0.6))
	ok.pressed.connect(_finish)
	row.add_child(ok)

	_focus.call_deferred()

func _focus() -> void:
	if not is_inside_tree():
		return
	_edit.grab_focus()
	_edit.select_all()
	if _edit.has_method("edit"):
		_edit.call("edit")
	elif DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show(_edit.text, Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT,
				max_length)


func _finish() -> void:
	if _closed:
		return
	_closed = true
	_close_keyboard()
	queue_free()
	done.emit(_edit.text)


func cancel() -> void:
	if _closed:
		return
	_closed = true
	_close_keyboard()
	queue_free()

func _close_keyboard() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
