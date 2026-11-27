class_name Characters
extends RefCounted


const DIR := "res://assets/characters/"
const DEFAULT := "male_ninja"

const LIST := {
	"female_ninja": {"name": "Female Ninja", "class": PlayerPawn.WeightClass.LIGHT,
			"file": "FemaleNinja.glb", "price": 400},
	"stick_man": {"name": "Stick Man", "class": PlayerPawn.WeightClass.LIGHT,
			"file": "StickMan.glb", "price": 0},
	"skeleton": {"name": "Skeleton", "class": PlayerPawn.WeightClass.LIGHT,
			"file": "Skeleton.glb", "price": 900},
	"male_ninja": {"name": "Male Ninja", "class": PlayerPawn.WeightClass.NORMAL,
			"file": "MaleNinja.glb", "price": 0},
	"ripped_female": {"name": "Ripped Female", "class": PlayerPawn.WeightClass.NORMAL,
			"file": "RippedFemale.glb", "price": 400},
	"ripped_male": {"name": "Ripped Male", "class": PlayerPawn.WeightClass.NORMAL,
			"file": "RippedMale.glb", "price": 600},
	"muscle_man": {"name": "Muscle Man", "class": PlayerPawn.WeightClass.HEAVY,
			"file": "MuscleMan.glb", "price": 0},
	"armor": {"name": "Armor", "class": PlayerPawn.WeightClass.HEAVY,
			"file": "ArmoredTank.glb", "price": 1200},
	"chef": {"name": "Chef", "class": PlayerPawn.WeightClass.HEAVY,
			"file": "Chef.glb", "price": 900},
}

const CLASS_ORDER := [
	PlayerPawn.WeightClass.LIGHT,
	PlayerPawn.WeightClass.NORMAL,
	PlayerPawn.WeightClass.HEAVY,
]
const CLASS_BLURBS := {
	PlayerPawn.WeightClass.LIGHT: "LIGHT\nquick · tiny hitbox\nflies far",
	PlayerPawn.WeightClass.NORMAL: "NORMAL\nbalanced",
	PlayerPawn.WeightClass.HEAVY: "HEAVY\nhits hard\nbig target",
}

static var _scenes := {}
static var _enhanced := {}
static var _outline_mat: StandardMaterial3D

static func valid(id: String) -> bool:
	return LIST.has(id)

static func display_name(id: String) -> String:
	return LIST[id]["name"] if LIST.has(id) else "?"

static func class_of(id: String) -> PlayerPawn.WeightClass:
	return LIST[id]["class"] if LIST.has(id) else PlayerPawn.WeightClass.NORMAL

static func ids_of_class(wclass: PlayerPawn.WeightClass) -> Array[String]:
	var out: Array[String] = []
	for id: String in LIST:
		if LIST[id]["class"] == wclass:
			out.append(id)
	return out

## Coin price of a fighter; 0 means free. One fighter per weight class is free,
## so paying never buys a stat advantage.
static func price(id: String) -> int:
	return int(LIST[id].get("price", 0)) if LIST.has(id) else 0

static func locked_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in LIST:
		if not Progress.owns(id):
			out.append(id)
	return out

static func random_id() -> String:
	return LIST.keys().pick_random()

static func random_of_class(wclass: PlayerPawn.WeightClass) -> String:
	return ids_of_class(wclass).pick_random()


static func scene(id: String) -> PackedScene:
	if not LIST.has(id):
		return null
	if not _scenes.has(id):
		_scenes[id] = load(DIR + LIST[id]["file"]) as PackedScene
		if _scenes[id] == null:
			push_warning("Characters: could not load %s" % LIST[id]["file"])
	return _scenes[id]


static func instantiate(id: String, outline := false) -> Node3D:
	var packed := scene(id)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	_enhance(model, outline)
	var ap := animation_player(model)
	if ap != null:
		for anim_name in ["Idle", "Walk"]:
			if ap.has_animation(anim_name):
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		if ap.has_animation("Idle"):
			ap.play("Idle")
	return model


static func _enhance(model: Node, outline: bool) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var tiny := mi.get_aabb().get_longest_axis_size() < 0.09
		var with_outline := outline and not tiny
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if not (src is StandardMaterial3D):
				continue
			var key := "%d_%s" % [src.get_instance_id(), with_outline]
			if not _enhanced.has(key):
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.rim_enabled = true
				mat.rim = 0.45
				mat.rim_tint = 0.35
				mat.roughness = clampf(mat.roughness, 0.45, 0.8)
				mat.metallic_specular = 0.6
				if with_outline:
					mat.next_pass = _outline()
				_enhanced[key] = mat
			mi.set_surface_override_material(i, _enhanced[key])

static func _outline() -> StandardMaterial3D:
	if _outline_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.05, 0.04, 0.06)
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		m.grow = true
		m.grow_amount = 0.018
		_outline_mat = m
	return _outline_mat

static func animation_player(model: Node) -> AnimationPlayer:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null
