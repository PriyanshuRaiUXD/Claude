class_name DeviceProfile
extends RefCounted


const PERF_PATH := "user://perf.cfg"

const SLOW_FPS := 40.0

const MIN_SECONDS := 20.0

const LOW := Settings.Quality.LOW
const MEDIUM := Settings.Quality.MEDIUM
const HIGH := Settings.Quality.HIGH

static var _measured := {}
static var _loaded := false

static func gpu_name() -> String:
	return RenderingServer.get_video_adapter_name()


static func memory_gb() -> float:
	var bytes := int(OS.get_memory_info().get("physical", -1))
	return bytes / 1073741824.0 if bytes > 0 else 0.0


static func _first_number(text: String) -> int:
	var digits := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else -1


static func gpu_tier(name: String, mobile: bool) -> int:
	var n := name.to_lower()
	if n.is_empty():
		return -1
	if "llvmpipe" in n or "swiftshader" in n or "basic render" in n or "software" in n:
		return LOW
	if "adreno" in n:
		var m := _first_number(n.substr(n.find("adreno")))
		if m >= 720 or (m >= 640 and m < 700):
			return HIGH
		if (m >= 710 and m < 720) or (m >= 615 and m < 640) or (m >= 530 and m < 600):
			return MEDIUM
		return LOW if m > 0 else MEDIUM
	if "immortalis" in n or "xclipse" in n or "apple" in n:
		return HIGH
	if "mali" in n:
		if "mali-t" in n or "mali t" in n or "mali-4" in n:
			return LOW
		var g := _first_number(n.substr(n.find("mali")))
		if g >= 100:
			var series := g / 100
			return HIGH if series >= 7 else (MEDIUM if series == 6 else LOW)
		if g >= 76:
			return HIGH
		return MEDIUM if g >= 57 else LOW
	if "powervr" in n or "img " in n:
		return LOW
	if not mobile:
		if "nvidia" in n or "geforce" in n or "quadro" in n or "radeon rx" in n or " arc" in n or "radeon pro" in n:

			return HIGH
		if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return HIGH
		return MEDIUM
	return -1


static func memory_tier(gb: float, mobile: bool) -> int:
	if gb <= 0.0:
		return HIGH
	if mobile:
		return LOW if gb < 3.0 else (MEDIUM if gb < 5.5 else HIGH)
	return LOW if gb < 3.5 else (MEDIUM if gb < 7.5 else HIGH)


static func hardware_quality() -> Settings.Quality:
	var mobile := OS.has_feature("mobile")
	var gpu := gpu_tier(gpu_name(), mobile)
	if gpu < 0:
		gpu = MEDIUM
	return mini(gpu, memory_tier(memory_gb(), mobile)) as Settings.Quality


static func recommended_quality() -> Settings.Quality:
	_load()
	var q: int = hardware_quality()
	while q > LOW and _measured.has(q) and float(_measured[q]) < SLOW_FPS:
		q -= 1
	return q as Settings.Quality


static func detail_for(q: Settings.Quality) -> int:
	return int(q)


static func describe() -> String:
	var parts: Array[String] = []
	var gpu := gpu_name().strip_edges()
	if not gpu.is_empty():
		parts.append(gpu)
	var gb := memory_gb()
	if gb > 0.0:
		parts.append("%d GB" % roundi(gb))
	_load()
	var q := hardware_quality()
	if recommended_quality() < q:
		parts.append("%s ran slow here" % Settings.QUALITY_NAMES[q])
	return " · ".join(parts)


static func record_match_fps(q: Settings.Quality, fps: float, seconds: float) -> void:
	if seconds < MIN_SECONDS or (Settings.fps_cap > 0 and Settings.fps_cap < 60):
		return
	_load()
	var prev := float(_measured.get(q, fps))
	_measured[q] = lerpf(prev, fps, 0.5)
	var cfg := ConfigFile.new()
	for level: int in _measured:
		cfg.set_value("fps", str(level), _measured[level])
	cfg.save(PERF_PATH)

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PERF_PATH) != OK:
		return
	for key: String in cfg.get_section_keys("fps"):
		var level := int(key)
		if level >= LOW and level <= HIGH:
			_measured[level] = float(cfg.get_value("fps", key, 60.0))
