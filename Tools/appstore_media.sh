#!/bin/bash
#
# appstore_media.sh — regenerates every screenshot and App Preview in AppStore/.
#
#     Tools/appstore_media.sh                 # screenshots + previews
#     Tools/appstore_media.sh screenshots     # screenshots only
#     Tools/appstore_media.sh video           # previews only
#
# Needs Xcode, the simulators named below and ImageMagick (`brew install
# imagemagick`) for the lossless PNG squeeze. Everything is posed by the DEBUG
# launch arguments in jetshot/DebugLaunch.swift, so it builds Debug — the whole
# harness is inside `#if DEBUG` and does not exist in a Release build.
#
# **Every launch below passes `-unlockall`, and that is what makes this safe to
# run.** `-unlockall` puts CloudStorageManager into a read-only demo mode for the
# life of the process: progress is served from memory and every write to
# UserDefaults and to iCloud becomes a no-op. Without it, thirty-odd launches of a
# fabricated fifty-level save would be pushed to the developer's own iCloud
# account and land on every device signed into it.
#
# Output goes to AppStore/screenshots/<locale>/<device>/ and
# AppStore/preview/<locale>/<device>.mp4. Override the root with OUT_ROOT=…
# to try things out without touching the committed set.
#
set -euo pipefail

MODE="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore}"
WORK="${WORK:-$(mktemp -d -t jetshot-appstore)}"
BID=cz.rob.jetshot

# The iPhone set goes into Connect's **6.5" slot at 1242 × 2688**, and an
# iPhone 11 Pro Max records exactly that — 414 × 896 points at 3x — so when that
# simulator is installed there is no rescaling at all and the screenshots are the
# pixels the game drew. It is the first choice for that reason alone. The runtimes
# do drop old devices eventually; the fallback records 1320 × 2868 and is scaled to
# width with eleven rows cropped, which is what Minigolf has to do for every shot.
#
# Set IPHONE_NAME to force one. Apple scales a 6.5" set up for the larger displays
# itself, so one iPhone set covers every iPhone slot.
IPHONE_CANDIDATES=("iPhone 11 Pro Max" "iPhone 17 Pro Max")
IPAD_NAME="${IPAD_NAME:-iPad Pro 13-inch (M5)}"   # records 2064 × 2752 — the "iPad 13"" slot

IPHONE_SHOT_SIZE=(1242 2688)
IPAD_SHOT_SIZE=(2064 2752)

# App Preview render sizes — the only two App Store Connect takes for these
# devices, and *not* the devices' own resolutions. 886 × 1920 serves every iPhone
# slot, 6.5" included. See AppStore/screenshots.md before changing either.
IPHONE_VIDEO_SIZE=(886 1920)
IPAD_VIDEO_SIZE=(1200 1600)

# Previews must carry stereo AAC at 256 kbps — silence does not satisfy the check
# — so one of the game's own tracks goes under the cut. Override, or set it empty
# to fall back to a (non-compliant) silent track.
PREVIEW_MUSIC="${PREVIEW_MUSIC-$ROOT/jetshot/Music/music-3.m4a}"

# en-GB is not here on purpose: it takes the en-US media unchanged, because no
# caption in AppStore/screenshots.md contains a word the two spell differently.
if [ -z "${LOCALES+x}" ]; then LOCALES=(cs en-US); fi

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
    # Device lines are indented four spaces and read "<name> (<udid>) (<state>)".
    # Matched as a fixed string, because names like "iPad Pro 13-inch (M5)" carry
    # brackets of their own; the trailing " (" keeps "iPhone 17" from matching
    # "iPhone 17 Pro Max".
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
        | head -n 1 || true
}

boot_and_install() {
    local udid="$1"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # The game hides the status bar, but pin it anyway so nothing stray shows.
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true
}

locale_args() {
    case "$1" in
        cs)    printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(cs)" -AppleLocale cs_CZ ;;
        en-US) printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(en-US)" -AppleLocale en_US ;;
    esac
}

launch() { # launch <udid> <locale> <args...>
    local udid="$1" loc="$2"; shift 2
    local largs=()
    while IFS= read -r -d '' a; do largs+=("$a"); done < <(locale_args "$loc")
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BID" "${largs[@]}" "$@" >/dev/null
}

# ---------------------------------------------------------------- build

if [ -n "${IPHONE_NAME:-}" ]; then
    IPHONE_CANDIDATES=("$IPHONE_NAME")
fi
IPHONE_NAME=""
for candidate in "${IPHONE_CANDIDATES[@]}"; do
    if [ -n "$(udid_for "$candidate")" ]; then IPHONE_NAME="$candidate"; break; fi
done
[ -n "$IPHONE_NAME" ] || { echo "none of these simulators exist: ${IPHONE_CANDIDATES[*]}"; exit 1; }

say "Building Debug for the simulator"
xcodebuild -project "$ROOT/jetshot.xcodeproj" -scheme jetshot \
    -configuration Debug -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$IPHONE_NAME" \
    -derivedDataPath "$WORK/dd" build >/dev/null
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/jetshot.app"

IPHONE_UDID="$(udid_for "$IPHONE_NAME")"
IPAD_UDID="$(udid_for "$IPAD_NAME")"
[ -n "$IPAD_UDID" ] || { echo "no simulator named '$IPAD_NAME'"; exit 1; }
printf '  iPhone: %s\n  iPad:   %s\n' "$IPHONE_NAME" "$IPAD_NAME"

# ---------------------------------------------------------------- screenshots

# name|settle|launch arguments.
#
# The settle is how long the shell waits before the capture, and it is per shot
# rather than global because these are not the same kind of picture. A menu is
# ready in three seconds; a level needs ten for the waves to fill the screen and
# the ship to have something to shoot at; a boss needs its warning, its entrance
# and the damage burst that puts it into its third act.
#
# `-invincible` is on every gameplay shot for the obvious reason — the bot is not
# good enough to survive level 45 unaided for twelve seconds — and `-autopilot` is
# on because a ship that is not being dragged does not fire, so a still frame of an
# idle game has no bullets in it at all.
SHOTS=(
    "01-wave|11|-level 34 -unlockall -guns 8 -missiles 2 -chain 12 -nointro -invincible -autopilot"
    "02-boss|15|-level 40 -unlockall -guns 8 -missiles 2 -boss 0.28 -nointro -invincible -autopilot"
    "03-chain|9|-level 22 -unlockall -guns 8 -missiles 1 -chain 40 -nointro -invincible -autopilot"
    "04-powerups|10|-level 28 -unlockall -guns 6 -missiles 2 -powerups barrier,shield,rapidfire,magnet -nointro -invincible -autopilot"
    "05-levels|4|-levelselect -level 25 -unlockall"
    "06-endless|11|-endless -unlockall -guns 8 -missiles 2 -round 24 -banner -nointro -invincible -autopilot"
    "07-enemies|12|-level 45 -unlockall -guns 8 -missiles 2 -nointro -invincible -autopilot"
    "08-menu|4|-unlockall"
)

shoot() { # shoot <udid> <locale> <device-dir> <extra-settle> <W> <H>
    local udid="$1" loc="$2" dev="$3" extra="$4" w="$5" h="$6"
    local dir="$OUT_ROOT/screenshots/$loc/$dev"
    mkdir -p "$dir"
    for entry in "${SHOTS[@]}"; do
        IFS='|' read -r name settle args <<<"$entry"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" $args
        sleep "$(awk "BEGIN{print $settle + $extra}")"
        xcrun simctl io "$udid" screenshot "$dir/$name.png" >/dev/null 2>&1
        # Scale only when the capture is not already the upload size — on an
        # iPhone 11 Pro Max and the iPad it is, and this does nothing. Filling the
        # box and cropping the overflow, rather than resizing to fit, keeps the
        # picture undistorted: the two aspect ratios differ by a hair.
        if [ "$(magick identify -format '%wx%h' "$dir/$name.png")" != "${w}x${h}" ]; then
            magick "$dir/$name.png" -resize "${w}x${h}^" -gravity center \
                -extent "${w}x${h}" -alpha off -depth 8 -strip "$dir/$name.png.tmp"
            mv "$dir/$name.png.tmp" "$dir/$name.png"
        fi
        printf '  %-14s %s\n' "$name" \
            "$(sips -g pixelWidth -g pixelHeight "$dir/$name.png" | awk '/pixel/{printf "%s ", $2}')"
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

if [ "$MODE" = all ] || [ "$MODE" = screenshots ]; then
    command -v magick >/dev/null \
        || { echo "needs ImageMagick to size and squeeze the shots (brew install imagemagick)"; exit 1; }
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in "${LOCALES[@]}"; do
        say "Screenshots — iPhone 6.5\" / $loc"
        shoot "$IPHONE_UDID" "$loc" iphone-6.5 0 "${IPHONE_SHOT_SIZE[@]}"
        # The iPad draws more of everything at a larger size and is the slower of
        # the two to reach a busy screen, so every shot gets a second longer.
        say "Screenshots — iPad 13\" / $loc"
        shoot "$IPAD_UDID" "$loc" ipad-13 1 "${IPAD_SHOT_SIZE[@]}"
    done

    # The simulator writes RGBA even though every pixel is opaque, and App Store
    # Connect wants screenshots without transparency. Dropping the channel leaves
    # the picture untouched and saves about a third of the size.
    say "Squeezing PNGs (lossless — anything that differs is left alone)"
    while IFS= read -r f; do
        magick "$f" -alpha off -depth 8 -strip \
                    -define png:compression-level=9 \
                    -define png:compression-filter=5 "$f.opt"
        if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
            mv "$f.opt" "$f"
        else
            rm -f "$f.opt"
            echo "  left as-is (not identical): $f"
        fi
    done < <(find "$OUT_ROOT/screenshots" -name '*.png')
    du -sh "$OUT_ROOT/screenshots"
fi

# ---------------------------------------------------------------- previews

# name|pre-roll|seconds|launch arguments.
#
# The pre-roll is dead time between the launch and the first recorded frame: long
# enough for the ship to be flying and the screen to have filled, and for the boss
# clip, long enough for the warning, the entrance and the damage burst to be over.
# Recording through any of that would put a title card in the middle of the cut.
#
# The boss here is left at 0.45 health rather than the screenshot's 0.28, because a
# clip has to hold for five seconds: at 0.28 the bot's eight barrels finish it
# inside three and the tail of the window is an empty screen. For the same reason
# the endless clip does not pass `-banner` while the screenshot does — held up over
# five seconds of video the round banner cycles three times and reads as a flicker.
CLIPS=(
    "c1-wave|5|13|-level 12 -unlockall -guns 6 -missiles 1 -nointro -invincible -autopilot"
    "c2-swarm|8|13|-level 34 -unlockall -guns 8 -missiles 2 -chain 20 -nointro -invincible -autopilot"
    "c3-powerups|7|13|-level 28 -unlockall -guns 8 -missiles 2 -powerups barrier,lightning,rapidfire -nointro -invincible -autopilot"
    "c4-boss|12|14|-level 40 -unlockall -guns 8 -missiles 2 -boss 0.45 -nointro -invincible -autopilot"
    "c5-endless|8|13|-endless -unlockall -guns 8 -missiles 2 -round 24 -nointro -invincible -autopilot"
    "c6-menu|4|8|-unlockall"
)

# Both devices share one set of cut points, unlike Minigolf's, and for a reason
# that is a property of this game rather than a shortcut: every clip here is
# continuous gameplay with no scripted beat to hit, so any five seconds of it are
# as good as any other five. There is nothing to synchronise against.
#
# c6-menu has to start at 0.0, and not because of what is on screen. It is the one
# clip that never moves, so the recorder gives it a very long GOP — and a range
# starting mid-GOP is dropped outright by the export once the segment sits at a
# non-zero offset in the composition: the finished file holds the last frame of the
# preceding clip for those seconds instead. Starting on the keyframe is what makes
# it render, and the screen is identical throughout anyway.
#
# The windows add up to 25.4 s, inside Connect's 15–30 s. `appstore_conform.swift`
# refuses anything outside that range before it wastes an encode on it.
CUTS=(c1-wave:1.0:5.2 c2-swarm:1.0:5.6 c3-powerups:1.0:5.4
      c4-boss:1.0:6.2 c5-endless:1.0:5.4 c6-menu:0.0:2.6)

record() { # record <udid> <locale> <clipdir>
    local udid="$1" loc="$2" dir="$3"
    mkdir -p "$dir"
    for entry in "${CLIPS[@]}"; do
        IFS='|' read -r name pre secs args <<<"$entry"
        # shellcheck disable=SC2086
        launch "$udid" "$loc" $args
        sleep "$pre"
        xcrun simctl io "$udid" recordVideo --codec h264 --force "$dir/$name.mp4" >/dev/null 2>&1 &
        local pid=$!
        sleep "$secs"
        kill -INT $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        sleep 1
        printf '  %-12s %s\n' "$name" "$(avmediainfo "$dir/$name.mp4" | awk '/^Duration:/{print $2 "s"}')"
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

assemble() { # assemble <clipdir> <out.mp4> <W> <H> <cut...>
    local dir="$1" out="$2" w="$3" h="$4"; shift 4
    mkdir -p "$(dirname "$out")"
    local specs=()
    for cut in "$@"; do specs+=("$dir/${cut%%:*}.mp4:${cut#*:}"); done
    swift "$ROOT/Tools/appstore_video.swift" "$out" "$w" "$h" "${specs[@]}"
    # What comes out of the cut is the right size but the wrong everything else for
    # App Store Connect — too high a profile, too fast a bit rate and no audio at
    # all. This pins the lot to Apple's table.
    swift "$ROOT/Tools/appstore_conform.swift" "$out" "$w" "$h" ${PREVIEW_MUSIC:+"$PREVIEW_MUSIC"}
}

if [ "$MODE" = all ] || [ "$MODE" = video ]; then
    boot_and_install "$IPHONE_UDID"
    boot_and_install "$IPAD_UDID"
    for loc in "${LOCALES[@]}"; do
        say "Preview — iPhone 6.5\" / $loc"
        record "$IPHONE_UDID" "$loc" "$WORK/clips/iphone-$loc"
        assemble "$WORK/clips/iphone-$loc" "$OUT_ROOT/preview/$loc/iphone-6.5.mp4" \
            "${IPHONE_VIDEO_SIZE[@]}" "${CUTS[@]}"

        say "Preview — iPad 13\" / $loc"
        record "$IPAD_UDID" "$loc" "$WORK/clips/ipad-$loc"
        assemble "$WORK/clips/ipad-$loc" "$OUT_ROOT/preview/$loc/ipad-13.mp4" \
            "${IPAD_VIDEO_SIZE[@]}" "${CUTS[@]}"
    done
fi

say "Done. Working files in $WORK"
