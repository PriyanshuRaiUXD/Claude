class_name ConfirmBox
extends Control


signal confirmed

var question := "Are you sure?"
var detail := ""
var yes_text := "Yes"
var no_text := "Cancel"


static func ask(parent: Node, text: String, on_yes: Callable, yes_label := "Yes",
		more := "") -> ConfirmBox:
	var box := ConfirmBox.new()
	box.question = text
	box.detail = more
	box.yes_text = yes_label
	box.confirmed.connect(on_yes)
	parent.add_child(box)
	return box

func _ready() -> void:
	add_to_group("confirm_box")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.97)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	root.add_child(WorldTheme.title_label(question, 40))
	if not detail.is_empty():
		var more := Label.new()
		more.text = detail
		more.add_theme_font_size_override("font_size", 22)
		more.add_theme_color_override("font_color", WorldTheme.MENU_DIM)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		more.custom_minimum_size = Vector2(520, 0)
		root.add_child(more)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	root.add_child(row)
	var no := Button.new()
	no.text = "  %s  " % no_text
	no.add_theme_font_size_override("font_size", 30)
	no.custom_minimum_size = Vector2(200, 66)
	WorldTheme.style_button(no)
	no.pressed.connect(cancel)
	row.add_child(no)
	var yes := Button.new()
	yes.text = "  %s  " % yes_text
	yes.add_theme_font_size_override("font_size", 30)
	yes.custom_minimum_size = Vector2(200, 66)
	WorldTheme.style_button(yes, Color(1.0, 0.5, 0.4))
	yes.pressed.connect(func() -> void:
		queue_free()
		confirmed.emit())
	row.add_child(yes)
	UiKit.close_on_outside_tap(self, panel, cancel)

func cancel() -> void:
	queue_free()
