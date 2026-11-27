extends SceneTree


func _init() -> void:
	var dir := "res://assets/characters/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		var scene := load(dir + f) as PackedScene
		if scene == null:
			print("MEASURE %s: failed to load" % f)
			continue
		var inst := scene.instantiate() as Node3D
		var box := AABB()
		var first := true
		var eyes_z := []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = _rel(mi, inst) * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
			if String(mi.name).begins_with("Eye") or String(mi.name).begins_with("Socket"):
				eyes_z.append(snappedf(_rel(mi, inst).origin.z, 0.01))
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		var anims := ""
		if not players.is_empty():
			var ap := players[0] as AnimationPlayer
			for a in ap.get_animation_list():
				anims += "%s(%.2fs loop=%d) " % [a, ap.get_animation(a).length, ap.get_animation(a).loop_mode]
		print("MEASURE %s pos=%s size=%s eyes_z=%s anims=%s" % [f, box.position, box.size, eyes_z, anims])
		inst.queue_free()
	print("MEASURE_DONE")


func _rel(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != top:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
