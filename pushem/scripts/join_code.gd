class_name JoinCode
extends RefCounted


const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const LENGTH := 6


static func local_ip() -> String:
	var best := ""
	var best_rank := 99
	for ip: String in IP.get_local_addresses():
		var rank := _rank(ip)
		if rank < best_rank:
			best_rank = rank
			best = ip
	return best

static func _rank(ip: String) -> int:
	var p := ip.split(".")
	if p.size() != 4 or not ip.is_valid_ip_address():
		return 99
	if p[0] == "192" and p[1] == "168":
		return 0
	if p[0] == "10":
		return 1
	if p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31:
		return 2
	return 99


static func make(ip: String) -> String:
	var kind := 3
	var payload := randi() & 16777215
	var p := ip.split(".")
	match _rank(ip):
		0:
			kind = 0
			payload = (int(p[2]) << 8) | int(p[3])
		1:
			kind = 1
			payload = (int(p[1]) << 16) | (int(p[2]) << 8) | int(p[3])
		2:
			kind = 2
			payload = ((int(p[1]) - 16) << 16) | (int(p[2]) << 8) | int(p[3])
	var v := (kind << 24) | payload
	var bits := (v << 4) | _check(v)
	var out := ""
	for i in LENGTH:
		out = ALPHABET[bits & 31] + out
		bits >>= 5
	return out

static func _check(v: int) -> int:
	return ((v * 2654435761) >> 11) & 15


static func normalize(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ALPHABET.contains(ch):
			out += ch
	return out


static func pretty(code: String) -> String:
	return code.substr(0, 3) + "-" + code.substr(3) if code.length() == LENGTH else code


static func decode(text: String) -> Dictionary:
	var code := normalize(text)
	if code.length() != LENGTH:
		return {"ok": false}
	var bits := 0
	for ch in code:
		bits = (bits << 5) | ALPHABET.find(ch)
	var v := bits >> 4
	if _check(v) != (bits & 15):
		return {"ok": false}
	var kind := v >> 24
	var payload := v & 16777215
	var a := (payload >> 16) & 255
	var b := (payload >> 8) & 255
	var c := payload & 255
	match kind:
		0:
			return {"ok": a == 0, "ip": "192.168.%d.%d" % [b, c]}
		1:
			return {"ok": true, "ip": "10.%d.%d.%d" % [a, b, c]}
		2:
			return {"ok": a < 16, "ip": "172.%d.%d.%d" % [a + 16, b, c]}
	return {"ok": true, "ip": ""}
