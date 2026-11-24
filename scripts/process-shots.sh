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
#   scripts/process-shots.sh                 # picker, colors, browser
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
  views=(picker colors browser)
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

# shellcheck source=scripts/matte.sh
source "$REPO_ROOT/scripts/matte.sh"

# Keep only the captured window with its attached tooltip and menus (window_box in matte.sh).
crop_to_window() { # file
  local box
  box=$(window_box "$1")
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
  magick "$out" -trim +repage "$out"
  crop_to_window "$out"
  compress "$out"
  echo "$(basename "$out")  <-  $(basename "$black") + $(basename "$white")"
done
