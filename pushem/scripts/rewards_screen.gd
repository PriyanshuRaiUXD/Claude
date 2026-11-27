class_name RewardsScreen
extends Control
## Daily login streak and today's three quests.

signal closed

var _body: HBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := MetaUi.modal(self, "REWARDS", close)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	box.add_child(_body)
	_fill()


func close() -> void:
	closed.emit()
	queue_free()


func go_back() -> void:
	close()


func _fill() -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(_daily_column())
	_body.add_child(_quest_column())


func _daily_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.add_child(UiKit.label("DAILY BONUS", 26, WorldTheme.MENU_DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	var available := Progress.daily_available()
	var next_step := Progress.daily_next_step()
	# Days already banked in the current loop.
	var done := next_step - 1 if available else (Progress.daily_streak - 1) % Progress.DAILY_REWARDS.size() + 1
	for i in Progress.DAILY_REWARDS.size():
		var day := i + 1
		var is_next := available and day == next_step
		var tint := Color(0.16, 0.22, 0.33, 0.92)
		if day <= done:
			tint = Color(0.14, 0.34, 0.2, 0.95)
		elif is_next:
			tint = Color(0.5, 0.36, 0.08, 0.98)
		var cell := MetaUi.card(tint)
		cell.custom_minimum_size = Vector2(104, 92)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		var dl := UiKit.label("DAY %d" % day, 18, WorldTheme.MENU_DIM)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dl)
		if day <= done:
			var ok := UiKit.label("CLAIMED", 18, UiKit.GREEN)
			ok.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(ok)
		else:
			v.add_child(MetaUi.coin_amount(Progress.DAILY_REWARDS[i], 22,
					MetaUi.GOLD if is_next else Color.WHITE))
		grid.add_child(cell)
		if is_next:
			UiKit.pulse.call_deferred(cell, 0.04, 1.2)

	if available:
		var amount := Progress.daily_next_amount()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var claim := UiKit.chunky("CLAIM  +%d" % amount, UiKit.GREEN, 26, Vector2(210, 64))
		claim.pressed.connect(func() -> void: _claim_daily(claim, 1))
		row.add_child(claim)
		if Ads.rewarded_available():
			var double := UiKit.chunky("WATCH AD  x2", UiKit.BLUE, 24, Vector2(210, 64))
			double.pressed.connect(func() -> void:
				claim.disabled = true
				double.disabled = true
				Ads.show_rewarded("daily_double", func() -> void: _claim_daily(double, 2)))
			row.add_child(double)
	else:
		col.add_child(UiKit.label("Come back tomorrow for day %d." % Progress.daily_next_step(),
				22, WorldTheme.MENU_DIM))
	return col


func _claim_daily(from: Control, multiplier: int) -> void:
	var got := Progress.claim_daily(multiplier)
	if got > 0 and is_inside_tree():
		GameAudio.play("win", -8.0, 1.5)
		MetaUi.float_text(from, "+%d" % got)
	_fill.call_deferred()


func _quest_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.add_child(UiKit.label("TODAY'S QUESTS", 26, WorldTheme.MENU_DIM))
	var list := Progress.quests_today()
	for i in list.size():
		var q: Dictionary = list[i]
		var def := Progress.quest_def(q["id"])
		if def.is_empty():
			continue
		var done := Progress.quest_done(q)
		var claimed: bool = q.get("claimed", false)
		var card := MetaUi.card(Color(0.14, 0.34, 0.2, 0.95) if claimed else Color(0.16, 0.22, 0.33, 0.92))
		card.custom_minimum_size = Vector2(430, 0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 4)
		row.add_child(left)
		left.add_child(UiKit.label(def["text"], 22))
		var prog := HBoxContainer.new()
		prog.add_theme_constant_override("separation", 8)
		left.add_child(prog)
		prog.add_child(MetaUi.bar(float(q["have"]) / float(def["goal"]),
				UiKit.GREEN if done else MetaUi.GOLD, Vector2(190, 16)))
		prog.add_child(UiKit.label("%d/%d" % [q["have"], def["goal"]], 18, WorldTheme.MENU_DIM))
		if claimed:
			row.add_child(UiKit.label("DONE", 22, UiKit.GREEN))
		elif done:
			var claim := UiKit.chunky("+%d" % def["reward"], UiKit.GREEN, 24, Vector2(110, 56))
			claim.pressed.connect(func() -> void:
				var got := Progress.claim_quest(i)
				if got > 0:
					GameAudio.play("tick", 0.0, 1.6)
					MetaUi.float_text(claim, "+%d" % got)
				_fill.call_deferred())
			row.add_child(claim)
		else:
			var reward := MetaUi.coin_amount(def["reward"], 22)
			reward.custom_minimum_size = Vector2(110, 0)
			row.add_child(reward)
		col.add_child(card)
	return col
