class_name Store
extends RefCounted
## Real-money store facade. The catalog and what each product grants live
## here; the actual payment goes through a Provider (Google Play Billing on
## Android). Assign `Store.provider` at start-up.
##
## Design rules this catalog follows on purpose:
##  * Nothing sold changes match balance — every weight class has a free
##    fighter, and paid fighters use the same three stat blocks.
##  * No random paid items (no loot boxes), so no odds disclosure / PEGI 16.
##  * "Remove Ads" removes the forced interstitials only; optional rewarded
##    ads stay because they are player-initiated. The shop text says so.

const REMOVE_ADS := "remove_ads"
const STARTER_PACK := "starter_pack"
const ALL_FIGHTERS := "all_fighters"

## "price" is the fallback label; a real provider returns the localized price.
const CATALOG := {
	"starter_pack": {"title": "Starter Pack", "price": "$1.99", "one_time": true,
			"blurb": "Armor fighter + 1,500 coins", "coins": 1500, "fighters": ["armor"]},
	"remove_ads": {"title": "Remove Ads", "price": "$2.99", "one_time": true,
			"blurb": "No more ads between matches.\nOptional reward ads stay."},
	"all_fighters": {"title": "All Fighters", "price": "$4.99", "one_time": true,
			"blurb": "Unlock every fighter, now and future"},
	"coins_s": {"title": "Pouch of Coins", "price": "$0.99", "coins": 1200,
			"blurb": "1,200 coins"},
	"coins_m": {"title": "Sack of Coins", "price": "$2.99", "coins": 4000,
			"blurb": "4,000 coins"},
	"coins_l": {"title": "Chest of Coins", "price": "$7.99", "coins": 12000,
			"blurb": "12,000 coins"},
}
const ORDER := ["starter_pack", "remove_ads", "all_fighters", "coins_s", "coins_m", "coins_l"]


## Subclass this to connect Google Play Billing (or another store).
class Provider:
	extends RefCounted

	## Localized price string, or "" to use the catalog fallback.
	func price_label(_product: String) -> String:
		return ""

	## Must call on_result.call(ok: bool) exactly once.
	func purchase(_product: String, on_result: Callable) -> void:
		on_result.call(false)

	## Re-reads owned non-consumables from the store and returns their ids
	## through on_result.call(ids: Array).
	func restore(on_result: Callable) -> void:
		on_result.call([])


static var provider: Provider


static func setup() -> void:
	if provider == null and (OS.is_debug_build() or "--simiap" in OS.get_cmdline_user_args()):
		provider = SimProvider.new()


static func available() -> bool:
	return provider != null


static func price_label(product: String) -> String:
	var live := provider.price_label(product) if provider != null else ""
	return live if not live.is_empty() else str(CATALOG[product]["price"])


static func owned(product: String) -> bool:
	return Progress.purchases.has(product)


## One-time products that are already owned (or made pointless) are hidden.
static func purchasable(product: String) -> bool:
	if not CATALOG.has(product):
		return false
	if CATALOG[product].get("one_time", false) and owned(product):
		return false
	if product == ALL_FIGHTERS and Characters.locked_ids().is_empty():
		return false
	return true


static func buy(product: String, on_result: Callable) -> void:
	if provider == null or not purchasable(product):
		on_result.call(false)
		return
	print("IAP_EVENT start product=%s" % product)
	provider.purchase(product, func(ok: bool) -> void:
		print("IAP_EVENT %s product=%s" % ["success" if ok else "cancelled", product])
		if ok:
			grant(product)
		on_result.call(ok))


## Applies what a product gives. Safe to call again for owned one-time items
## (restore): coins are only granted the first time.
static func grant(product: String) -> void:
	if not CATALOG.has(product):
		return
	var item: Dictionary = CATALOG[product]
	var first_time := not owned(product)
	if item.get("one_time", false):
		if first_time:
			Progress.purchases.append(product)
	if first_time or not item.get("one_time", false):
		Progress.coins += int(item.get("coins", 0))
	for id: String in item.get("fighters", []):
		Progress.unlock(id)
	if product == REMOVE_ADS:
		Progress.no_ads = true
	elif product == ALL_FIGHTERS:
		for id: String in Characters.LIST:
			Progress.unlock(id)
	Progress.save()


static func restore(on_done: Callable) -> void:
	if provider == null:
		on_done.call()
		return
	provider.restore(func(ids: Array) -> void:
		for id: Variant in ids:
			if CATALOG.has(str(id)) and CATALOG[str(id)].get("one_time", false):
				grant(str(id))
		on_done.call())


## Debug stand-in: every purchase succeeds instantly and costs nothing.
class SimProvider:
	extends Provider

	func price_label(product: String) -> String:
		return "%s (test)" % Store.CATALOG[product]["price"]

	func purchase(_product: String, on_result: Callable) -> void:
		on_result.call(true)
