class_name Art
extends RefCounted


const ROOT := "res://assets/"

static var _textures := {}
static var _manifests := {}


static func texture(rel_path: String) -> Texture2D:
	if rel_path.is_empty():
		return null
	if _textures.has(rel_path):
		return _textures[rel_path]
	var path := ROOT + rel_path
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("Art: no imported texture at %s — falling back to flat color." % path)
	_textures[rel_path] = tex
	return tex


static func manifest(rel_path: String) -> Variant:
	if _manifests.has(rel_path):
		return _manifests[rel_path]
	var path := ROOT + rel_path
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_warning("Art: %s is not valid JSON — ignoring it." % path)
	_manifests[rel_path] = parsed
	return parsed


static func color_from(value: Variant, fallback: Color) -> Color:
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


static func in_folder(folder: String, rel_path: String) -> String:
	var p := rel_path.strip_edges()
	if p.is_empty() or p.contains("/"):
		return p
	return folder + "/" + p
