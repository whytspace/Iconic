#!/usr/bin/env bash
#
# Turn `/iconic shot` captures into named transparent images for the README.
#
# Each `/iconic shot` writes a black+white screenshot pair, and WoW names
# screenshots by timestamp, so this relies on order: it takes the newest 2*N
# screenshots, recovers true alpha from each pair (difference matting), trims
# to the content, and writes one named PNG per view, in the order given.
#
# Usage:
#   scripts/process-shots.sh                 # picker, colours, browser
#   scripts/process-shots.sh browser         # just the newest pair
#   SHOTS_DIR=/path scripts/process-shots.sh
#
# Requires: ImageMagick 7 (`magick`) — brew install imagemagick
# Optional: pngquant, oxipng — brew install pngquant oxipng

set -euo pipefail

SHOTS_DIR="${SHOTS_DIR:-/Applications/Games/World of Warcraft/_retail_/Screenshots}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/images"

# Output names, in the order the shots were taken.
if [ "$#" -gt 0 ]; then
  views=("$@")
else
  views=(picker colours browser)
fi

command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick not found — install it with: brew install imagemagick" >&2
  exit 1
}
[ -d "$SHOTS_DIR" ] || {
  echo "screenshots folder not found: $SHOTS_DIR" >&2
  exit 1
}
mkdir -p "$OUT_DIR"

# Difference matte. The plates aren't pure black/white — WoW renders the page
# over a near-black backdrop — so sample each plate's corner for its true backdrop
# (b0, b1) and use the general matte: alpha = 1 - (white - black)/(b1 - b0),
# colour = (black - (1 - alpha)*b0) / alpha (un-premultiplied), then trim.
# Assuming pure black here leaves a ~9% white haze where there should be none.
matte() { # black white out
  local b0 b1 low
  b0=$(magick "$1" -format '%[fx:(p{0,0}.r+p{0,0}.g+p{0,0}.b)/3]' info:)
  b1=$(magick "$2" -format '%[fx:(p{0,0}.r+p{0,0}.g+p{0,0}.b)/3]' info:)
  low=$(awk -v a="$b0" -v b="$b1" 'BEGIN{printf "%.4f", (1 + a - b) * 100}')
  magick \
    \( "$1" "$2" -compose Mathematics -define compose:args=0,-1,1,1 -composite \
       -level "${low}%,100%" \) -write mpr:alpha +delete \
    \( mpr:alpha -negate -evaluate multiply "$b0" \) -write mpr:bg +delete \
    "$1" mpr:bg -compose Mathematics -define compose:args=0,-1,1,0 -composite \
    mpr:alpha -compose Divide -composite \
    mpr:alpha -alpha off -compose CopyOpacity -composite \
    -trim +repage "$3"
}

# Keep only the largest opaque region (windows less than ~24px apart merge): the captured window with its
# attached tooltip and menus. Drops
# anything floating apart from it, like the cursor ring or a stray unit tooltip.
crop_to_window() { # file
  local box
  box=$(magick "$1" -alpha extract -threshold 50% -morphology Dilate Octagon:24 \
    -define connected-components:verbose=true -connected-components 8 null: |
    awk '$NF == "srgb(255,255,255)" && $(NF-1) > max { max = $(NF-1); box = $2 } END { print box }')
  [ -n "$box" ] && magick "$1" -crop "$box" +repage -trim +repage "$1"
}

# TinyPNG-style shrink: lossy palette quantization, then a lossless squeeze.
# Both tools are optional — warn once and pass the file through untouched.
warned_pngquant=0 warned_oxipng=0
compress() { # file
  if command -v pngquant >/dev/null 2>&1; then
    # Exit 98/99 = couldn't hit the quality floor; keep the original in that case.
    pngquant --quality=65-90 --speed 1 --strip --force --output "$1" "$1" || true
  elif [ "$warned_pngquant" -eq 0 ]; then
    echo "pngquant not found — skipping quantization (brew install pngquant)" >&2
    warned_pngquant=1
  fi
  if command -v oxipng >/dev/null 2>&1; then
    oxipng -o max --strip safe -q "$1"
  elif [ "$warned_oxipng" -eq 0 ]; then
    echo "oxipng not found — skipping lossless squeeze (brew install oxipng)" >&2
    warned_oxipng=1
  fi
}

# Newest 2*N screenshots, oldest-first (matching capture order).
need=$((2 * ${#views[@]}))
recent=()
while IFS= read -r f; do recent+=("$f"); done < <(ls -t "$SHOTS_DIR"/*.png 2>/dev/null | head -n "$need" | tail -r)

if [ "${#recent[@]}" -lt "$need" ]; then
  echo "need $need screenshots (${#views[@]} views x black+white), found ${#recent[@]} in $SHOTS_DIR" >&2
  exit 1
fi

for i in "${!views[@]}"; do
  black="${recent[$((2 * i))]}"
  white="${recent[$((2 * i + 1))]}"
  out="$OUT_DIR/${views[$i]}.png"
  matte "$black" "$white" "$out"
  crop_to_window "$out"
  compress "$out"
  echo "$(basename "$out")  <-  $(basename "$black") + $(basename "$white")"
done
