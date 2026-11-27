class_name ProfileEditor
extends Control


signal changed

var fighter := Characters.DEFAULT

var _big: UiKit.Avatar
var _name_field: Button
var _tiles := {}
var _error: Label
var _photo_tile: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := WorldTheme.panel_style()
	style.bg_color = Color(WorldTheme.MENU_PANEL, 0.96)
	style.set_border_width_all(4)
	style.border_color = UiKit.INK
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	root.add_child(UiKit.title("PROFILE", 52, UiKit.YELLOW))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	root.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(left)
	_big = UiKit.Avatar.new(190)
	_big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_big)
	left.add_child(UiKit.label("NAME", 22, WorldTheme.MENU_DIM))
	_name_field = TextEntry.field(30, Vector2(260, 56))
	_name_field.text = Settings.player_name
	_name_field.pressed.connect(_edit_name)
	left.add_child(_name_field)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(UiKit.label("ICON", 22, WorldTheme.MENU_DIM))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	grid.add_child(_tile("", UiKit.portrait(fighter), UiKit.avatar_tint(fighter), "MY FIGHTER"))
	for id: String in Characters.LIST:
		grid.add_child(_tile(id, UiKit.portrait(id), UiKit.avatar_tint(id), ""))
	_photo_tile = _tile(Settings.AVATAR_CUSTOM, UiKit.custom_avatar(), Color(0.12, 0.16, 0.24),
			"MY PHOTO")
	_photo_tile.visible = UiKit.custom_avatar() != null
	grid.add_child(_photo_tile)
	var upload := UiKit.chunky("UPLOAD\nPHOTO", UiKit.BLUE, 18, Vector2(92, 92))
	upload.add_theme_constant_override("outline_size", 5)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := upload.get_theme_stylebox(state) as StyleBoxFlat
		sb.content_margin_left = 2
		sb.content_margin_right = 2
	upload.pressed.connect(_pick_photo)
	grid.add_child(upload)
	_error = UiKit.label("", 20, Color(1.0, 0.6, 0.5))
	right.add_child(_error)

	UiKit.corner_close(self, close)
	UiKit.close_on_outside_tap(self, panel, close)
	_refresh()
	UiKit.pop_in.call_deferred(panel)

func close() -> void:
	queue_free()


func _tile(value: String, tex: Texture2D, tint: Color, caption: String) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 92)
	var av := UiKit.Avatar.new(92)
	av.show_texture(tex, tint)
	b.add_child(av)
	if not caption.is_empty():
		var l := UiKit.label(caption, 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -24
		l.offset_bottom = -4
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	_tiles[value] = av
	b.pressed.connect(func() -> void:
		Settings.avatar = value
		Settings.save()
		_refresh()
		changed.emit())
	return b

func _refresh() -> void:
	_big.show_profile(fighter)
	var current := Settings.avatar
	if current == Settings.AVATAR_CUSTOM and UiKit.custom_avatar() == null:
		current = ""
	for value: String in _tiles:
		(_tiles[value] as UiKit.Avatar).set_border(UiKit.YELLOW if value == current else UiKit.INK)

func _edit_name() -> void:
	TextEntry.ask(self, "YOUR NAME", Settings.player_name, func(t: String) -> void:
		var n := t.strip_edges().left(Settings.NAME_MAX)
		if n.is_empty():
			return
		Settings.player_name = n
		Settings.save()
		_name_field.text = n
		changed.emit(), Settings.NAME_MAX, "Type your name")


func _pick_photo() -> void:
	_error.text = ""
	var filters := PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Choose a picture", "", "", false,
				DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
				func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
					if ok and paths.size() > 0:
						_use_photo.call_deferred(paths[0]))
		return

	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = filters
	dlg.title = "Choose a picture"
	dlg.file_selected.connect(func(path: String) -> void:
		_use_photo(path)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.8)


func _use_photo(path: String) -> void:
	var img := load_picture(path)
	if img == null:
		_error.text = "Couldn't open that picture — try a PNG or JPG."
		return
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2,
			side, side))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	if img.save_png(Settings.AVATAR_PATH) != OK:
		_error.text = "Couldn't save the picture."
		return
	UiKit.reload_custom_avatar()
	(_tiles[Settings.AVATAR_CUSTOM] as UiKit.Avatar).show_texture(UiKit.custom_avatar(),
			Color(0.12, 0.16, 0.24))
	_photo_tile.visible = true
	Settings.avatar = Settings.AVATAR_CUSTOM
	Settings.save()
	_refresh()
	changed.emit()


static func load_picture(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 12:
		if bytes[0] == 137 and bytes[1] == 80:
			err = img.load_png_from_buffer(bytes)
		elif bytes[0] == 255 and bytes[1] == 216:
			err = img.load_jpg_from_buffer(bytes)
		elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
			err = img.load_webp_from_buffer(bytes)
	if err != OK:
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return img
