class_name DragScroll
extends ScrollContainer


const DRAG_START := 14.0
const WHEEL_STEP := 70
const TAP_GUARD_MS := 200

var _touch := -1
var _start_y := 0.0
var _start_scroll := 0
var _dragging := false
var _drag_end_ms := -100000

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	mouse_filter = Control.MOUSE_FILTER_IGNORE


func just_dragged() -> bool:
	return _dragging or Time.get_ticks_msec() - _drag_end_ms < TAP_GUARD_MS

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0 and get_global_rect().has_point(event.position) and not _covered():

			_touch = event.index
			_start_y = event.position.y
			_start_scroll = scroll_vertical
			_dragging = false
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if _dragging:
				_drag_end_ms = Time.get_ticks_msec()
			_dragging = false
	elif event is InputEventScreenDrag and event.index == _touch:
		var dy: float = event.position.y - _start_y
		if not _dragging and absf(dy) > DRAG_START:
			_dragging = true
		if _dragging:
			scroll_vertical = int(_start_scroll - dy)
	elif event is InputEventMouseButton and event.pressed and get_global_rect().has_point(event.position) and not _covered():

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_vertical -= WHEEL_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_vertical += WHEEL_STEP


func _covered() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for sibling in parent.get_children():
		if sibling != self and sibling is Control and (sibling as Control).visible and sibling.get_index() > get_index() and (sibling is CharacterPicker or sibling is ConfirmBox):

			return true
	return false
