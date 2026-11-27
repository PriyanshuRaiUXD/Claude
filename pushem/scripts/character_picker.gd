class_name CharacterPicker
extends Control


signal picked(id: String)

var current := Characters.DEFAULT

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.95)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 24)
	root.add_child(head)
	head.add_child(WorldTheme.title_label("CHOOSE YOUR FIGHTER", 40))
	var wallet := MetaUi.Wallet.new()
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wallet)

	var group := ButtonGroup.new()
	for wclass: PlayerPawn.WeightClass in Characters.CLASS_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		root.add_child(row)

		var caption := Label.new()
		caption.text = Characters.CLASS_BLURBS[wclass]
		caption.custom_minimum_size = Vector2(170, 0)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 20)
		caption.add_theme_color_override("font_color",
				PlayerPawn.STATS[wclass]["color"].lightened(0.35))
		row.add_child(caption)

		for id in Characters.ids_of_class(wclass):
			row.add_child(_card(id, group))

	var back := Button.new()
	back.text = "  Back  "
	back.add_theme_font_size_override("font_size", 26)
	back.custom_minimum_size = Vector2(0, 50)
	WorldTheme.style_button(back)
	back.pressed.connect(queue_free)
	root.add_child(back)
	UiKit.close_on_outside_tap(self, panel, queue_free)

func _card(id: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = id == current
	b.custom_minimum_size = Vector2(176, 150)
	var tint: Color = PlayerPawn.STATS[Characters.class_of(id)]["color"].lightened(0.3)
	WorldTheme.style_button(b, tint)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)

	var preview := CharacterPreview.new()
	preview.character = id
	preview.custom_minimum_size = Vector2(176, 116)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(preview)

	var name_label := Label.new()
	name_label.text = Characters.display_name(id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", WorldTheme.MENU_ACCENT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	if not Progress.can_use(id):
		preview.modulate = Color(0.45, 0.48, 0.56)
		name_label.visible = false
		var tag := MetaUi.coin_amount(Characters.price(id), 22, MetaUi.GOLD)
		box.add_child(tag)
	elif not Progress.owns(id):
		name_label.text = "TRIAL · 1 MATCH"
		name_label.add_theme_color_override("font_color", UiKit.GREEN)

	b.pressed.connect(func() -> void:
		if Progress.can_use(id):
			picked.emit(id)
			queue_free()
		else:
			b.button_pressed = false
			_offer(id))
	return b


## Locked fighter: buy with coins, or try it for one match via a rewarded ad.
func _offer(id: String) -> void:
	var price := Characters.price(id)
	var enough := Progress.coins >= price
	var box := MetaUi.modal(self, Characters.display_name(id).to_upper(), Callable(), 460.0)
	var modal: Control = box.get_meta("modal")
	var close := func() -> void: modal.queue_free()
	var view := CharacterPreview.new()
	view.character = id
	view.custom_minimum_size = Vector2(300, 190)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(view)
	var wclass := Characters.class_of(id)
	var kind := UiKit.label("%s fighter — same stats as every %s" % [
			(PlayerPawn.STATS[wclass]["label"] as String).to_upper(),
			(PlayerPawn.STATS[wclass]["label"] as String).to_lower()], 20, WorldTheme.MENU_DIM)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kind)
	if not enough:
		var need := UiKit.label("You need %s more coins" % MetaUi.commas(price - Progress.coins),
				22, UiKit.RED.lightened(0.25))
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(need)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var buy := UiKit.chunky("", UiKit.GREEN, 26, Vector2(190, 66))
	var cost := MetaUi.coin_amount(price, 26)
	cost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cost.offset_bottom = -6
	buy.add_child(cost)
	buy.disabled = not enough
	buy.pressed.connect(func() -> void:
		if Progress.buy_fighter(id):
			GameAudio.play("win", -8.0, 1.4)
			picked.emit(id)
			queue_free())
	row.add_child(buy)
	if Ads.rewarded_available():
		var try_it := UiKit.chunky("TRY  ·  AD", UiKit.BLUE, 24, Vector2(190, 66))
		try_it.pressed.connect(func() -> void:
			try_it.disabled = true
			Ads.show_rewarded("try_fighter", func() -> void:
				Progress.start_trial(id)
				if is_inside_tree():
					picked.emit(id)
					queue_free()))
		row.add_child(try_it)
	var back := UiKit.chunky("BACK", Color(0.3, 0.36, 0.48), 24, Vector2(130, 66))
	back.pressed.connect(close)
	row.add_child(back)
