class_name Progress
extends RefCounted
## Persistent player progression and economy: coins, XP, fighter unlocks,
## daily reward streak, daily quests and lifetime stats.
##
## Everything lives on the device (user://progress.cfg). That is fine for a
## coins-for-cosmetics economy, but it is editable by a determined player —
## anything bought with real money must be re-validated through the store
## provider (see Store.restore) rather than trusted from this file.

const PATH := "user://progress.cfg"

# --- Match payouts -----------------------------------------------------------
const COINS_PLAY := 10
const COINS_KO := 6
const COINS_SECOND := 15
const COINS_WIN := 40
const COINS_STREAK := 5 # per consecutive win beyond the first, capped
const STREAK_CAP := 5
const XP_PLAY := 20
const XP_KO := 10
const XP_WIN := 50
const COINS_PER_LEVEL := 50

# --- Daily login reward (7-day loop) ----------------------------------------
const DAILY_REWARDS := [50, 75, 100, 150, 200, 300, 500]

# --- Daily quests ------------------------------------------------------------
# "stat" is a key of the per-match result dictionary passed to record_match().
const QUEST_POOL := [
	{"id": "play3", "text": "Play 3 matches", "stat": "played", "goal": 3, "reward": 60},
	{"id": "play5", "text": "Play 5 matches", "stat": "played", "goal": 5, "reward": 100},
	{"id": "ko4", "text": "Knock out 4 fighters", "stat": "kos", "goal": 4, "reward": 80},
	{"id": "ko8", "text": "Knock out 8 fighters", "stat": "kos", "goal": 8, "reward": 140},
	{"id": "win1", "text": "Win a match", "stat": "won", "goal": 1, "reward": 100},
	{"id": "win2", "text": "Win 2 matches", "stat": "won", "goal": 2, "reward": 180},
	{"id": "top2", "text": "Finish top 2 twice", "stat": "podium", "goal": 2, "reward": 90},
	{"id": "power3", "text": "Use 3 power-ups", "stat": "powerups", "goal": 3, "reward": 70},
	{"id": "online1", "text": "Play a match with friends", "stat": "online", "goal": 1, "reward": 120},
]
const QUESTS_PER_DAY := 3

# --- Opt-in "watch an ad for coins" in the shop ------------------------------
const AD_COINS := 40
const AD_COINS_PER_DAY := 3

static var coins := 0
static var xp := 0
static var owned: Array[String] = []
## Fighter id unlocked for exactly one match (rewarded-ad "try" placement).
static var trial := ""
static var matches := 0
static var wins := 0
static var kos := 0
static var win_streak := 0
static var best_streak := 0
static var sessions := 0
static var no_ads := false
static var purchases: Array[String] = []
static var daily_day := -1
static var daily_streak := 0
static var quest_day := -1
## Array of {"id", "have", "claimed"} for today's quests.
static var quests: Array = []
static var adcoins_day := -1
static var adcoins_count := 0
static var _loaded := false


static func load_from_disk() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		coins = maxi(0, int(cfg.get_value("wallet", "coins", 0)))
		xp = maxi(0, int(cfg.get_value("wallet", "xp", 0)))
		owned.assign(_strings(cfg.get_value("wallet", "owned", [])))
		purchases.assign(_strings(cfg.get_value("wallet", "purchases", [])))
		no_ads = bool(cfg.get_value("wallet", "no_ads", false))
		trial = str(cfg.get_value("wallet", "trial", ""))
		matches = int(cfg.get_value("stats", "matches", 0))
		wins = int(cfg.get_value("stats", "wins", 0))
		kos = int(cfg.get_value("stats", "kos", 0))
		win_streak = int(cfg.get_value("stats", "win_streak", 0))
		best_streak = int(cfg.get_value("stats", "best_streak", 0))
		sessions = int(cfg.get_value("stats", "sessions", 0))
		daily_day = int(cfg.get_value("daily", "day", -1))
		daily_streak = int(cfg.get_value("daily", "streak", 0))
		quest_day = int(cfg.get_value("daily", "quest_day", -1))
		adcoins_day = int(cfg.get_value("daily", "adcoins_day", -1))
		adcoins_count = int(cfg.get_value("daily", "adcoins_count", 0))
		var q: Variant = cfg.get_value("daily", "quests", [])
		quests = q if q is Array else []
	sessions += 1
	_roll_quests()
	save()


static func save() -> void:
	if not _loaded:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("wallet", "xp", xp)
	cfg.set_value("wallet", "owned", owned)
	cfg.set_value("wallet", "purchases", purchases)
	cfg.set_value("wallet", "no_ads", no_ads)
	cfg.set_value("wallet", "trial", trial)
	cfg.set_value("stats", "matches", matches)
	cfg.set_value("stats", "wins", wins)
	cfg.set_value("stats", "kos", kos)
	cfg.set_value("stats", "win_streak", win_streak)
	cfg.set_value("stats", "best_streak", best_streak)
	cfg.set_value("stats", "sessions", sessions)
	cfg.set_value("daily", "day", daily_day)
	cfg.set_value("daily", "streak", daily_streak)
	cfg.set_value("daily", "quest_day", quest_day)
	cfg.set_value("daily", "quests", quests)
	cfg.set_value("daily", "adcoins_day", adcoins_day)
	cfg.set_value("daily", "adcoins_count", adcoins_count)
	cfg.save(PATH)


static func _strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in v:
			out.append(str(item))
	return out


## Calendar day number in the player's local time zone.
static func today() -> int:
	var d := Time.get_date_dict_from_system()
	return int(Time.get_unix_time_from_datetime_dict(
			{"year": d["year"], "month": d["month"], "day": d["day"]}) / 86400)


# --- Wallet ------------------------------------------------------------------

static func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	save()


static func spend(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	save()
	return true


static func ad_coins_left() -> int:
	return AD_COINS_PER_DAY if adcoins_day != today() else maxi(0, AD_COINS_PER_DAY - adcoins_count)


static func claim_ad_coins() -> int:
	if ad_coins_left() <= 0:
		return 0
	if adcoins_day != today():
		adcoins_day = today()
		adcoins_count = 0
	adcoins_count += 1
	coins += AD_COINS
	save()
	return AD_COINS


# --- Levels ------------------------------------------------------------------

static func xp_for_level(level: int) -> int:
	return 100 + 50 * (level - 1)


## Returns {"level", "into", "need"} for a total XP amount.
static func level_info(total_xp := -1) -> Dictionary:
	var left := xp if total_xp < 0 else total_xp
	var level := 1
	while left >= xp_for_level(level):
		left -= xp_for_level(level)
		level += 1
	return {"level": level, "into": left, "need": xp_for_level(level)}


# --- Fighters ----------------------------------------------------------------

static func owns(id: String) -> bool:
	return Characters.price(id) <= 0 or owned.has(id)


static func can_use(id: String) -> bool:
	return owns(id) or (not trial.is_empty() and trial == id)


static func unlock(id: String) -> void:
	if Characters.valid(id) and not owned.has(id):
		owned.append(id)
	if trial == id:
		trial = ""
	save()


static func buy_fighter(id: String) -> bool:
	if not Characters.valid(id) or owns(id):
		return false
	if not spend(Characters.price(id)):
		return false
	unlock(id)
	return true


static func start_trial(id: String) -> void:
	trial = id
	save()


## The fighter to actually field: the wanted one if usable, else a free one.
static func usable_fighter(wanted: String) -> String:
	return wanted if Characters.valid(wanted) and can_use(wanted) else Characters.DEFAULT


# --- Daily reward ------------------------------------------------------------

static func daily_available() -> bool:
	return daily_day != today()


## Which day (1-7) of the loop the next claim pays out.
static func daily_next_step() -> int:
	var streak := daily_streak + 1 if daily_day == today() - 1 else 1
	return (streak - 1) % DAILY_REWARDS.size() + 1


static func daily_next_amount() -> int:
	return DAILY_REWARDS[daily_next_step() - 1]


## Claims today's reward. Returns the coins granted (0 if already claimed).
static func claim_daily(multiplier := 1) -> int:
	if not daily_available():
		return 0
	var amount := daily_next_amount() * maxi(1, multiplier)
	daily_streak = daily_streak + 1 if daily_day == today() - 1 else 1
	daily_day = today()
	coins += amount
	save()
	return amount


# --- Quests ------------------------------------------------------------------

static func _roll_quests() -> void:
	var day := today()
	if quest_day == day and quests.size() == QUESTS_PER_DAY:
		return
	quest_day = day
	quests = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pushem-quests-%d" % day)
	var pool := QUEST_POOL.duplicate()
	var used_stats := {}
	while quests.size() < QUESTS_PER_DAY and not pool.is_empty():
		var pick: Dictionary = pool.pop_at(rng.randi() % pool.size())
		if used_stats.has(pick["stat"]):
			continue
		used_stats[pick["stat"]] = true
		quests.append({"id": pick["id"], "have": 0, "claimed": false})


static func quest_def(id: String) -> Dictionary:
	for q: Dictionary in QUEST_POOL:
		if q["id"] == id:
			return q
	return {}


static func quests_today() -> Array:
	_roll_quests()
	return quests


static func quest_done(q: Dictionary) -> bool:
	var def := quest_def(q.get("id", ""))
	return not def.is_empty() and int(q.get("have", 0)) >= int(def["goal"])


static func claimable_quests() -> int:
	var n := 0
	for q: Dictionary in quests_today():
		if quest_done(q) and not q.get("claimed", false):
			n += 1
	return n


## Pays out a finished quest. Returns the coins granted.
static func claim_quest(index: int) -> int:
	var list := quests_today()
	if index < 0 or index >= list.size():
		return 0
	var q: Dictionary = list[index]
	if q.get("claimed", false) or not quest_done(q):
		return 0
	q["claimed"] = true
	var reward := int(quest_def(q["id"])["reward"])
	coins += reward
	save()
	return reward


# --- Match results -----------------------------------------------------------

## Books one finished match and returns the payout breakdown:
## {"rows": [[label, coins], ...], "coins", "xp", "level_before", "level_after",
##  "level_bonus", "streak"}.
## `result` keys: place (1 = winner), players, kos, powerups, online (bool).
static func record_match(result: Dictionary) -> Dictionary:
	var place := int(result.get("place", 0))
	var players := int(result.get("players", 0))
	var match_kos := int(result.get("kos", 0))
	var won := place == 1 and players > 1
	var rows: Array = [["Match played", COINS_PLAY]]
	var gained_xp := XP_PLAY + XP_KO * match_kos
	if match_kos > 0:
		rows.append(["%d knockout%s" % [match_kos, "" if match_kos == 1 else "s"],
				COINS_KO * match_kos])
	if won:
		rows.append(["Victory", COINS_WIN])
		gained_xp += XP_WIN
		win_streak += 1
		best_streak = maxi(best_streak, win_streak)
		if win_streak > 1:
			rows.append(["Win streak x%d" % win_streak,
					COINS_STREAK * mini(win_streak - 1, STREAK_CAP)])
	else:
		if place == 2 and players > 2:
			rows.append(["Runner-up", COINS_SECOND])
		win_streak = 0
	var total := 0
	for row: Array in rows:
		total += int(row[1])

	var before := int(level_info()["level"])
	xp += gained_xp
	var after := int(level_info()["level"])
	var level_bonus := COINS_PER_LEVEL * (after - before)

	matches += 1
	kos += match_kos
	if won:
		wins += 1
	coins += total + level_bonus

	var stats := {"played": 1, "kos": match_kos, "won": 1 if won else 0,
			"podium": 1 if place > 0 and place <= 2 and players > 2 else 0,
			"powerups": int(result.get("powerups", 0)),
			"online": 1 if result.get("online", false) else 0}
	for q: Dictionary in quests_today():
		var def := quest_def(q["id"])
		if not def.is_empty():
			q["have"] = mini(int(def["goal"]), int(q["have"]) + int(stats.get(def["stat"], 0)))
	# A trial fighter lasts one match.
	trial = ""
	save()
	return {"rows": rows, "coins": total, "xp": gained_xp, "level_before": before,
			"level_after": after, "level_bonus": level_bonus, "streak": win_streak}
