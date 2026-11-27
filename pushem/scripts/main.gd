extends Node


const COUNTDOWN_GIVE_DELAY := 3.5

var net: Net
var _screen: Control
var _game: Game

func _ready() -> void:

	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.load_from_disk()
	Progress.load_from_disk()
	Ads.setup()
	Store.setup()

	for arg: String in OS.get_cmdline_user_args():
		if arg == "--showfps":
			Settings.show_fps = true
		elif arg.begins_with("--zoom="):
			Settings.zoom = clampf(float(arg.get_slice("=", 1)), 0.0, 1.0)
		elif arg.begins_with("--port="):
			Net.port_override = int(arg.get_slice("=", 1))
		elif arg.begins_with("--graphics="):
			for level: Settings.Quality in Settings.QUALITY_NAMES:
				if Settings.QUALITY_NAMES[level].to_lower() == arg.get_slice("=", 1).to_lower():
					Settings.graphics = level
	Settings.apply_graphics(get_viewport())
	add_child(GameAudio.new())

	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.match_started.connect(_enter_match)
	net.match_ended.connect(_exit_match_to_lobby)
	net.disconnected.connect(_on_disconnected)

	var test_args := OS.get_cmdline_user_args()
	if not test_args.is_empty():

		var beat := func() -> void:
			var extra := ""
			if _game != null:
				var holding := 0
				for p: PlayerPawn in _game.pawns.values():
					if p.held >= 0 or p.powerup >= 0:
						holding += 1
				extra = " dropped=%d drops=%d holding=%d holes=%d music=%s" % [
						_game._next_drop_id - 1, _game._drops.size(), holding,
						_game._holes.size(), GameAudio.music_state()]
				if _game.local_pawn != null and _game.hud != null:
					extra += " you_held=%d you_active=%d slot=%s" % [
							_game.local_pawn.held, _game.local_pawn.powerup,
							_game.hud.slot.visible]
				if net.role != Net.Role.OFFLINE:
					extra += _game.net_report()
			print("TEST_HEARTBEAT t=%.1f game=%s%s" % [
					Time.get_ticks_msec() / 1000.0,
					"none" if _game == null else Game.Phase.keys()[_game.phase], extra])
		var timer := Timer.new()
		timer.wait_time = 2.0
		timer.timeout.connect(beat)
		add_child(timer)
		timer.start()

	for arg: String in test_args:
		if arg.begins_with("--coins="):
			Progress.coins = int(arg.get_slice("=", 1))
		elif arg.begins_with("--autoend="):
			# Scripted finish: the local fighter knocks everyone else out.
			var after := float(arg.get_slice("=", 1))
			var poll := Timer.new()
			poll.wait_time = 0.25
			add_child(poll)
			poll.timeout.connect(func() -> void:
				if _game == null or _game.local_pawn == null or not _game._playing():
					return
				poll.stop()
				var me := _game.id_of(_game.local_pawn)
				var step := 0
				for id: int in _game.pawns:
					if id == me:
						continue
					step += 1
					get_tree().create_timer(after + step * 0.9).timeout.connect(func() -> void:
						if _game == null or _game.phase == Game.Phase.OVER:
							return
						var victim: PlayerPawn = _game.pawns[id]
						_game._emit("hit", {"pos": victim.global_position + Vector3.UP * 0.8,
								"s": 0.9, "a": me, "b": id})
						victim.lives = 1
						_game._on_pawn_fell(victim)))
			poll.start()
	for arg: String in test_args:
		if arg.begins_with("--shot="):
			var spec := arg.get_slice("=", 1)
			var path := spec.get_slice("@", 0)
			var secs := float(spec.get_slice("@", 1)) if "@" in spec else 6.0
			get_tree().create_timer(secs, true, false, true).timeout.connect(func() -> void:
				var img := get_viewport().get_texture().get_image()
				img.save_png(path)
				print("TEST_SHOT saved %s" % path))
	if "--autoinput" in test_args:

		var poll := Timer.new()
		poll.wait_time = 0.5
		add_child(poll)
		poll.timeout.connect(func() -> void:
			if _game == null or _game.local_pawn == null or not _game._playing():
				return
			poll.stop()
			var start := _game.local_pawn.global_position
			print("NETTEST start pos %s" % start)
			var press := InputEventScreenTouch.new()
			press.pressed = true
			press.position = Vector2(150, 570)
			Input.parse_input_event(press)
			var drag := InputEventScreenDrag.new()
			drag.position = Vector2(236, 570)
			Input.parse_input_event(drag)
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				var tap := InputEventScreenTouch.new()
				tap.pressed = true
				tap.index = 1
				tap.position = Vector2(1130, 580)
				Input.parse_input_event(tap)
				var up := tap.duplicate() as InputEventScreenTouch
				up.pressed = false
				Input.parse_input_event(up)
				get_tree().create_timer(0.2).timeout.connect(func() -> void:
					if _game != null and _game.local_pawn != null:
						print("NETTEST pushed, cooldown %.2f" % _game.local_pawn.cooldown_left)))
			get_tree().create_timer(3.0).timeout.connect(func() -> void:
				var release := InputEventScreenTouch.new()
				release.pressed = false
				release.position = Vector2(236, 570)
				Input.parse_input_event(release)
				if _game != null and _game.local_pawn != null:
					print("NETTEST moved %.2f m" % _game.local_pawn.global_position.distance_to(start))))
		poll.start()
	if "--autotest" in test_args:

		var world := WorldTheme.Kind.LAVA
		for arg: String in test_args:
			if arg.begins_with("--world="):
				var want := arg.get_slice("=", 1).to_lower()
				for kind: WorldTheme.Kind in WorldTheme.NAMES:
					if WorldTheme.NAMES[kind].to_lower() == want:
						world = kind
		var fighter := "armor"
		for arg: String in test_args:
			if arg.begins_with("--char=") and Characters.valid(arg.get_slice("=", 1)):
				fighter = arg.get_slice("=", 1)
		var map := Arena.Shape.HEXAGON
		for arg: String in test_args:
			if arg.begins_with("--map="):
				for shape: Arena.Shape in Arena.SHAPE_NAMES:
					if Arena.SHAPE_NAMES[shape].to_lower() == arg.get_slice("=", 1).to_lower():
						map = shape
		_start_practice(map, world, fighter)
		var aim_pull := Vector2.ZERO
		for arg: String in test_args:
			if arg == "--autoaim":
				aim_pull = Vector2(-50, -60)
			elif arg.begins_with("--autoaim="):
				var xy := arg.get_slice("=", 1).split_floats(",")
				if xy.size() == 2:
					aim_pull = Vector2(xy[0], xy[1])
		if aim_pull != Vector2.ZERO:

			get_tree().create_timer(6.0).timeout.connect(func() -> void:
				var press := InputEventScreenTouch.new()
				press.pressed = true
				press.index = 1
				press.position = Vector2(1130, 580)
				Input.parse_input_event(press)
				var drag := InputEventScreenDrag.new()
				drag.index = 1
				drag.position = Vector2(1130, 580) + aim_pull
				Input.parse_input_event(drag))

			get_tree().create_timer(5.0).timeout.connect(func() -> void:
				if _game != null:
					_game._on_use_pressed())

			for at: float in [7.5, 7.9, 9.0]:
				get_tree().create_timer(at).timeout.connect(func() -> void:
					if _game != null and _game.local_pawn != null:
						var lp: PlayerPawn = _game.local_pawn
						print("AIMTEST t=%.1f pos=%s powerup=%d in_air=%s" % [at,
								lp.global_position.snapped(Vector3.ONE * 0.01), lp.powerup,
								lp.in_air()]))
			get_tree().create_timer(7.6).timeout.connect(func() -> void:
				var release := InputEventScreenTouch.new()
				release.pressed = false
				release.index = 1
				release.position = Vector2(1130, 580) + aim_pull
				Input.parse_input_event(release))
		for arg: String in test_args:
			if arg.begins_with("--automenu="):
				var page := arg.get_slice("=", 1)
				get_tree().create_timer(5.0).timeout.connect(func() -> void:
					if _game == null:
						return
					_game.open_menu(page == "options")
					if page == "edit":
						_game._menu.adjust_stick.emit()
					elif page == "exit":
						_game._menu.exit_to_menu.emit()
					elif page == "leave":
						_game._hide_menu()
						_game.exit_requested.emit())
		if "--autotapout" in test_args:

			for at: float in [6.0, 7.0, 8.0]:
				get_tree().create_timer(at).timeout.connect(func() -> void:
					if _game == null or _game._menu == null:
						print("TAPOUT t=%.0f menu=closed" % at)
						return
					var panel := _game._menu.find_children("", "PanelContainer", true, false)[0] as Control
					var spot := Vector2(30, 360)
					if at == 6.0:
						spot = panel.get_global_rect().position + Vector2(8, 8)
					print("TAPOUT t=%.0f menu=open confirms=%d tap=%s" % [at,
							get_tree().get_nodes_in_group("confirm_box").size(), spot])
					for down: bool in [true, false]:
						var mb := InputEventMouseButton.new()
						mb.button_index = MOUSE_BUTTON_LEFT
						mb.pressed = down
						mb.position = spot
						mb.global_position = spot
						Input.parse_input_event(mb))
		if "--autocancel" in test_args:

			for at: float in [5.0, 6.0, 8.0]:
				get_tree().create_timer(at).timeout.connect(func() -> void:
					if _game != null:
						print("AUTOCANCEL press t=%.0f held=%d active=%d" % [at,
								_game.local_pawn.held, _game.local_pawn.powerup])
						_game._on_use_pressed()
						print("AUTOCANCEL after  held=%d active=%d" % [
								_game.local_pawn.held, _game.local_pawn.powerup]))
		if "--botme" in test_args:
			_bot_drives_me()

		for arg: String in test_args:
			if arg.begins_with("--give="):
				var want := arg.get_slice("=", 1).to_upper()
				for kind: int in Powerup.NAMES:
					if Powerup.NAMES[kind] == want or Powerup.Kind.keys()[kind] == want:
						get_tree().create_timer(COUNTDOWN_GIVE_DELAY).timeout.connect(
								func() -> void:
									if _game != null and _game.local_pawn != null:
										_game.local_pawn.held = kind)
	elif "--autohost" in test_args or "--autodedicated" in test_args:
		net.local_name = "AutoHost"
		if "--autodedicated" in test_args:
			net.host_is_player = false
			net.lite_render = true
		net.host_lobby()
		print("TEST_CODE %s" % net.game_code)
		net.add_bot()
		if "--autodedicated" in test_args:
			net.add_bot()
		net.lobby_changed.connect(func() -> void:
			if net.role == Net.Role.HOST and net.players.size() >= 3 and _game == null:
				net.start_match())
		if "--giveall=shoes" in test_args:

			var give := Timer.new()
			give.wait_time = 0.5
			add_child(give)
			give.timeout.connect(func() -> void:
				if _game != null and _game._playing():
					give.stop()
					for p: PlayerPawn in _game.pawns.values():
						p.held = Powerup.Kind.SHOES)
			give.start()
	elif "--autojoin" in test_args or Array(test_args).any(func(a: String) -> bool:
			return a.begins_with("--autojoincode=")):
		net.local_name = "AutoClient"
		net.local_char = "chef"
		var code := ""
		for arg: String in test_args:
			if arg.begins_with("--autojoincode="):
				code = arg.get_slice("=", 1)
		if "--clientlobby" in test_args:

			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if _game == null:
					_show_lobby(false))
		if code.is_empty():
			net.join("127.0.0.1")
		else:
			var err := net.join_code(code)
			print("TEST_JOINCODE %s -> %s" % [code, "ok" if err.is_empty() else err])
		if "--botme" in test_args:

			net.match_started.connect(_bot_drives_me, CONNECT_DEFERRED)
		if "--autojump" in test_args:

			var poll := Timer.new()
			poll.wait_time = 0.25
			add_child(poll)
			poll.timeout.connect(func() -> void:
				if _game == null or _game.local_pawn == null:
					return
				var lp: PlayerPawn = _game.local_pawn
				if lp.held == Powerup.Kind.SHOES:
					_game._on_use_pressed()
				elif lp.powerup == Powerup.Kind.SHOES and not lp.in_air():
					poll.stop()
					print("JUMPTEST start %s" % lp.global_position.snapped(Vector3.ONE * 0.01))
					var press := InputEventScreenTouch.new()
					press.pressed = true
					press.index = 1
					press.position = Vector2(1130, 580)
					Input.parse_input_event(press)
					var drag := InputEventScreenDrag.new()
					drag.index = 1
					drag.position = Vector2(1130, 500)
					Input.parse_input_event(drag)
					get_tree().create_timer(0.3).timeout.connect(func() -> void:
						var up := press.duplicate() as InputEventScreenTouch
						up.pressed = false
						up.position = drag.position
						Input.parse_input_event(up))
					for at: float in [0.6, 0.85, 1.8]:
						get_tree().create_timer(at).timeout.connect(func() -> void:
							print("JUMPTEST +%.2fs pos=%s powerup=%d in_air=%s" % [at,
									lp.global_position.snapped(Vector3.ONE * 0.01),
									lp.powerup, lp.in_air()])))
			poll.start()
	elif "--autobrowse" in test_args:
		net.hosts_updated.connect(func(hosts: Dictionary) -> void:
			for ip: String in hosts:
				print("FOUND_HOST %s %s" % [ip, hosts[ip]["name"]]))
		net.start_browsing()
	elif Array(test_args).any(func(a: String) -> bool: return a.begins_with("--autoname")):

		_show_menu()
		print("NAMETEST loaded=%s field=%s" % [Settings.player_name,
				(_screen as MainMenu)._name_label.text])
		var typed := ""
		for arg: String in test_args:
			if arg.begins_with("--autoname="):
				typed = arg.get_slice("=", 1)
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			(_screen as MainMenu).edit_name())
		if not typed.is_empty():
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				var box := get_tree().get_first_node_in_group("confirm_box") as TextEntry
				box._edit.text = typed
				box._finish()
				print("NAMETEST saved=%s field=%s" % [Settings.player_name,
						(_screen as MainMenu)._name_label.text]))
	elif "--autoback" in test_args:

		_show_menu()
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			var esc := InputEventKey.new()
			esc.pressed = true
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			Input.parse_input_event(esc))
	elif "--autoshop" in test_args:
		_show_menu()
		(_screen as MainMenu).open_shop()
	elif "--autorewards" in test_args:
		_show_menu()
		(_screen as MainMenu).open_rewards()
	elif "--autosettings" in test_args:
		_show_settings()
	elif "--autopicker" in test_args:
		_show_menu()
		(_screen as MainMenu).open_picker()
		for arg: String in test_args:
			if arg.begins_with("--autooffer="):
				for child in _screen.get_children():
					if child is CharacterPicker:
						child._offer(arg.get_slice("=", 1))
	elif "--autoprofile" in test_args:
		_show_menu()
		(_screen as MainMenu).open_profile()

		for arg: String in test_args:
			if arg.begins_with("--autophoto="):
				var editor: ProfileEditor = _screen.get_children().filter(
						func(c: Node) -> bool: return c is ProfileEditor)[0]
				editor._use_photo(arg.get_slice("=", 1))
				print("PHOTOTEST avatar=%s file=%s error='%s'" % [Settings.avatar,
						FileAccess.file_exists(Settings.AVATAR_PATH), editor._error.text])
	elif "--autopractice" in test_args:
		_show_menu()
		(_screen as MainMenu).open_practice()
	elif "--autolobby" in test_args:
		net.local_name = "Host"
		net.host_lobby()
		net.add_bot()
		for arg: String in test_args:
			if arg.begins_with("--bots="):
				for i in int(arg.get_slice("=", 1)):
					net.add_bot()
		_show_lobby(true)
		print("TEST_CODE %s ip=%s decoded=%s" % [net.game_code, JoinCode.local_ip(),
				JoinCode.decode(net.game_code)])
		if "--autoscroll" in test_args:

			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				var press := InputEventScreenTouch.new()
				press.pressed = true
				press.position = Vector2(640, 620)
				Input.parse_input_event(press)
				for step in 12:
					var drag := InputEventScreenDrag.new()
					drag.position = Vector2(640, 620 - step * 30)
					Input.parse_input_event(drag)
				var up := InputEventScreenTouch.new()
				up.pressed = false
				up.position = Vector2(640, 620 - 11 * 30)
				Input.parse_input_event(up)
				get_tree().create_timer(0.5).timeout.connect(func() -> void:
					var scroll := (_screen as LobbyScreen)._scroll
					print("TEST_SCROLL v=%d max=%d players=%d" % [scroll.scroll_vertical,
							scroll.get_v_scroll_bar().max_value - scroll.size.y,
							net.players.size()])))
	else:
		_show_menu()


func _bot_drives_me() -> void:
	if _game == null:
		return
	if not _game._loaded:
		await _game.loaded
	if _game == null or _game.local_pawn == null:
		return
	var brain := BotBrain.new()
	brain.game = _game
	_game.local_pawn.add_child(brain)
	_game.auto_local = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:

		_on_back()

func _on_back() -> void:
	var boxes := get_tree().get_nodes_in_group("confirm_box")
	if not boxes.is_empty():
		boxes.back().cancel()
	elif _game != null:
		_game.handle_back()
	elif _screen != null and _screen.has_method("go_back"):
		_screen.go_back()


func _leave_match_to_menu() -> void:
	if net.role != Net.Role.OFFLINE:
		net.leave()
	else:
		_teardown_game()
		_show_menu()

func _show_menu() -> void:
	_clear_screen()
	var menu := MainMenu.new()
	menu.practice_requested.connect(_start_practice)
	menu.host_requested.connect(_start_hosting)
	menu.join_requested.connect(_start_browsing)
	menu.settings_requested.connect(_show_settings)
	_screen = menu
	add_child(menu)

func _show_settings() -> void:
	_clear_screen()
	var settings := SettingsScreen.new()
	settings.closed.connect(_show_menu)
	_screen = settings
	add_child(settings)

func _start_practice(map: Arena.Shape, world: WorldTheme.Kind, fighter: String) -> void:
	_clear_screen()
	_game = Game.new()
	_game.map_shape = map
	_game.world = world
	_game.local_char = fighter
	_game.match_finished.connect(func() -> void:
		_teardown_game()
		_show_menu()
		if not OS.get_cmdline_user_args().is_empty():
			print("TEST_BACK_TO_MENU coins=%d matches=%d level=%d" % [Progress.coins,
					Progress.matches, Progress.level_info()["level"]]))
	_game.exit_requested.connect(_leave_match_to_menu)
	add_child(_game)

func _start_hosting(map: Arena.Shape, world: WorldTheme.Kind,
		fighter: String, pname: String) -> void:
	net.local_name = pname
	net.local_char = fighter
	net.map_shape = map
	net.world = world
	if net.host_lobby() == OK:
		_show_lobby(true)

func _start_browsing(fighter: String, pname: String) -> void:
	net.local_name = pname
	net.local_char = fighter
	_clear_screen()
	var browse := BrowseScreen.new()
	browse.net = net
	browse.joined.connect(func() -> void: _show_lobby(false))
	browse.cancelled.connect(_show_menu)
	_screen = browse
	add_child(browse)

func _show_lobby(as_host: bool) -> void:
	_clear_screen()
	var lobby := LobbyScreen.new()
	lobby.net = net
	lobby.is_host = as_host
	lobby.left.connect(_show_menu)
	_screen = lobby
	add_child(lobby)

func _enter_match() -> void:
	_clear_screen()
	_game = Game.new()
	_game.net = net
	_game.map_shape = net.map_shape
	_game.world = net.world
	_game.exit_requested.connect(_leave_match_to_menu)
	add_child(_game)

func _exit_match_to_lobby() -> void:
	_teardown_game()
	if net.role != Net.Role.OFFLINE:
		_show_lobby(net.role == Net.Role.HOST)
	else:
		_show_menu()

func _on_disconnected(reason: String) -> void:
	_teardown_game()
	_show_menu()
	if not reason.is_empty() and _screen is MainMenu:
		var toast := Label.new()
		toast.text = reason
		toast.add_theme_font_size_override("font_size", 30)
		toast.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
		toast.offset_top -= 60
		toast.offset_bottom -= 60
		_screen.add_child(toast)

func _teardown_game() -> void:
	get_tree().paused = false
	if _game != null:
		get_viewport().disable_3d = false
		net.game = null
		_game.queue_free()
		_game = null

func _clear_screen() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
