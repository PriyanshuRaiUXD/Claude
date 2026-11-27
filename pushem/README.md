# Push 'Em

WLAN sumo brawler for Android: flick to dash, push everyone off the arena, be
the last one standing. Godot 4.7.1, GDScript, Mobile (Vulkan) renderer.

This folder is the editable project. It was reconstructed from the
`pushem_4.apk` build (v0.1.0): the compiled scripts were decompiled back to
GDScript, and the imported models, textures and font were converted back to
source files. Original code comments were not in the APK and are gone;
everything else runs identically to that build.

## Run and build

```sh
godot --path .                      # play on desktop
godot --path . -- --autotest        # jump straight into a bot match
godot --headless --path . --script res://tools/test_meta.gd   # economy/ads/store tests
godot --headless --path . --export-debug "Android" build/pushem.apk
```

The Android export needs the Godot 4.7.1 export templates, an Android SDK
(build-tools 35, platform 35), a JDK and a debug keystore set in Godot's
editor settings. `export_presets.cfg` is checked in.

## What 0.2.0 adds on top of the recovered 0.1.0

**Progression and economy** (`scripts/progress.gd`)

- Coins and XP for every match: participation, per knockout, runner-up, win,
  win streak, plus a coin bonus on each level-up.
- Six of the nine fighters cost coins (400-1,200). One fighter in each weight
  class is free and paid fighters share the same three stat blocks, so nothing
  for sale changes match balance.
- Daily login bonus on a 7-day loop and three daily quests.
- Saved to `user://progress.cfg`.

**Monetisation hooks**

- `scripts/ads.gd` — ad facade with the placement rules built in: rewarded ads
  are always opt-in; interstitials only after the results screen, never in the
  first three matches, at most one per three matches and per 150 seconds, never
  in online matches, never after "Remove Ads".
- `scripts/store.gd` — real-money catalog (starter pack, remove ads, all
  fighters, three coin packs) and what each product grants.
- Rewarded placements: double match coins, double daily bonus, try a locked
  fighter for one match, capped free coins in the shop.

**Both are facades with no SDK behind them yet.** Debug builds (and
`--simads` / `--simiap`) use simulated providers that show a labelled "TEST
AD" card and grant purchases for free, so every flow can be played through.
A release build with no provider shows no ads and disables purchase buttons.
To go live, subclass `Ads.Provider` and `Store.Provider` around the real
plugins (for example AdMob/AppLovin MAX and Google Play Billing) and assign
them before the first screen in `scripts/main.gd`.

**Match presentation**

- Knockout credit: the last fighter to hit you within six seconds gets the KO.
  Shown in a kill feed and a centre "KO!" pop for your own.
- Victory moment: slow motion, the camera swings down and orbits the winner,
  confetti, then a results screen with the payout breakdown.
- Ground shockwave on heavy hits, a themed plume where fighters fall off, a
  back light so fighters separate from the floor, a soft vignette, and
  three-point lighting on every fighter preview.

## Before shipping with real ads

- Show a consent prompt (a Google-certified CMP such as UMP) before any ad SDK
  initialises, and add a neutral age screen: a brawler attracts minors, and
  personalised ads to them are barred or restricted in most markets.
- Fill in Google Play's Data safety form for everything the ad SDKs collect and
  publish a privacy policy naming each SDK.
- Purchases recorded in `user://progress.cfg` are trusted locally. Re-validate
  owned products through the store provider's `restore()` on start-up.

See `docs/market-research.md` for how comparable games monetise, what their
SDK stacks collect, and why the feature order above was chosen.

## Test hooks

Arguments after `--` drive the game for automated checks, for example
`--autotest --results --autoend=2 --autocontinue` (scripted match that ends in
a win and returns to the menu), `--autoshop`, `--autorewards`,
`--autopicker --autooffer=chef`, `--coins=1000`, `--shot=out.png@8`.
