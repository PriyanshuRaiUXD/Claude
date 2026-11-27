class_name MetaUi
extends RefCounted
## Shared widgets for the progression screens (shop, rewards, results).

const GOLD := Color(1.0, 0.8, 0.16)
const GOLD_DARK := Color(0.82, 0.52, 0.06)
const PURPLE := Color(0.62, 0.42, 0.98)


## A drawn coin, so the game needs no icon atlas.
class CoinIcon:
	extends Control

	func _init(side := 34.0) -> void:
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c + Vector2(0, r * 0.12), r, UiKit.INK)
		draw_circle(c, r, UiKit.INK)
		draw_circle(c, r - 3.0, MetaUi.GOLD_DARK)
		draw_circle(c - Vector2(0, r * 0.08), r - 3.0 - r * 0.1, MetaUi.GOLD)
		draw_arc(c - Vector2(0, r * 0.08), r * 0.52, 0.0, TAU, 24, MetaUi.GOLD_DARK, maxf(2.0, r * 0.14), true)
		draw_arc(c - Vector2(0, r * 0.08), r * 0.7, -2.6, -1.5, 8, Color(1, 1, 1, 0.8), maxf(2.0, r * 0.12), true)


## Coin icon + amount, e.g. for prices and the wallet.
static func coin_amount(amount: int, font_size := 28, color := Color.WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := CoinIcon.new(font_size * 1.15)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var l := UiKit.label(commas(amount), font_size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The wallet chip shown on the main menu and in the shop header.
class Wallet:
	extends PanelContainer

	var _label: Label
	var _shown := -1

	func _init() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.07, 0.13, 0.82)
		sb.set_corner_radius_all(26)
		sb.set_border_width_all(3)
		sb.border_color = UiKit.INK
		sb.content_margin_left = 12
		sb.content_margin_right = 18
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.add_child(MetaUi.CoinIcon.new(38))
		_label = UiKit.label("0", 30, MetaUi.GOLD)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_label)

	func _process(_delta: float) -> void:
		# Count towards the real balance so every payout visibly lands.
		if _shown < 0:
			_shown = Progress.coins
		elif _shown != Progress.coins:
			var step := maxi(1, absi(Progress.coins - _shown) / 8)
			_shown = Progress.coins if absi(Progress.coins - _shown) <= step else _shown + step * signi(Progress.coins - _shown)
		_label.text = MetaUi.commas(_shown)


## Dimmed full-screen modal with a centred panel. Returns the content VBox;
## the modal Control itself is `box.get_meta("modal")`.
static func modal(parent: Node, title: String, on_close: Callable, min_width := 0.0) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.97)
	style.set_border_width_all(4)
	style.border_color = UiKit.INK
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	if not title.is_empty():
		box.add_child(UiKit.title(title, 46, UiKit.YELLOW))
	box.set_meta("modal", root)
	box.set_meta("panel", panel)
	parent.add_child(root)
	if on_close.is_valid():
		UiKit.corner_close(root, on_close)
		UiKit.close_on_outside_tap(root, panel, on_close)
	UiKit.pop_in.call_deferred(panel)
	return box


## A card-style panel used for shop items and quest rows.
static func card(tint := Color(0.16, 0.22, 0.33, 0.9)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = UiKit.INK
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	return p


static func bar(value: float, color := GOLD, size := Vector2(220, 18)) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = clampf(value, 0.0, 1.0)
	b.show_percentage = false
	b.custom_minimum_size = size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.11, 0.9)
	bg.set_corner_radius_all(int(size.y / 2.0))
	bg.set_border_width_all(2)
	bg.border_color = UiKit.INK
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(int(size.y / 2.0))
	fill.set_border_width_all(2)
	fill.border_color = UiKit.INK
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


## Small floating "+120" that rises and fades over a control.
static func float_text(over: Control, text: String, color := GOLD) -> void:
	if over == null or not over.is_inside_tree():
		return
	var l := UiKit.title(text, 34, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.top_level = true
	over.add_child(l)
	l.global_position = over.global_position + Vector2(over.size.x * 0.5 - 60.0, -10.0)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y - 70.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


## Red notification dot for buttons with something to claim.
class Dot:
	extends Control

	var count := 0:
		set(value):
			count = value
			visible = count > 0
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 15.0, UiKit.INK)
		draw_circle(c, 12.0, UiKit.RED)
		draw_string(get_theme_default_font(), Vector2(0, c.y + 7.0), str(count),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, Color.WHITE)
