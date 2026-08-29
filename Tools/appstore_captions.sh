#!/bin/bash
#
# appstore_captions.sh — burns the captions into the finished screenshots.
#
#     Tools/appstore_captions.sh
#
# Reads AppStore/screenshots/<locale>/<device>/NN-*.png and writes files of the
# same name into AppStore/screenshots-captioned/. The original set is left
# untouched — upload one or the other to App Store Connect.
#
# Layout: a band of text at the top, below it the shrunken screenshot on a deep
# blue-black ground taken from the game's own sky. The screenshot is scaled, never
# cropped, so neither the HUD nor the chain meter loses anything.
#
# Needs ImageMagick (`brew install imagemagick`).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="${SRC_ROOT:-$ROOT/AppStore/screenshots}"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore/screenshots-captioned}"

# ImageMagick has no fonts registered here, so it needs a path to the file. Arial
# Bold is the only bold face in the system with complete Czech diacritics (Arial
# Rounded Bold has neither ť nor ě, and SF only renders in regular via IM).
FONT="${FONT:-/System/Library/Fonts/Supplemental/Arial Bold.ttf}"

# GameScene's own background colour, and a darker floor under it. Keeping the band
# the same family as the sky is what stops the card reading as a screenshot pasted
# onto marketing material.
BG_TOP='#0b0b2b'
BG_BOTTOM='#030310'

# The captions from AppStore/screenshots.md. The number matches the file prefix.
# Where the text does not fit on one line the break is written by hand — an
# automatic one leaves a single word hanging on the second line.
cs_caption() {
    case "$1" in
        01) echo "Padesát úrovní."$'\n'"Zbraně střílejí samy." ;;
        02) echo "Každá úroveň"$'\n'"končí bossem" ;;
        03) echo "Řetěz zásahů,"$'\n'"skóre až osmkrát" ;;
        04) echo "Třináct vylepšení,"$'\n'"osm hlavní" ;;
        05) echo "Padesát úrovní,"$'\n'"tři hvězdy za každou" ;;
        06) echo "Nekonečná hra:"$'\n'"jak daleko doletíš?" ;;
        07) echo "27 nepřátel,"$'\n'"12 překážek" ;;
        08) echo "Bez reklam."$'\n'"Bez nákupů. Bez účtu." ;;
    esac
}

en_caption() {
    case "$1" in
        01) echo "Fifty levels."$'\n'"The guns fire themselves." ;;
        02) echo "Every level"$'\n'"ends with a boss" ;;
        03) echo "Chain your kills,"$'\n'"score up to x8" ;;
        04) echo "Thirteen power-ups,"$'\n'"eight barrels" ;;
        05) echo "Fifty levels,"$'\n'"three stars each" ;;
        06) echo "Endless:"$'\n'"how far can you get?" ;;
        07) echo "27 enemies,"$'\n'"12 obstacles" ;;
        08) echo "No ads."$'\n'"No purchases. No account." ;;
    esac
}

# Per-device dimensions: canvas, height of the text band, width of the text block,
# font size. The screenshot is sized to fill the rest below the band.
#
# The canvas has to be the size App Store Connect takes for the slot the set is
# uploaded to, not whatever the simulator happened to record — the iphone-6.5
# directory holds 1242 × 2688, which is Connect's 6.5" slot (see
# AppStore/screenshots.md). The band and the type are scaled to the canvas; keep
# them in proportion if the canvas ever changes, or the iPhone caption stops
# matching the iPad's.
geometry_for() {
    case "$1" in
        iphone-6.5) echo "1242 2688 452 1082 86" ;;
        ipad-13)    echo "2064 2752 450 1760 128" ;;
        *)          echo "" ;;
    esac
}

[ -f "$FONT" ] || { echo "font not found: $FONT"; exit 1; }
command -v magick >/dev/null || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }

for locale_dir in "$SRC_ROOT"/*; do
    [ -d "$locale_dir" ] || continue
    locale="$(basename "$locale_dir")"
    for device_dir in "$locale_dir"/*; do
        [ -d "$device_dir" ] || continue
        device="$(basename "$device_dir")"

        read -r W H BAND BOX PT <<<"$(geometry_for "$device")"
        [ -n "${W:-}" ] || { echo "  skipping unknown device: $device"; continue; }

        # The screenshot card: a 3px border plus a soft shadow, 22px above the
        # bottom edge. Whatever height is left above it belongs to the text.
        margin=22
        border=3
        card_h=$(( H - BAND - margin ))
        card_w=$(( W * card_h / H ))
        band_h=$(( H - card_h - margin - 2 * border ))

        out="$OUT_ROOT/$locale/$device"
        mkdir -p "$out"
        printf '\n\033[1m%s / %s\033[0m  (card %dx%d, band %d)\n' "$locale" "$device" "$card_w" "$card_h" "$band_h"

        for src in "$device_dir"/*.png; do
            name="$(basename "$src")"
            num="${name%%-*}"
            case "$locale" in
                cs) caption="$(cs_caption "$num")" ;;
                *)  caption="$(en_caption "$num")" ;;
            esac
            [ -n "$caption" ] || { echo "  no caption for $name — skipped"; continue; }

            magick -size "${W}x${H}" gradient:"$BG_TOP-$BG_BOTTOM" \
                \( "$src" -resize "${card_w}x${card_h}" \
                   -bordercolor '#7fd7ff33' -border "$border" \
                   \( +clone -background black -shadow 55x28+0+10 \) \
                   +swap -background none -layers merge +repage \) \
                -gravity south -geometry "+0+$margin" -composite \
                \( -size "${BOX}x" -background none -fill white -font "$FONT" \
                   -pointsize "$PT" -gravity center caption:"$caption" \
                   -gravity center -extent "${W}x${band_h}" \) \
                -gravity north -geometry +0+0 -composite \
                -alpha off -depth 8 \
                "$out/$name"
            printf '  %-16s %s\n' "$name" "$(echo "$caption" | tr '\n' ' ')"
        done
    done
done

printf '\n\033[1mLossless recompression\033[0m\n'
while IFS= read -r f; do
    magick "$f" -strip -define png:compression-level=9 \
                -define png:compression-filter=5 "$f.opt"
    if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
        mv "$f.opt" "$f"
    else
        rm -f "$f.opt"
        echo "  left as it was (not bit-identical): $f"
    fi
done < <(find "$OUT_ROOT" -name '*.png')

printf '\n\033[1mDone:\033[0m %s\n' "$OUT_ROOT"
du -sh "$OUT_ROOT"
