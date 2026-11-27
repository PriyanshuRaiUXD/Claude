class_name Settings
extends RefCounted


const PATH := "user://settings.cfg"

const MUSIC_DEFAULT := 0.6
const SFX_DEFAULT := 1.0


const ZOOM_DEFAULT := 0.55


const STICK_FLOATING := 0
const STICK_FIXED := 1
const STICK_POS_DEFAULT := Vector2(0.13, 0.79)


enum Quality {LOW, MEDIUM, HIGH}
const QUALITY_NAMES := {Quality.LOW: "Low", Quality.MEDIUM: "Medium", Quality.HIGH: "High"}


const QUALITY := {
	Quality.LOW: {
		"render_scale": 0.8, "msaa": Viewport.MSAA_2X, "fxaa": false,
		"shadows": false, "shadow_size": 1024, "octaves": 3, "glow": false, "outline": false,
		"world_detail": 0, "shadow_filter": RenderingServer.SHADOW_QUALITY_HARD,
		"sky_radiance": Sky.RADIANCE_SIZE_32,
	},
	Quality.MEDIUM: {
		"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "fxaa": false,
		"shadows": true, "shadow_size": 2048, "octaves": 4, "glow": true, "outline": false,
		"world_detail": 1, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"sky_radiance": Sky.RADIANCE_SIZE_64,
	},
	Quality.HIGH: {
		"render_scale": 1.0, "msaa": Viewport.MSAA_4X, "fxaa": false,
		"shadows": true, "shadow_size": 4096, "octaves": 5, "glow": true, "outline": true,
		"world_detail": 2, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"sky_radiance": Sky.RADIANCE_SIZE_128,
	},
}


static var fighter := "male_ninja"

const NAME_MAX := 14
static var player_name := ""


const AVATAR_CUSTOM := "custom"
const AVATAR_PATH := "user://avatar.png"
static var avatar := ""

static var last_map := 2
static var last_world := 2
static var zoom := ZOOM_DEFAULT
static var stick_mode := STICK_FLOATING
static var stick_pos := STICK_POS_DEFAULT
static var graphics: Quality = Quality.HIGH

const FPS_CAPS := [30, 60, 90, 120, 0]
static var fps_cap := 60

static var show_fps := false

static var scenery := 2

static var effects := 2
static var music_volume := MUSIC_DEFAULT
static var sfx_volume := SFX_DEFAULT


static func default_quality() -> Quality:
	return DeviceProfile.recommended_quality()


static func default_detail() -> int:
	return DeviceProfile.detail_for(default_quality())

static func default_fps_cap() -> int:
	return 60 if OS.has_feature("mobile") else 0

static func quality() -> Dictionary:
	return QUALITY[graphics]

static func load_from_disk() -> void:
	graphics = default_quality()
	fps_cap = default_fps_cap()
	scenery = default_detail()
	effects = default_detail()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("audio", "music", MUSIC_DEFAULT)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", SFX_DEFAULT)), 0.0, 1.0)
	zoom = clampf(float(cfg.get_value("controls", "zoom", ZOOM_DEFAULT)), 0.0, 1.0)
	stick_mode = STICK_FIXED if int(cfg.get_value("controls", "stick_mode",
			STICK_FLOATING)) == STICK_FIXED else STICK_FLOATING
	var sp: Variant = cfg.get_value("controls", "stick_pos", STICK_POS_DEFAULT)
	stick_pos = (sp as Vector2).clamp(Vector2(0.05, 0.1), Vector2(0.6, 0.95)) if sp is Vector2 else STICK_POS_DEFAULT

	graphics = clampi(int(cfg.get_value("video", "graphics", default_quality())),
			Quality.LOW, Quality.HIGH) as Quality
	fighter = str(cfg.get_value("player", "fighter", fighter))
	player_name = str(cfg.get_value("player", "name", "")).strip_edges().left(NAME_MAX)
	avatar = str(cfg.get_value("player", "avatar", ""))
	last_map = int(cfg.get_value("player", "map", last_map))
	last_world = int(cfg.get_value("player", "world", last_world))
	var cap := int(cfg.get_value("video", "fps_cap", default_fps_cap()))
	fps_cap = cap if cap in FPS_CAPS else default_fps_cap()
	show_fps = bool(cfg.get_value("video", "show_fps", false))
	scenery = clampi(int(cfg.get_value("video", "scenery", default_detail())), 0, 2)
	effects = clampi(int(cfg.get_value("video", "effects", default_detail())), 0, 2)

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "zoom", zoom)
	cfg.set_value("controls", "stick_mode", stick_mode)
	cfg.set_value("controls", "stick_pos", stick_pos)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "scenery", scenery)
	cfg.set_value("video", "effects", effects)
	cfg.set_value("player", "fighter", fighter)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "avatar", avatar)
	cfg.set_value("player", "map", last_map)
	cfg.set_value("player", "world", last_world)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(PATH)

static func reset_defaults() -> void:
	zoom = ZOOM_DEFAULT
	stick_mode = STICK_FLOATING
	stick_pos = STICK_POS_DEFAULT
	graphics = default_quality()
	fps_cap = default_fps_cap()
	show_fps = false
	scenery = default_detail()
	effects = default_detail()
	music_volume = MUSIC_DEFAULT
	sfx_volume = SFX_DEFAULT


static func apply_graphics(viewport: Viewport) -> void:
	var q := quality()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q["render_scale"] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR

	viewport.scaling_3d_scale = q["render_scale"]
	viewport.fsr_sharpness = 0.25
	viewport.msaa_3d = q["msaa"]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED

	RenderingServer.directional_shadow_atlas_set_size(q["shadow_size"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["shadow_filter"])
	Engine.max_fps = fps_cap
