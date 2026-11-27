class_name Net
extends Node


enum Role {OFFLINE, HOST, CLIENT}

const PORT := 38511

static var port_override := 0
const DISCOVERY_PORT := 38512
const MAX_PLAYERS := 8
const BEACON_MAGIC := "PUSHEM2"
const SNAPSHOT_HZ := 30.0
const STATE_HZ := 30.0


class Clock:
	var offset := 0.0
	var jitter := 0.0
	var interval := 1.0 / 30.0
	var _has := false
	var _last := -1.0

	static func now() -> float:
		return Time.get_ticks_usec() / 1000000.0

	func sample(remote_t: float) -> void:
		var o := now() - remote_t
		if not _has:
			offset = o
			_has = true
		elif o < offset:
			offset = o
		else:
			offset += (o - offset) * 0.01
		jitter = lerpf(jitter, o - offset, 0.08)
		if _last > 0.0 and remote_t > _last and remote_t - _last < 0.5:
			interval = lerpf(interval, remote_t - _last, 0.1)
		_last = remote_t

	func to_local(remote_t: float) -> float:
		return remote_t + offset

	func remote_now() -> float:
		return now() - offset

	func delay() -> float:
		return clampf(interval * 1.5 + jitter * 1.5, 0.04, 0.22)

	func render_time() -> float:
		return remote_now() - delay()

signal lobby_changed
signal match_started
signal match_ended
signal hosts_updated(hosts: Dictionary)
signal disconnected(reason: String)

var role: Role = Role.OFFLINE

var players := {}
var map_shape: Arena.Shape = Arena.Shape.CIRCLE
var world: WorldTheme.Kind = WorldTheme.Kind.WINDY
var host_is_player := true
var lite_render := false
var game_code := ""

var local_name := "Player"
var local_char := Characters.DEFAULT

var game: Game

var ready_peers := {}

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_accum := 0.0
var _found_hosts := {}
var _next_bot_id := -1

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _teardown("Could not connect."))
	multiplayer.server_disconnected.connect(func() -> void: _teardown("Host left the game."))

static func game_port() -> int:
	return port_override if port_override > 0 else PORT

func is_authority() -> bool:
	return role != Role.CLIENT

func my_id() -> int:
	return multiplayer.get_unique_id() if role != Role.OFFLINE else 1


func host_lobby() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(game_port(), MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	game_code = JoinCode.make(JoinCode.local_ip())
	players.clear()
	_next_bot_id = -1
	if host_is_player:
		players[1] = _entry(local_name, local_char, false)
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	lobby_changed.emit()
	return OK

func set_host_plays(plays: bool) -> void:
	host_is_player = plays
	if role != Role.HOST:
		return
	if plays and not players.has(1):
		players[1] = _entry(local_name, local_char, false)
	elif not plays:
		players.erase(1)
	_broadcast_lobby()

func add_bot() -> void:
	if role != Role.HOST or players.size() >= MAX_PLAYERS:
		return
	var bot_names := ["Rocky", "Zippy", "Bo", "Tank", "Pip", "Mo", "Dot", "Slab"]
	players[_next_bot_id] = _entry(bot_names[(-_next_bot_id - 1) % bot_names.size()],
			Characters.random_id(), true)
	_next_bot_id -= 1
	_broadcast_lobby()


func set_bot_character(id: int, char_id: String) -> void:
	if role != Role.HOST or not players.has(id) or not players[id]["bot"]:
		return
	players[id] = _entry(players[id]["name"], char_id, true)
	_broadcast_lobby()

func remove_bot(id: int) -> void:
	if role == Role.HOST and players.has(id) and players[id]["bot"]:
		players.erase(id)
		_broadcast_lobby()

func remove_bots() -> void:
	if role != Role.HOST:
		return
	for id: int in players.keys():
		if players[id]["bot"]:
			players.erase(id)
	_next_bot_id = -1
	_broadcast_lobby()

func set_map(shape: Arena.Shape) -> void:
	map_shape = shape
	if role == Role.HOST:
		_broadcast_lobby()

func set_world(kind: WorldTheme.Kind) -> void:
	world = kind
	if role == Role.HOST:
		_broadcast_lobby()

func start_match() -> void:
	if role == Role.HOST and players.size() >= 2:
		_stop_beacon()
		ready_peers.clear()
		_rpc_start.rpc(map_shape, world, players)
		_begin_local_match()


func start_browsing() -> void:
	_found_hosts.clear()
	_listener = PacketPeerUDP.new()
	_listener.bind(DISCOVERY_PORT)

func stop_browsing() -> void:
	if _listener != null:
		_listener.close()
		_listener = null

func join(ip: String) -> Error:
	stop_browsing()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, game_port())
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	return OK


func join_code(text: String) -> String:
	var code := JoinCode.normalize(text)
	for ip: String in _found_hosts:
		if str(_found_hosts[ip].get("code", "")) == code:
			return "" if join(ip) == OK else "Could not connect."
	var info := JoinCode.decode(code)
	if not info["ok"]:
		return "That code isn't right — check the letters."
	if str(info["ip"]).is_empty():
		return "No game with that code on this Wi-Fi yet."
	return "" if join(info["ip"]) == OK else "Could not connect."

func set_local_fighter(char_id: String) -> void:
	local_char = char_id
	if role == Role.CLIENT:
		_rpc_register.rpc_id(1, local_name, char_id)
	elif role == Role.HOST and players.has(1):
		players[1] = _entry(local_name, char_id, false)
		_broadcast_lobby()

static func _entry(pname: String, char_id: String, bot: bool) -> Dictionary:
	if not Characters.valid(char_id):
		char_id = Characters.DEFAULT
	return {"name": pname, "char": char_id,
			"class": Characters.class_of(char_id), "bot": bot}

func leave() -> void:
	_teardown("")


func _process(delta: float) -> void:
	if role == Role.HOST and _beacon != null:
		_beacon_accum += delta
		if _beacon_accum >= 1.0:
			_beacon_accum = 0.0
			var info := {"magic": BEACON_MAGIC, "name": local_name,
					"players": players.size(), "max": MAX_PLAYERS, "code": game_code}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data: Variant = JSON.parse_string(
					_listener.get_packet().get_string_from_utf8())
			if data is Dictionary and data.get("magic") == BEACON_MAGIC:
				_found_hosts[_listener.get_packet_ip()] = data
				changed = true
		if changed:
			hosts_updated.emit(_found_hosts)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(pname: String, char_id: String) -> void:
	if role != Role.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = _entry(pname, char_id, false)
	_broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(state: Dictionary) -> void:
	players = state["players"]
	map_shape = state["map"]
	world = state["world"]
	game_code = str(state.get("code", ""))
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_start(shape: int, world_kind: int, roster: Dictionary) -> void:
	map_shape = shape
	world = world_kind
	players = roster
	_begin_local_match()

@rpc("authority", "call_remote", "reliable")
func _rpc_end_match() -> void:
	_end_local_match()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_state(data: PackedByteArray) -> void:
	if role == Role.HOST and game != null:
		game.apply_client_state(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "call_remote", "reliable")
func report_knock(payload: Dictionary) -> void:
	if role == Role.HOST and game != null:
		game.apply_knock_report(multiplayer.get_remote_sender_id(), payload)


@rpc("any_peer", "call_remote", "reliable")
func report_release() -> void:
	if role == Role.HOST and game != null:
		game.apply_release_report(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func report_loaded() -> void:
	if role == Role.HOST:
		ready_peers[multiplayer.get_remote_sender_id()] = true

@rpc("any_peer", "call_remote", "reliable")
func request_push(direction: Vector3) -> void:
	if role == Role.HOST and game != null:
		game.apply_push(multiplayer.get_remote_sender_id(), direction)

@rpc("any_peer", "call_remote", "reliable")
func request_use() -> void:
	if role == Role.HOST and game != null:
		game.apply_use(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func request_cancel() -> void:
	if role == Role.HOST and game != null:
		game.apply_cancel(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func request_bomb(target: Vector3) -> void:
	if role == Role.HOST and game != null:
		game.apply_bomb(multiplayer.get_remote_sender_id(), target)

@rpc("any_peer", "call_remote", "reliable")
func request_jump(target: Vector3) -> void:
	if role == Role.HOST and game != null:
		game.apply_jump(multiplayer.get_remote_sender_id(), target)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(data: PackedByteArray) -> void:
	if game != null:
		game.apply_snapshot(data)

@rpc("authority", "call_remote", "reliable")
func game_event(kind: String, payload: Dictionary) -> void:
	if game != null:
		game.apply_event(kind, payload)


func send_snapshot(data: PackedByteArray) -> void:
	if role == Role.HOST:
		snapshot.rpc(data)

func send_event(kind: String, payload: Dictionary) -> void:
	if role == Role.HOST:
		game_event.rpc(kind, payload)
	if game != null:
		game.apply_event(kind, payload)

func end_match() -> void:
	if role == Role.HOST:
		_rpc_end_match.rpc()
		_end_local_match()
		_start_beacon_again()


func _begin_local_match() -> void:
	match_started.emit()

func _end_local_match() -> void:
	match_ended.emit()

func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if role == Role.HOST:
		_rpc_lobby.rpc({"players": players, "map": map_shape, "world": world,
				"code": game_code})

func _start_beacon_again() -> void:
	if role == Role.HOST and _beacon == null:
		_beacon = PacketPeerUDP.new()
		_beacon.set_broadcast_enabled(true)
		_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)

func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null

func _on_peer_connected(_id: int) -> void:

	pass

func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST:
		return
	players.erase(id)
	if game != null:
		game.drop_player(id)
	_broadcast_lobby()

func _on_connected_to_server() -> void:
	_rpc_register.rpc_id(1, local_name, local_char)

func _teardown(reason: String) -> void:
	_stop_beacon()
	stop_browsing()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	players.clear()
	game_code = ""
	game = null
	disconnected.emit(reason)
