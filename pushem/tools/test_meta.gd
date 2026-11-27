extends SceneTree
## Headless checks for the progression, ad-cadence and store logic.
## Run: godot --headless --path . --script res://tools/test_meta.gd
## (use a throwaway XDG_DATA_HOME so it never touches a real save).

var _failed := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", what])


class CountingAds:
	extends Ads.Provider
	var rewarded := 0
	var interstitials := 0

	func is_rewarded_ready() -> bool:
		return true

	func is_interstitial_ready() -> bool:
		return true

	func show_rewarded(_p: String, on_done: Callable) -> void:
		rewarded += 1
		on_done.call(true)

	func show_interstitial(_p: String, on_closed: Callable) -> void:
		interstitials += 1
		on_closed.call()


func _init() -> void:
	Progress.load_from_disk()
	Progress.coins = 0
	Progress.xp = 0
	Progress.owned.clear()
	Progress.purchases.clear()
	Progress.no_ads = false
	Progress.matches = 0
	Progress.win_streak = 0
	Progress.daily_day = -1
	Progress.daily_streak = 0

	# --- match payouts ---
	var r := Progress.record_match({"place": 1, "players": 4, "kos": 3, "powerups": 1})
	_check(r["coins"] == 10 + 18 + 40, "win with 3 KOs pays 68 coins (got %d)" % r["coins"])
	_check(r["xp"] == 100 and r["level_after"] == 2, "100 XP reaches level 2")
	_check(Progress.coins == 68 + Progress.COINS_PER_LEVEL, "level-up bonus is banked")
	r = Progress.record_match({"place": 1, "players": 4, "kos": 0})
	_check(r["streak"] == 2 and r["coins"] == 10 + 40 + 5, "second win adds a streak bonus")
	r = Progress.record_match({"place": 2, "players": 4, "kos": 1})
	_check(r["coins"] == 10 + 6 + 15 and Progress.win_streak == 0, "runner-up pays 31 and resets the streak")
	r = Progress.record_match({"place": 4, "players": 4, "kos": 0})
	_check(r["coins"] == 10, "last place still pays the participation coins")
	r = Progress.record_match({"place": 1, "players": 1, "kos": 0})
	_check(r["coins"] == 10, "a one-player match is not a win")

	# --- fighters ---
	_check(Progress.owns("male_ninja") and Progress.owns("stick_man") and Progress.owns("muscle_man"),
			"one fighter per weight class is free")
	for wclass: PlayerPawn.WeightClass in Characters.CLASS_ORDER:
		var free := false
		for id in Characters.ids_of_class(wclass):
			free = free or Characters.price(id) == 0
		_check(free, "weight class %d has a free fighter" % wclass)
	Progress.coins = 399
	_check(not Progress.buy_fighter("female_ninja") and Progress.coins == 399, "cannot buy without enough coins")
	Progress.coins = 400
	_check(Progress.buy_fighter("female_ninja") and Progress.coins == 0 and Progress.owns("female_ninja"),
			"buying a fighter spends its price")
	_check(not Progress.buy_fighter("female_ninja"), "cannot buy a fighter twice")
	Progress.start_trial("chef")
	_check(Progress.can_use("chef") and not Progress.owns("chef"), "trial makes a fighter usable, not owned")
	_check(Progress.usable_fighter("armor") == Characters.DEFAULT, "locked fighter falls back to the default")
	Progress.record_match({"place": 3, "players": 4, "kos": 0})
	_check(not Progress.can_use("chef"), "trial ends after one match")

	# --- daily reward ---
	Progress.coins = 0
	Progress.daily_day = -1
	Progress.daily_streak = 0
	_check(Progress.daily_available() and Progress.daily_next_amount() == 50, "day 1 pays 50")
	_check(Progress.claim_daily() == 50 and not Progress.daily_available(), "claiming closes today's reward")
	_check(Progress.claim_daily() == 0, "cannot claim twice in one day")
	Progress.daily_day = Progress.today() - 1
	_check(Progress.daily_next_step() == 2 and Progress.claim_daily(2) == 150, "day 2 doubled by an ad pays 150")
	Progress.daily_day = Progress.today() - 3
	_check(Progress.daily_next_step() == 1, "a missed day resets the streak")
	Progress.daily_day = Progress.today() - 1
	Progress.daily_streak = 7
	_check(Progress.daily_next_step() == 1, "the 7-day loop wraps around")

	# --- quests ---
	Progress.quest_day = -1
	var quests := Progress.quests_today()
	_check(quests.size() == Progress.QUESTS_PER_DAY, "three quests are rolled per day")
	var stats := {}
	for q: Dictionary in quests:
		stats[Progress.quest_def(q["id"])["stat"]] = true
	_check(stats.size() == quests.size(), "the day's quests track different stats")
	for i in 10:
		Progress.record_match({"place": 1, "players": 4, "kos": 4, "powerups": 2, "online": true})
	_check(Progress.claimable_quests() == Progress.QUESTS_PER_DAY, "playing completes the quests")
	var before := Progress.coins
	var paid := Progress.claim_quest(0)
	_check(paid > 0 and Progress.coins == before + paid and Progress.claim_quest(0) == 0, "a quest pays out once")

	# --- store ---
	Store.provider = Store.SimProvider.new()
	Progress.coins = 0
	Progress.owned.clear()
	Store.buy(Store.STARTER_PACK, func(_ok: bool) -> void: pass)
	_check(Progress.coins == 1500 and Progress.owns("armor") and not Store.purchasable(Store.STARTER_PACK),
			"starter pack grants coins + Armor once")
	Store.grant(Store.STARTER_PACK)
	_check(Progress.coins == 1500, "restoring a one-time pack does not re-grant coins")
	Store.buy("coins_s", func(_ok: bool) -> void: pass)
	Store.buy("coins_s", func(_ok: bool) -> void: pass)
	_check(Progress.coins == 1500 + 2400, "coin packs are repeatable")
	Store.buy(Store.ALL_FIGHTERS, func(_ok: bool) -> void: pass)
	_check(Characters.locked_ids().is_empty(), "All Fighters unlocks the roster")
	Store.provider = null
	var refused := [false]
	Store.buy("coins_s", func(ok: bool) -> void: refused[0] = not ok)
	_check(refused[0], "no provider means no purchase")

	# --- ad cadence ---
	var ads := CountingAds.new()
	Ads.provider = ads
	Progress.no_ads = false
	Progress.matches = 0
	var done := [0]
	for i in 3:
		Progress.matches += 1
		Ads.after_match(func() -> void: done[0] += 1)
	_check(ads.interstitials == 0 and done[0] == 3, "no interstitial during the first three matches")
	Progress.matches += 1
	Ads.after_match(func() -> void: done[0] += 1)
	_check(ads.interstitials == 1, "first interstitial after the grace period")
	for i in 5:
		Progress.matches += 1
		Ads.after_match(func() -> void: done[0] += 1)
	_check(ads.interstitials == 1, "the time gap blocks back-to-back interstitials")
	Ads._last_interstitial_ms = -1000000
	Ads._matches_since = 0
	Progress.no_ads = true
	for i in 6:
		Progress.matches += 1
		Ads.after_match(func() -> void: done[0] += 1)
	_check(ads.interstitials == 1 and done[0] == 15, "Remove Ads stops interstitials, flow still continues")
	var got := [false]
	Ads.show_rewarded("test", func() -> void: got[0] = true)
	_check(got[0] and ads.rewarded == 1, "rewarded ads still work with Remove Ads")
	Progress.coins = 0
	Progress.adcoins_day = -1
	for i in 5:
		Progress.claim_ad_coins()
	_check(Progress.coins == Progress.AD_COINS * Progress.AD_COINS_PER_DAY, "ad coins are capped per day")
	Ads.provider = null
	_check(not Ads.rewarded_available(), "no provider hides every ad button")

	print("META_TESTS %s (%d failed)" % ["OK" if _failed == 0 else "FAILED", _failed])
	quit(1 if _failed > 0 else 0)
