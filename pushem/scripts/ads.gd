class_name Ads
extends RefCounted
## Ad facade. Game code only ever talks to this class; the real SDK plugs in
## as a Provider (assign `Ads.provider` at start-up, before the first screen).
##
## Policy baked in here, not in the provider:
##  * Rewarded ads are always opt-in (the player taps a button to watch).
##  * Interstitials only at a natural break (after the results screen), never
##    in the first few matches, never more often than every N matches / M secs,
##    and never for players who bought "Remove Ads".
##
## Without a provider (the default in release builds) nothing is shown and
## every ad button hides itself. Debug builds, or `--simads`, get a simulated
## provider so the whole flow can be tested without an ad account.

const INTERSTITIAL_GRACE_MATCHES := 3 # lifetime matches before the first one
const INTERSTITIAL_EVERY := 3 # matches between interstitials
const INTERSTITIAL_MIN_GAP_SECS := 150.0


## Subclass this to connect a real ad SDK (AdMob, AppLovin MAX, LevelPlay...).
class Provider:
	extends RefCounted

	func is_rewarded_ready() -> bool:
		return false

	## Must call on_done.call(earned: bool) exactly once.
	func show_rewarded(_placement: String, on_done: Callable) -> void:
		on_done.call(false)

	func is_interstitial_ready() -> bool:
		return false

	## Must call on_closed.call() exactly once.
	func show_interstitial(_placement: String, on_closed: Callable) -> void:
		on_closed.call()


static var provider: Provider
static var _matches_since := 0
static var _last_interstitial_ms := -1000000
static var _busy := false


static func setup() -> void:
	if provider == null and (OS.is_debug_build() or "--simads" in OS.get_cmdline_user_args()) and not "--noads" in OS.get_cmdline_user_args():
		provider = SimProvider.new()


static func rewarded_available() -> bool:
	return provider != null and not _busy and provider.is_rewarded_ready()


## Shows an opt-in rewarded ad. on_reward is called only if the reward was earned.
static func show_rewarded(placement: String, on_reward: Callable) -> void:
	if not rewarded_available():
		return
	_busy = true
	_log("rewarded_start", placement)
	provider.show_rewarded(placement, func(earned: bool) -> void:
		_busy = false
		_log("rewarded_earned" if earned else "rewarded_skipped", placement)
		if earned:
			on_reward.call())


## Call once per finished match, after the results screen. Shows an
## interstitial if one is due, then always calls on_done.
static func after_match(on_done: Callable) -> void:
	_matches_since += 1
	var now := Time.get_ticks_msec()
	var due := provider != null and not _busy and not Progress.no_ads and Progress.matches > INTERSTITIAL_GRACE_MATCHES and _matches_since >= INTERSTITIAL_EVERY and (now - _last_interstitial_ms) / 1000.0 >= INTERSTITIAL_MIN_GAP_SECS and provider.is_interstitial_ready()
	if not due:
		on_done.call()
		return
	_busy = true
	_matches_since = 0
	_last_interstitial_ms = now
	_log("interstitial", "after_match")
	provider.show_interstitial("after_match", func() -> void:
		_busy = false
		on_done.call())


static func _log(event: String, placement: String) -> void:
	# Hook an analytics SDK in here; for now it is just a log line.
	print("AD_EVENT %s placement=%s" % [event, placement])


## Stand-in used in debug builds: a full-screen card that "plays" for a few
## seconds. It never contacts a network and never earns money.
class SimProvider:
	extends Provider

	const REWARDED_SECS := 3.0
	const INTERSTITIAL_SECS := 2.0

	func is_rewarded_ready() -> bool:
		return true

	func is_interstitial_ready() -> bool:
		return true

	func show_rewarded(placement: String, on_done: Callable) -> void:
		_card("TEST AD", "Rewarded · %s" % placement, REWARDED_SECS,
				func() -> void: on_done.call(true))

	func show_interstitial(placement: String, on_closed: Callable) -> void:
		_card("TEST AD", "Interstitial · %s" % placement, INTERSTITIAL_SECS, on_closed)

	func _card(title: String, sub: String, secs: float, on_end: Callable) -> void:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			on_end.call()
			return
		var layer := CanvasLayer.new()
		layer.layer = 100
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.03, 0.05, 0.97)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(bg)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 14)
		layer.add_child(box)
		box.add_child(UiKit.title(title, 72, UiKit.YELLOW))
		var line := UiKit.label(sub, 28, Color(0.8, 0.85, 0.95))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
		var note := UiKit.label("Simulated — no real ad network is connected.", 22,
				Color(0.6, 0.65, 0.75))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)
		tree.root.add_child(layer)
		# Ignore time scale and pause so slow-motion never stretches the "ad".
		tree.create_timer(secs, true, false, true).timeout.connect(func() -> void:
			layer.queue_free()
			on_end.call())
