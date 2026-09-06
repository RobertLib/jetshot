# Screenshots and App Preview

Screenshots are **not indexed for search**, and they decide almost everything after
it: in the search results a listing is its icon, its name, its subtitle and its
**first two screenshots**. Nothing else on this page is seen before the tap.

The media is **not made by hand and is not in git** — the scripts below produce it.
Uploading is manual: in App Store Connect drag the files into the *App Preview and
Screenshots* section (language switch at the top, one locale at a time).

## What the scripts produce

| What | Where | Resolution | Count |
|---|---|---|---|
| iPhone screenshots | `screenshots/<locale>/iphone-6.5/` | 1242 × 2688 (6.5" slot) | 8 |
| iPad 13" screenshots | `screenshots/<locale>/ipad-13/` | 2064 × 2752 | 8 |
| The same with captions | `screenshots-captioned/<locale>/<device>/` | same | 8 + 8 |
| iPhone App Preview | `preview/<locale>/iphone-6.5.mp4` | 886 × 1920, 30 fps, 25.4 s, AAC | 1 |
| iPad 13" App Preview | `preview/<locale>/ipad-13.mp4` | 1200 × 1600, 30 fps, 25.4 s, AAC | 1 |

```bash
Tools/appstore_media.sh              # screenshots and videos (~25 min)
Tools/appstore_media.sh screenshots  # screenshots only (~12 min)
Tools/appstore_media.sh video        # videos only (~13 min)
Tools/appstore_captions.sh           # paints captions onto finished screenshots (~2 min)
```

The locales are `cs` and `en-US`, everything in portrait. **Upload either the
captioned set or the plain one** — both have the same file names and order, they
differ only in the band at the top. Captions are not compulsory, but they lift
conversion. `en-GB` reuses the `en-US` media unchanged: no caption in the table
below contains a word the two spell differently.

The screenshots are 8-bit PNGs with no alpha channel (the simulator writes one even
when it is fully opaque, and App Store Connect does not want transparency) and have
been through a lossless recompression — verified with `magick compare -metric AE`
= 0.

`appstore_media.sh` needs Xcode, the simulators below and ImageMagick
(`brew install imagemagick`). It builds Debug — everything it drives is inside
`#if DEBUG` and never reaches an App Store build. `appstore_captions.sh` only
repaints finished PNGs and needs no simulator.

### The iPhone is captured at 6.5" natively

**The iPhone set is 1242 × 2688 — Connect's 6.5" slot — and an *iPhone 11 Pro Max*
records exactly that**, being 414 × 896 points at 3x. When that simulator is
installed the pipeline scales nothing at all and the uploaded pixels are the ones
the game drew. That is why it is first in `IPHONE_CANDIDATES`.

The runtimes do drop old devices eventually. The fallback is an *iPhone 17 Pro Max*,
which records 1320 × 2868; the shell then scales to width and crops eleven rows,
because the two aspect ratios differ by 0.4% and a fit would squash the picture
instead. Set `IPHONE_NAME` to force either one.

Apple derives the smaller sizes itself, so **one iPhone set covers every iPhone
slot**. Check which slot you are dropping files into before you regenerate at
another size — Connect will not tell you that you chose a different one.

### Why it is not in git

Around 300 MB of images and video are output, not source — the source is this
description, `jetshot/DebugLaunch.swift` and the scripts in `Tools/`. A PNG is
already compressed, so git cannot shrink it and it would stay in the history for
good; and because the autopilot flies a slightly different run every time, the set
is not byte-reproducible — every regeneration would add another 90 MB of new blobs,
not a diff.

App Store Connect keeps the record of what was actually shipped with each version.
If you ever need the exact files locally as well, attach them as a ZIP to the
release on the matching tag — that keeps them out of the repository history.

## How the game is posed

The pipeline needs states that are hours of play apart, twice per locale, on two
devices. `jetshot/DebugLaunch.swift` is the harness that produces them from launch
arguments — the full list is in that file's header. The three worth knowing here:

- **`-unlockall` is on every launch, and it is what makes this safe to run.** It
  puts `CloudStorageManager` into a read-only demo mode for the life of the
  process: progress is served from memory and every write to UserDefaults and to
  iCloud becomes a no-op. Without it, thirty-odd launches of a fabricated
  fifty-level save would be pushed to your own iCloud account and land on every
  device signed into it.
- **`-autopilot` flies the ship**, steering through the same `isTouching` /
  `touchLocation` pair a real drag sets. That is not a detail: the guns only fire
  while a finger is down, so a still frame of an idle game has no bullets in it at
  all.
- **`-invincible`** because the bot is not good enough to survive level 45 for
  twelve seconds, let alone a 25-second recording.

A chain lapses after 1.8 s, a shield lasts five, and the endless round banner is
gone in under two — so `DebugLaunch` holds those three states rather than setting
them once and hoping the capture lands in time. Everything it re-asserts is true of
the run: the chain is rebuilt by registering real kills, the power-ups go through
their real activators, and the banner prints the run's own `endlessRound`.

The banner hold is the one that is opt-in, behind `-banner`, and only the
screenshot asks for it. The banner lives about 1.65 s, so holding it means a new
one fades in as the last fades out — which is what a still needs and the opposite
of what five seconds of video needs, where three of those cycles read as a flicker.

## The shot list

Eight shots, in this order. The first two carry the listing; everything after them
is read by people who have already decided to look. The captions are the ones
`appstore_captions.sh` paints on.

| # | What is on screen | EN caption | CZ caption |
|---|---|---|---|
| 1 | Level 34 mid-wave: eight barrels firing, coins, asteroids, chain lit | Fifty levels. The guns fire themselves. | Padesát úrovní. Zbraně střílejí samy. |
| 2 | Level 40's boss in its third act — cracked armor, health bar under a third, the screen full of its barrage | Every level ends with a boss | Každá úroveň končí bossem |
| 3 | The chain meter at x8 with the CHAIN counter high | Chain your kills, score up to x8 | Série zásahů, skóre až osmkrát |
| 4 | Barrier, shield, rapid fire and magnet all live, their timer bars stacked under the HUD | Thirteen power-ups, eight barrels | Třináct vylepšení, osm zbraní |
| 5 | The level grid, fifty levels, most of them three-starred | Fifty levels, three stars each | Padesát úrovní, tři hvězdy za každou |
| 6 | An endless run at round 24, ROUND banner up | Endless: how far can you get? | Nekonečná hra: jak daleko doletíš? |
| 7 | Level 45: a turret mid-rotation, a laser charging, a formation arriving as one shape | 27 enemies, 12 obstacles | 27 nepřátel, 12 překážek |
| 8 | Main menu, with the endless record under the ENDLESS button | No ads. No purchases. No account. | Bez reklam. Bez nákupů. Bez účtu. |

Notes on the shots themselves, for when one needs retuning:

- **The settle is per shot, in `SHOTS`,** because these are not the same kind of
  picture. A menu is ready in four seconds; a level needs eleven for the waves to
  fill the screen; the boss needs fifteen, for its warning, its entrance and the
  damage burst that puts it into its third act.
- **Never shoot the starting ship.** One barrel is what a new player sees and the
  worst thing to advertise, which is why every gameplay shot passes `-guns 8`.
- **Catch the boss below a third health.** `BossPhaseRules.thresholds` is where the
  silhouette cracks and the cadence turns up; phase one looks like every other
  space shooter on the store. `-boss 0.28` lands there.
- **The game is drawn in light** — bloom, glows, neon vector shapes on black. It is
  the one thing that separates this listing visually from the pixel-art and
  3D-render competition, so favour frames with a lot of it.
- **Captions go in a band at the top**, over the sky where there is nothing to
  cover. Keep them short enough to read at thumbnail size, which is where two of
  these are actually seen.

## The preview

Six clips, cut to 25.4 seconds. In order: a mid-campaign level, a dense wave at x8,
the lightning power-up clearing the screen, level 40's boss, an endless run at round
24, and the menu.

The cut points are in `CUTS` and both devices share one set, unlike Minigolf's,
because every clip here is continuous gameplay with no scripted beat to hit — there
is nothing to synchronise against. The one exception is documented in the script:
`c6-menu` has to start at 0.0, because it is the only clip that never moves, the
recorder gives it a very long GOP, and a range starting mid-GOP is dropped outright
by the export once the segment sits at a non-zero offset.

## What Apple requires

The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) and is
**portrait only**, so **two sets** of portrait screenshots are mandatory.

| Slot | Resolution (portrait) | Count |
|---|---|---|
| iPhone 6.9" | 1260 × 2736, 1290 × 2796 or 1320 × 2868 | 3–10 |
| **iPhone 6.5"** ← what we upload | 1284 × 2778 or **1242 × 2688** | 3–10 |
| iPad 13" | 2048 × 2732 or **2064 × 2752** | 3–10 |

PNG or JPEG, no transparency, no rounded corners, no device frame (a frame is
allowed, but it has to be part of the image and must not cover the content). They
are ordered the way you upload them.

The App Preview is optional, and its specification is stricter than the one for
screenshots — every line of it is enforced on upload, so it is worth reading as a
checklist rather than as advice:

| | |
|---|---|
| Resolution | **iPhone 886 × 1920, iPad 13" 1200 × 1600** (portrait) |
| Video | H.264 **High Profile Level 4.0**, progressive, 30 fps — or ProRes 422 HQ |
| Bit rate | 10–12 Mbps VBR (H.264) |
| Audio | stereo AAC, **256 kbps**, 44.1 or 48 kHz — **required** |
| Length | 15–30 s, at most 500 MB, `.mp4` / `.m4v` / `.mov` |

Three of those cost an upload each to learn, and `appstore_conform.swift` exists to
pin all of them:

- **The preview is not the device's own resolution.** 886 × 1920 is the accepted
  portrait size for *every* iPhone slot, 6.5" included, and a file at 1242 × 2688
  is refused however good it looks. Unlike the screenshots, one file serves them
  all — which is why there is a single `iphone-6.5.mp4` rather than one per slot.
- **Level 4.0 is a ceiling.** At the device's own resolution the encoder has to
  reach Level 5.0, which is out of spec.
- **Silence is not audio.** AAC compresses digital silence to about 2 kbps, two
  orders of magnitude under the 256 kbps asked for, and Connect reports that as an
  unsupported audio configuration. The bed is `jetshot/Music/music-3.m4a`, looped
  under the whole cut with a fade at each end; override it with `PREVIEW_MUSIC`.

The bit rate is the subtle one. `AVVideoAverageBitRateKey` is a ceiling, not a
target, and Jetshot is mostly black — a starfield and a few dozen bright shapes
over an empty sky, which inter-frame prediction eats for almost nothing between
explosions. Asking for a number and getting one requires the all-intra GOP the
conform script sets; measured output is 11.0–11.5 Mbps across the four previews,
in the middle of Apple's band. `appstore_conform.swift` prints the rate it actually
wrote, and **that figure is the whole check** — do not change the GOP without
re-reading it.

## Localisation

Screenshots are uploaded per language. App Store Connect falls back to the primary
language's media for any localisation that has none, so **the English set is enough
to ship**. The Czech set is worth making anyway — a Czech-language listing with
English captions reads as a machine translation of somebody else's game, and the
Czech storefront is the one place this app has no six-figure competitor.
