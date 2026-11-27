class_name ShopScreen
extends Control
## Real-money shop plus the opt-in "watch an ad for coins" card.

signal closed

var _grid: GridContainer
var _note: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := MetaUi.modal(self, "SHOP", close)
	var wallet := MetaUi.Wallet.new()
	wallet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(wallet)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(_grid)
	_note = UiKit.label("", 20, WorldTheme.MENU_DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	_fill()


func close() -> void:
	closed.emit()
	queue_free()


func go_back() -> void:
	close()


func _fill() -> void:
	for child in _grid.get_children():
		child.queue_free()
	if Ads.rewarded_available() or Progress.ad_coins_left() < Progress.AD_COINS_PER_DAY:
		_grid.add_child(_ad_card())
	for product: String in Store.ORDER:
		if Store.purchasable(product):
			_grid.add_child(_product_card(product))
	if not Store.available():
		_note.text = "Purchases are not connected in this build."
	elif OS.is_debug_build():
		_note.text = "Test build: purchases are simulated and free."
	else:
		_note.text = "Fighters are bought with coins in CHANGE FIGHTER."


func _card_shell(title: String, blurb: String, tint: Color) -> VBoxContainer:
	var card := MetaUi.card(tint)
	card.custom_minimum_size = Vector2(232, 190)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var t := UiKit.label(title, 26, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := Label.new()
	b.text = blurb
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.86, 0.9, 0.97))
	v.add_child(b)
	return v


func _product_card(product: String) -> Control:
	var item: Dictionary = Store.CATALOG[product]
	var featured := product == Store.STARTER_PACK
	var v := _card_shell(item["title"], item["blurb"],
			Color(0.3, 0.2, 0.46, 0.95) if featured else Color(0.16, 0.22, 0.33, 0.92))
	var buy := UiKit.chunky(Store.price_label(product), UiKit.GREEN, 24, Vector2(0, 56))
	buy.disabled = not Store.available()
	buy.pressed.connect(func() -> void:
		buy.disabled = true
		Store.buy(product, func(ok: bool) -> void:
			if not is_inside_tree():
				return
			if ok:
				GameAudio.play("win", -8.0, 1.4)
				MetaUi.float_text(buy, "THANKS!", UiKit.GREEN)
			_fill.call_deferred()))
	v.add_child(buy)
	return v.get_parent() as Control


func _ad_card() -> Control:
	var left := Progress.ad_coins_left()
	var v := _card_shell("Free Coins", "Watch a short ad\n%d left today" % left,
			Color(0.12, 0.3, 0.36, 0.95))
	var watch := UiKit.chunky("WATCH  +%d" % Progress.AD_COINS, UiKit.BLUE, 22, Vector2(0, 56))
	watch.disabled = left <= 0 or not Ads.rewarded_available()
	watch.pressed.connect(func() -> void:
		watch.disabled = true
		Ads.show_rewarded("shop_coins", func() -> void:
			var got := Progress.claim_ad_coins()
			if is_inside_tree():
				GameAudio.play("tick", 0.0, 1.6)
				MetaUi.float_text(watch, "+%d" % got)
				_fill.call_deferred()))
	v.add_child(watch)
	return v.get_parent() as Control
