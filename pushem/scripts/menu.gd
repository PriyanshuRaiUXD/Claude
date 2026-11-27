class_name MainMenu
extends Control


signal practice_requested(map: Arena.Shape, world: WorldTheme.Kind, fighter: String)
signal host_requested(map: Arena.Shape, world: WorldTheme.Kind,
		fighter: String, pname: String)
signal join_requested(fighter: String, pname: String)
signal settings_requested

var _fighter := Characters.DEFAULT
var _preview: CharacterPreview
var _fighter_label: Label
var _class_label: Label
var _badge_avatar: UiKit.Avatar
var _name_label: Label
var _level_label: Label
var _xp_bar: ProgressBar
var _rewards_dot: MetaUi.Dot
var _shop_button: Button
static var _greeted := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(WorldTheme.make_backdrop(WorldTheme.MENU_BACKDROP))
	_fighter = Progress.usable_fighter(Settings.fighter)

	if Settings.player_name.is_empty():
		Settings.player_name = "Player %d" % (randi() % 900 + 100)
		Settings.save()

	var glow := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.9, 0.42))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(glow, Control.PRESET_CENTER, -330, -320, 330, 260)
	add_child(glow)

	_preview = CharacterPreview.new()
	_preview.character = _fighter
	_preview.sway = true
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_preview, Control.PRESET_CENTER, -230, -280, 230, 210)
	add_child(_preview)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	_place(hit, Control.PRESET_CENTER, -170, -260, 170, 200)
	hit.pressed.connect(open_picker)
	add_child(hit)

	var plate := VBoxContainer.new()
	plate.add_theme_constant_override("separation", 2)
	plate.alignment = BoxContainer.ALIGNMENT_END
	_place(plate, Control.PRESET_CENTER_BOTTOM, -170, -150, 170, -18)
	add_child(plate)
	_fighter_label = UiKit.title("", 38)
	plate.add_child(_fighter_label)
	_class_label = UiKit.label("", 22)
	_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(_class_label)
	var change := UiKit.chunky("CHANGE FIGHTER", UiKit.BLUE, 24, Vector2(240, 58))
	change.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change.pressed.connect(open_picker)
	plate.add_child(change)

	var badge := Button.new()
	badge.flat = true
	badge.focus_mode = Control.FOCUS_NONE
	_place(badge, Control.PRESET_TOP_LEFT, 16, 14, 400, 118)
	badge.pressed.connect(open_profile)
	add_child(badge)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)
	_badge_avatar = UiKit.Avatar.new(96)
	row.add_child(_badge_avatar)
	var who := VBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	_name_label = UiKit.label("", 32)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(_name_label)
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 8)
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(lv_row)
	_level_label = UiKit.label("LV 1", 20, MetaUi.PURPLE.lightened(0.35))
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_child(_level_label)
	_xp_bar = MetaUi.bar(0.0, MetaUi.PURPLE, Vector2(150, 14))
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_child(_xp_bar)
	var edit := UiKit.label("EDIT PROFILE", 18, UiKit.YELLOW)
	edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(edit)

	var title := UiKit.title("PUSH 'EM", 60, UiKit.YELLOW)
	_place(title, Control.PRESET_CENTER_TOP, -220, 12, 220, 96)
	add_child(title)
	UiKit.wobble.call_deferred(title, 2.0, 3.4)
	var gear := UiKit.IconButton.new("gear", 76)
	_place(gear, Control.PRESET_TOP_RIGHT, -94, 16, -18, 92)
	gear.pressed.connect(func() -> void: settings_requested.emit())
	add_child(gear)

	var wallet := MetaUi.Wallet.new()
	wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallet.offset_right = -108
	wallet.offset_top = 26
	wallet.mouse_filter = Control.MOUSE_FILTER_STOP
	wallet.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			open_shop())
	add_child(wallet)

	_shop_button = UiKit.chunky("SHOP", MetaUi.PURPLE, 30, Vector2(0, 0), "coins & packs")
	_place(_shop_button, Control.PRESET_CENTER_LEFT, 22, -128, 222, -40)
	_shop_button.pressed.connect(open_shop)
	add_child(_shop_button)
	var rewards := UiKit.chunky("REWARDS", Color(0.95, 0.5, 0.2), 28, Vector2(0, 0), "daily & quests")
	_place(rewards, Control.PRESET_CENTER_LEFT, 22, -24, 222, 64)
	rewards.pressed.connect(open_rewards)
	add_child(rewards)
	_rewards_dot = MetaUi.Dot.new()
	_rewards_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rewards_dot.offset_left = -20
	_rewards_dot.offset_right = 10
	_rewards_dot.offset_top = -12
	_rewards_dot.offset_bottom = 18
	rewards.add_child(_rewards_dot)

	var practice := UiKit.chunky("PRACTICE", UiKit.BLUE, 40, Vector2(0, 0), "vs bots")
	_place(practice, Control.PRESET_BOTTOM_LEFT, 22, -128, 282, -20)
	practice.pressed.connect(open_practice)
	add_child(practice)
	var host := UiKit.chunky("HOST GAME", UiKit.YELLOW, 36, Vector2(0, 0), "friends join you")
	_place(host, Control.PRESET_BOTTOM_RIGHT, -472, -128, -252, -20)
	host.pressed.connect(func() -> void:
		host_requested.emit(_last_map(), _last_world(), _fighter, _player_name()))
	add_child(host)
	var join := UiKit.chunky("JOIN GAME", UiKit.GREEN, 36, Vector2(0, 0), "enter a code")
	_place(join, Control.PRESET_BOTTOM_RIGHT, -238, -128, -22, -20)
	join.pressed.connect(func() -> void: join_requested.emit(_fighter, _player_name()))
	add_child(join)
	UiKit.pulse.call_deferred(host, 0.025, 1.8)

	_show_fighter()
	_show_profile()
	_show_progress()
	# Greet the player with the daily bonus once per session.
	if not _greeted and Progress.daily_available() and OS.get_cmdline_user_args().is_empty():
		_greeted = true
		open_rewards.call_deferred()


func _show_progress() -> void:
	var info := Progress.level_info()
	_level_label.text = "LV %d" % info["level"]
	_xp_bar.value = float(info["into"]) / float(info["need"])
	_rewards_dot.count = Progress.claimable_quests() + (1 if Progress.daily_available() else 0)
	_fighter = Progress.usable_fighter(_fighter)
	_show_fighter()


func open_shop() -> void:
	var shop := ShopScreen.new()
	shop.closed.connect(_show_progress)
	add_child(shop)


func open_rewards() -> void:
	var rewards := RewardsScreen.new()
	rewards.closed.connect(_show_progress)
	add_child(rewards)


func _place(c: Control, preset: Control.LayoutPreset, l: float, t: float, r: float,
		b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func go_back() -> void:
	for child in get_children():
		if child is ShopScreen or child is RewardsScreen:
			child.close()
			return
		if child is CharacterPicker or child is ProfileEditor or child is PracticeSetup:
			child.queue_free()
			return
	ConfirmBox.ask(self, "Exit Push 'Em?", func() -> void: get_tree().quit(), "Exit")


func open_picker() -> void:
	var picker := CharacterPicker.new()
	picker.current = _fighter
	picker.picked.connect(func(id: String) -> void:
		_fighter = id
		Settings.fighter = id
		Settings.save()
		_show_fighter()
		_show_profile())
	add_child(picker)

func open_profile() -> void:
	var editor := ProfileEditor.new()
	editor.fighter = _fighter
	editor.changed.connect(_show_profile)
	add_child(editor)

func open_practice() -> void:
	var setup := PracticeSetup.new()
	setup.start_requested.connect(func(map: Arena.Shape, world: WorldTheme.Kind) -> void:
		practice_requested.emit(map, world, _fighter))
	add_child(setup)


func edit_name() -> void:
	open_profile()
	for child in get_children():
		if child is ProfileEditor:
			child._edit_name()

func _show_fighter() -> void:
	_preview.character = _fighter
	var wclass := Characters.class_of(_fighter)
	_fighter_label.text = Characters.display_name(_fighter).to_upper()
	_class_label.text = "%s FIGHTER" % (PlayerPawn.STATS[wclass]["label"] as String).to_upper()
	_class_label.add_theme_color_override("font_color",
			(PlayerPawn.STATS[wclass]["color"] as Color).lightened(0.35))

func _show_profile() -> void:
	_badge_avatar.show_profile(_fighter)
	_name_label.text = Settings.player_name

func _player_name() -> String:
	var n := Settings.player_name.strip_edges()
	return n if not n.is_empty() else "Player"

func _last_map() -> Arena.Shape:
	return clampi(Settings.last_map, 0, Arena.SHAPE_NAMES.size() - 1) as Arena.Shape

func _last_world() -> WorldTheme.Kind:
	return clampi(Settings.last_world, 0, WorldTheme.NAMES.size() - 1) as WorldTheme.Kind
