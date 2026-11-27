# Market research: monetisation and data collection in comparable games

Compiled 2026-11-27 to decide what Push 'Em should build.

## How far to trust this

- **Revenue and benchmark figures were read from search-result summaries of
  the cited pages**, not the full pages (most analyst sites were blocked from
  the research environment). Check exact wording and dates before relying on
  any number.
- **Third-party revenue estimates (AppMagic, Sensor Tower) count in-app
  purchases only.** They understate ad-funded games.
- **SDK data comes from AppGoblin, not Exodus Privacy** (Exodus was
  unreachable). AppGoblin counts companies per category; its numbers are not
  comparable to Exodus tracker counts.
- **Permissions come from Google Play's public permission listing**, which
  omits the advertising-ID, notification and billing permissions. Treat it as a
  lower bound.
- **Data safety entries are developer self-declarations** fetched from the live
  Play pages on 2026-11-27. Nobody here inspected network traffic.
- No competitor APK was downloaded or decompiled.

## 1. How the money is made

### 3D puzzle and hybrid-casual

| Game | What is known | Kind of figure | Source |
|---|---|---|---|
| Royal Match | $7bn+ lifetime; coins are the single currency for continues and lives | AppMagic estimate | https://www.pocketgamer.biz/royal-kingdom-surpasses-750m-with-42-of-all-revenue-made-in-h1-2026/ |
| Match Factory | about $308M lifetime, about $15M/month; $9.99 pass; 5 lives plus level timer | AppMagic estimate; store listing | https://www.blog.udonis.co/mobile-marketing/mobile-games/match-factory |
| Triple Match 3D | ads roughly half of revenue at launch; $11.1M IAP in Jan 2024 | Naavik / AppMagic estimates | https://naavik.co/digest/match-factory-pays-off/ |
| Hexa Sort | about 70/30 ads/IAP; rewarded video is the core; "No Ads" $4.99-$11.99 and reviews say it removes interstitials only | analyst estimate; store listing | https://maf.ad/en/blog/hexa-sort-hybrid-casual/ |
| Block Jam 3D | about $70k/day IAP, ads 30-35%; interstitial after every level, two rewarded placements; season pass, piggy bank, coin packs from $1.99 | analyst estimate | https://www.gamigion.com/?p=4855 |
| Mob Control | 85% ads / 15% IAP in its early hybrid phase; "$200M+" lifetime | Voodoo's own statements | https://voodoo.io/news/inside-voodoo-s-hit-the-story-of-mob-control-s-200m-rise |
| Screw puzzles | genre IAP above $27M in Q1 2025, about 4x year on year | AppMagic estimate | https://appmagic.rocks/blog/wool-sort-trend |

Nearly all top hybrid-casual games had a season pass by mid-2025 (AppMagic):
https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization

### Party and arena brawlers

| Game | What is known | Kind of figure | Source |
|---|---|---|---|
| Stumble Guys | $60M+ IAP and 265M downloads by 2023; $60M in 2023 falling to $23M in 2024 | third-party estimates | https://mobilegamer.biz/fall-guys-clone-stumble-guys-has-now-earned-over-60m-from-265m-downloads/ |
| Brawl Stars | about $662M in 2024; pass became real-money only in Jan 2024 | AppMagic via Statista; Supercell | https://supercell.com/en/games/brawlstars/blog/news/incoming-changes-to-the-brawl-pass/ |
| Smash Karts | ads are 70-80% of revenue; a banner shows for 5-7 seconds while the kart is destroyed | developer statement | https://www.google.co.jp/ads/publisher/stories/tall_team/ |
| Hole.io | 121M downloads in 2025; IAP revenue is trivial, so it is an ads business | third-party estimate | https://maf.ad/en/blog/top-mobile-games-2025/ |

No revenue data was found for Push'em All or Bump.io.

### Benchmarks

| Metric | Value | Source |
|---|---|---|
| Retention, median game | D1 22%, D7 4%, D30 0.7% | https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game |
| Retention, top 10% | D1 40%, D7 12%, D30 4% | same |
| Rewarded eCPM, US Android | $16.49 (Q4 2024) | https://appodeal.com/the-mobile-ecpm-report-updated-q4-2024-view |
| Interstitial eCPM, US Android | $10.11 | https://blog.playio.co/mobile-game-ecpm-benchmarks-2026 |
| Banner eCPM, US Android | about $0.60 | https://www.blog.udonis.co/mobile-marketing/mobile-apps/ecpms |
| Rewarded eCPM, India | $0.80-1.50 (weak source) | https://cas.ai/?p=11066 |
| ARPDAU, hypercasual | $0.01-0.08 | https://tenjin.com/glossary/average-revenue-per-daily-active-user-arpdau/ |
| ARPDAU, hybrid-casual | $0.10-0.50 | https://blog.playio.co/arpdau-benchmarks-mobile-games |

### What changed 2023-2026

- Apple's tracking prompt broke ad arbitrage: in 2022 iOS ad impressions fell
  20% and Android eCPM fell 28% (Tenjin). https://businessofapps.com/?p=86500
- Hypercasual went from 50% of installs (Q1 2021) to 30% (Q1 2023), and to
  about 1% of IAP revenue in 2025.
- Hybrid-casual revenue reached $788M in 2025, up 75% (AppMagic).
  https://www.pocketgamer.biz/what-happened-to-hypercasual-the-markets-evolution-over-the-past-year/
- Google retired the Android Privacy Sandbox APIs on 2025-10-17; the
  advertising ID remains the working identifier.
  https://privacysandbox.google.com/blog/update-on-plans-for-privacy-sandbox-technologies

## 2. What these games collect

| App | Ad-network companies / mediation SDKs | Dangerous permissions (Play listing) | Data safety highlights |
|---|---|---|---|
| Triple Match 3D | 18 / 3 | none | Declares no device IDs shared, despite 18 ad networks detected |
| Match 3D | 23 / 3 | none | Shares device IDs, approximate location, purchase history; "data isn't encrypted" |
| Match Factory! | 9 / 2 | none | Shares device IDs, approximate location, purchase history, interactions |
| Hexa Sort | 24 / 3 | approximate location | Shares device IDs, approximate location, purchase history |
| Block Jam 3D | 24 / 3 | none | Shares device IDs and location; declares no advertising purpose |
| Mob Control | 19 / 3 | none | Shares email, device IDs, approximate location for advertising |
| Push'em All | 22 / 3 | none | Shares device IDs and location; declares no advertising purpose |
| Royal Match | 6 / 2 | none | Shares device IDs and approximate location for advertising |
| Stumble Guys | 13 / 2 | none | Shares device IDs, approximate location, purchase history |
| Brawl Stars | 1 / 0 | camera, storage | Shares device IDs and app interactions |

Sources per app: `https://appgoblin.info/apps/<package>` and
`https://play.google.com/store/apps/datasafety?id=<package>`.

Three patterns:

- **Ad-funded games embed 18-24 ad-network companies; IAP-funded games embed
  1-9.**
- **Almost none request a dangerous permission.** The data moves through
  identifiers that need no prompt (advertising ID, app set ID) and the IP
  address, not through contacts, SMS or precise location.
- **Several self-declarations look inconsistent with the detected SDKs.**

What the ad SDKs read (verified for Google's SDK): IP address used to estimate
general location, app launches, taps and video views, diagnostics, the
advertising ID and the app set ID.
https://developers.google.com/admob/android/privacy/play-data-disclosure

What they cannot do on current Android: read the advertising ID without the
`AD_ID` manifest permission; link it to persistent IDs such as IMEI; use the
installed-app list for ads (prohibited); read contacts, SMS, microphone,
camera or precise location without a runtime prompt.
https://support.google.com/googleplay/android-developer/answer/10158779

### Enforcement record in this genre

- Voodoo: CNIL fined it EUR 3M (2022-12-29) for using a device identifier for
  ads after users refused tracking. https://cnil.fr/en/node/8705
- Jam City: $1.4M for no CCPA opt-out in 21 game apps.
  https://www.oag.ca.gov/news/press-releases/attorney-general-bonta-secures-14-million-settlement-mobile-app-gaming-company
- Tilting Point: $500K over misconfigured SDKs and children's data.
- HyperBeard: $150K (FTC) for letting ad networks track children.

## 3. Rules that constrain the design

- Google Play bans unexpected full-screen ads, including at the start of a
  level, and interstitials that cannot be closed after 15 seconds. Opt-in
  rewarded ads and natural breaks are allowed.
  https://support.google.com/googleplay/android-developer/answer/9857753
- Paid random items need odds disclosed before purchase, default to PEGI 16
  for new submissions from June 2026, and need a "contains loot boxes" store
  disclosure in the UK.
- A Google-certified consent tool is required to serve personalised ads in the
  EEA, UK and Switzerland. https://support.google.com/admob/answer/13554116
- If children are in the audience, ads to them must come from Families
  self-certified SDKs with no personalised ads.
  https://support.google.com/googleplay/android-developer/answer/9900633
- India's DPDP Act duties apply from May 2027; "child" means under 18, and
  tracking or targeted ads aimed at children are barred.
  https://www.amsshardul.com/insight/enforcement-of-the-dpdp-act-and-notification-of-the-dpdp-rules/
- The EU Digital Fairness Act (proposed 2026-11-11, not law) would ban paid
  loot boxes and pay-to-win for minors.

## 4. What Push 'Em builds, and in what order

Judgment, not sourced fact.

| # | Feature | Status in 0.2.0 |
|---|---|---|
| 1 | Rewarded video, 3-4 opt-in placements | Built (simulated provider) |
| 2 | Interstitials at natural breaks + Remove Ads | Built (simulated provider) |
| 3 | Web build on Poki / CrazyGames for free distribution | Not started |
| 4 | One-time starter pack | Built |
| 5 | Direct-purchase shop, no randomness | Built |
| 6 | Daily quests, login reward, win streak | Built |
| 7 | Season pass | Deferred until D7 retention is about 8% or better |
| 8 | Weekend events | Not started |

Deliberately not built: paid loot boxes, pay-to-win power-ups, lives/energy
(they starve multiplayer lobbies), subscriptions, offerwalls, in-match banners.

Recommended SDK set when going live: one mediation layer with three or four
networks, Google UMP for consent, one analytics/crash SDK, Play Billing, no
attribution SDK until ads are being bought, and a random player ID rather than
an email.

### Revenue model per 1,000 daily players (a model, not sourced)

| Scenario | Assumptions | Per day | Per month |
|---|---|---|---|
| Low | tier-3-heavy organic Android, near-zero IAP | $3-5 | $100-150 |
| Mid | about 20% tier-1 players, IAP ARPDAU $0.01 | about $25 | about $750 |
| High | 40%+ tier-1, working starter pack | $80-100 | $2,400-3,000 |

At median retention, holding 1,000 daily players needs roughly 300-400 new
installs every day. Distribution, not the feature list, is the constraint.
