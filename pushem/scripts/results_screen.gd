class_name ResultsScreen
extends CanvasLayer
## Post-match summary: placement, payout breakdown, XP bar, and the opt-in
## "double coins" rewarded ad. Shown over the frozen arena.

signal continued

## Filled in by Game before the node enters the tree.
var place := 0
var players := 0
var winner_name := ""
var payout := {}
## False in online matches: the host returns everyone to the lobby, so the
## panel is informational and has no buttons.
var interactive := true

var _coin_row: HBoxContainer
var _total_label: Label
var _double: Button
var _continue: Button
var _shown_total := 0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var box := MetaUi.modal(root, "", Callable(), 560.0)
	var modal: Control = box.get_meta("modal")
	modal.mouse_filter = root.mouse_filter
	(modal.get_child(0) as ColorRect).color = Color(0.02, 0.04, 0.08, 0.5)

	var won := place == 1 and players > 1
	var headline := "VICTORY!" if won else ("DRAW" if place <= 0 else "%s PLACE" % _ordinal(place))
	var head := UiKit.title(headline, 64, UiKit.YELLOW if won else Color.WHITE)
	box.add_child(head)
	UiKit.wobble.call_deferred(head, 1.5, 2.6)
	if not won and not winner_name.is_empty():
		var sub := UiKit.label("%s took the win" % winner_name, 22, WorldTheme.MENU_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(sub)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)
	for row: Array in payout.get("rows", []):
		rows.add_child(_line(str(row[0]), int(row[1])))
	if int(payout.get("level_bonus", 0)) > 0:
		rows.add_child(_line("Level %d reached!" % payout["level_after"],
				int(payout["level_bonus"]), MetaUi.PURPLE.lightened(0.3)))

	var total := HBoxContainer.new()
	total.alignment = BoxContainer.ALIGNMENT_CENTER
	total.add_theme_constant_override("separation", 10)
	box.add_child(total)
	total.add_child(UiKit.label("TOTAL", 30, WorldTheme.MENU_DIM))
	var icon := MetaUi.CoinIcon.new(44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(icon)
	_total_label = UiKit.title("0", 44, MetaUi.GOLD)
	total.add_child(_total_label)
	_coin_row = total
	_count_to(int(payout.get("coins", 0)) + int(payout.get("level_bonus", 0)))

	var info := Progress.level_info()
	var xp_row := HBoxContainer.new()
	xp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	xp_row.add_theme_constant_override("separation", 10)
	box.add_child(xp_row)
	xp_row.add_child(UiKit.label("LV %d" % info["level"], 24, MetaUi.PURPLE.lightened(0.35)))
	var xp_bar := MetaUi.bar(0.0, MetaUi.PURPLE, Vector2(300, 18))
	xp_row.add_child(xp_bar)
	xp_row.add_child(UiKit.label("+%d XP" % payout.get("xp", 0), 20, WorldTheme.MENU_DIM))
	create_tween().tween_property(xp_bar, "value",
			float(info["into"]) / float(info["need"]), 0.8).set_delay(0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if not interactive:
		var wait := UiKit.label("Back to the lobby in a moment...", 20, WorldTheme.MENU_DIM)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(wait)
		return
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	if Ads.rewarded_available() and int(payout.get("coins", 0)) > 0:
		_double = UiKit.chunky("WATCH AD  x2 COINS", UiKit.BLUE, 24, Vector2(290, 70))
		_double.pressed.connect(_on_double)
		buttons.add_child(_double)
	_continue = UiKit.chunky("CONTINUE", UiKit.GREEN, 28, Vector2(220, 70))
	_continue.pressed.connect(_on_continue)
	buttons.add_child(_continue)


func _line(text: String, amount: int, color := Color.WHITE) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := UiKit.label(text, 24, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(MetaUi.coin_amount(amount, 24, MetaUi.GOLD))
	return row


func _count_to(target: int) -> void:
	var from := _shown_total
	_shown_total = target
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_total_label.text = MetaUi.commas(int(round(v))), float(from), float(target), 0.7).set_delay(0.25)


func _on_double() -> void:
	_double.disabled = true
	_continue.disabled = true
	Ads.show_rewarded("results_double", func() -> void:
		var bonus := int(payout.get("coins", 0))
		Progress.add_coins(bonus)
		if not is_inside_tree():
			return
		GameAudio.play("win", -8.0, 1.5)
		_double.visible = false
		MetaUi.float_text(_coin_row, "x2!")
		_count_to(_shown_total + bonus))
	# Whether or not the ad paid out, the player can always leave.
	get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(_continue):
			_continue.disabled = false)


func _on_continue() -> void:
	_continue.disabled = true
	continued.emit()


static func _ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dTH" % n
	match n % 10:
		1:
			return "%dST" % n
		2:
			return "%dND" % n
		3:
			return "%dRD" % n
	return "%dTH" % n
