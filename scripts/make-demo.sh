#!/usr/bin/env bash
#
# Turn the frames of `/iconic shot demo` into docs/images/demo.webp, an animation with a transparent background.
#
# The demo captures each frame as a black+white screenshot pair and stores each frame's display time, mouse pointer
# spot and the screen area to keep in Iconic's saved variables, which the game writes on /reload. In three stages,
# the first two cached in .cache/demo, so changing only the look (pointer, fade, size, quality) redoes stage 3 alone:
#   1. remove the backgrounds of the newest 2*N screenshots (one transparent image per pair)
#   2. crop them to the recorded area
#   3. trim, draw the pointer, fade out, scale and encode
#
# Usage (after the demo and a /reload):
#   scripts/make-demo.sh
#   QUALITY=70 MAX_WIDTH=960 POINTER_SIZE=48 scripts/make-demo.sh
#   SHOTS_DIR=/path WTF_DIR=/path scripts/make-demo.sh
#
# Requires: ImageMagick 7 (`magick`), img2webp — brew install imagemagick webp

set -euo pipefail

WOW="/Applications/Games/World of Warcraft/_retail_"
SHOTS_DIR="${SHOTS_DIR:-$WOW/Screenshots}"
WTF_DIR="${WTF_DIR:-$WOW/WTF}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${CACHE:-$REPO_ROOT/.cache/demo}"
OUTPUT="$REPO_ROOT/docs/images/demo.webp"
QUALITY="${QUALITY:-55}"
# GitHub and CurseForge show README images about 836-838px wide.
MAX_WIDTH="${MAX_WIDTH:-840}"
# The mouse pointer (WoW's Interface\CURSOR\Point.blp), its tip, and its size in screenshot pixels. It glides to a new
# spot at least GLIDE_MIN screenshot pixels away in GLIDE_FRAMES frames; smaller moves (dragging) just happen.
POINTER="$REPO_ROOT/scripts/pointer.png"
POINTER_TIP=2
POINTER_SIZE="${POINTER_SIZE:-64}"
GLIDE_MIN=50 GLIDE_FRAMES=6 GLIDE_MS=40
# The first frame fades in from transparent; after the last one, a fade to transparent and an empty pause before the
# loop restarts.
FADE_FRAMES=8 FADE_MS=60 END_PAUSE_MS=700

for tool in magick img2webp; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool not found — install it with: brew install imagemagick webp" >&2
    exit 1
  }
done
# shellcheck source=scripts/matte.sh
source "$REPO_ROOT/scripts/matte.sh"

started=$SECONDS
step() { echo "==> $*" >&2; }
done_in() { echo "    done in $((SECONDS - started))s" >&2; started=$SECONDS; }
progress() { printf "\r    %d/%d" "$1" "$2" >&2; [ "$1" -eq "$2" ] && echo >&2; return 0; }

saved=$(ls -t "$WTF_DIR"/Account/*/SavedVariables/Iconic.lua 2>/dev/null | head -n 1)
[ -n "$saved" ] || {
  echo "no Iconic saved variables under $WTF_DIR; run /reload after the demo" >&2
  exit 1
}
# The numbers in a saved list such as ["demoFrames"] = { 0.12, -- [1] ... }, one per line.
saved_list() { # name
  awk -v name="$1" '
    index($0, "[\"" name "\"] = {") { grab = 1; skip = 1 }
    grab && !skip && /^[[:space:]]*\}/ { exit }
    grab && !skip { gsub(/[^0-9.]/, " "); print $1 }
    { skip = 0 }
  ' "$saved"
}
# A number from the saved ["demoBox"] = { ["key"] = n, ... }.
saved_box() { # key
  awk -v key="$1" '
    /\["demoBox"\] = \{/ { grab = 1 }
    grab && index($0, "[\"" key "\"] =") { split($0, v, "= "); print v[2] + 0; exit }
    grab && /^\},?$/ { exit }
  ' "$saved"
}
holds=() pointer_x=() pointer_y=()
while IFS= read -r v; do holds+=("$v"); done < <(saved_list demoFrames)
while IFS= read -r v; do pointer_x+=("$v"); done < <(saved_list demoPointerX)
while IFS= read -r v; do pointer_y+=("$v"); done < <(saved_list demoPointerY)
count=${#holds[@]}
step "$count frames in $saved"
[ "$count" -gt 0 ] || {
  echo "no demo frames in $saved; run /iconic shot demo, then /reload" >&2
  exit 1
}

# Newest 2*N screenshots, oldest first; each frame is named after its black screenshot.
shots=()
while IFS= read -r f; do shots+=("$f"); done < <(ls -t "$SHOTS_DIR"/*.png 2>/dev/null | head -n $((2 * count)) | tail -r)
[ "${#shots[@]}" -eq $((2 * count)) ] || {
  echo "need $((2 * count)) screenshots for $count frames, found ${#shots[@]} in $SHOTS_DIR" >&2
  exit 1
}
names=()
for ((i = 0; i < count; i++)); do names+=("$(basename "${shots[$((2 * i))]}" .png)"); done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$CACHE/matted"

step "1/3 removing the backgrounds of $count screenshot pairs (cached in ${CACHE#"$REPO_ROOT"/})"
for ((i = 0; i < count; i++)); do
  out="$CACHE/matted/${names[$i]}.png"
  [ -f "$out" ] || matte "${shots[$((2 * i))]}" "${shots[$((2 * i + 1))]}" "$out"
  progress $((i + 1)) "$count"
done
done_in

# The recorded area (IconicDB.demoBox, screen pixels scaled to the screenshots), else the windows in all frames laid
# over each other, without stray bits like the cursor ring. 8px margin for border shadows, except on the left, where
# the character window sits right next to the picker.
read -r shot_w shot_h < <(magick "${shots[0]}" -format '%w %h\n' info:)
screen_w=$(saved_box screenWidth) screen_h=$(saved_box screenHeight)
if [ -n "$screen_w" ]; then
  scale_x=$(awk -v a="$shot_w" -v b="$screen_w" 'BEGIN { print a / b }')
  scale_y=$(awk -v a="$shot_h" -v b="$screen_h" 'BEGIN { print a / b }')
  box=$(awk -v fx="$scale_x" -v fy="$scale_y" -v sw="$shot_w" -v sh="$shot_h" \
    -v L="$(saved_box left)" -v T="$(saved_box top)" -v R="$(saved_box right)" -v B="$(saved_box bottom)" 'BEGIN {
      m = 8; l = int(L * fx + 0.999); t = int(T * fy) - m; r = int(R * fx + 0.999) + m; b = int(B * fy + 0.999) + m
      if (t < 0) t = 0; if (r > sw) r = sw; if (b > sh) b = sh
      printf "%dx%d+%d+%d", r - l, b - t, l, t }')
else
  scale_x=1 scale_y=1
  magick "$CACHE"/matted/*.png -evaluate-sequence max "$work/all.png"
  box=$(window_box "$work/all.png")
fi
[ -n "$box" ] || {
  echo "no window found in the frames" >&2
  exit 1
}
read -r _ _ box_x box_y < <(echo "$box" | tr 'x+' '  ')

step "2/3 cropping to the recorded area $box (cached)"
cropped="$CACHE/cropped/$box"
mkdir -p "$cropped"
for ((i = 0; i < count; i++)); do
  out="$cropped/${names[$i]}.png"
  [ -f "$out" ] || magick "$CACHE/matted/${names[$i]}.png" -crop "$box" +repage "$out"
  progress $((i + 1)) "$count"
done
done_in

step "3/3 trimming, drawing the pointer, fading out, scaling to at most ${MAX_WIDTH}px wide and encoding"
# Trim to what any frame shows inside the area.
frames=()
for name in "${names[@]}"; do frames+=("$cropped/$name.png"); done
read -r trim_w trim_h trim_x trim_y < <(magick "${frames[@]}" -evaluate-sequence max -format '%@\n' info: | tr 'x+' '  ')
trim="${trim_w}x${trim_h}+${trim_x}+${trim_y}"

# Output frames as "frame x y ms": each captured frame, and before one whose pointer jumped, GLIDE_FRAMES of the
# previous frame with the pointer gliding over (eased). x and y are the pointer tip in trimmed screenshot pixels.
plan=$(awk -v n="$count" -v gmin="$GLIDE_MIN" -v gf="$GLIDE_FRAMES" -v gms="$GLIDE_MS" -v sx="$scale_x" -v sy="$scale_y" \
  -v ox="$((box_x + trim_x))" -v oy="$((box_y + trim_y))" -v xs="${pointer_x[*]:-}" -v ys="${pointer_y[*]:-}" \
  -v hs="${holds[*]}" '
  BEGIN {
    split(hs, hold, " "); np = split(xs, px, " "); split(ys, py, " ")
    for (i = 1; i <= n; i++) {
      x = np ? px[i] * sx - ox : "none"; y = np ? py[i] * sy - oy : "none"
      if (np && i > 1 && (x - lx) ^ 2 + (y - ly) ^ 2 >= gmin ^ 2) {
        for (k = 1; k <= gf; k++) {
          t = k / (gf + 1); t = t * t * (3 - 2 * t)
          printf "%d %d %d %d\n", i - 2, lx + (x - lx) * t, ly + (y - ly) * t, gms
        }
      }
      printf "%d %s %s %d\n", i - 1, np ? int(x) : x, np ? int(y) : y, hold[i] * 1000 + 0.5
      lx = x; ly = y
    }
  }')
total=$(($(echo "$plan" | wc -l) + 2 * FADE_FRAMES))

magick "$POINTER" -resize "${POINTER_SIZE}x${POINTER_SIZE}" "$work/pointer.png"
tip=$((POINTER_TIP * POINTER_SIZE / 32))
frame_args=()
k=0
render() { # frame x y out
  if [ "$2" = "none" ]; then
    magick "${frames[$1]}" -crop "$trim" +repage -resize "${MAX_WIDTH}x>" "$4"
  else
    magick "${frames[$1]}" -crop "$trim" +repage \
      "$work/pointer.png" -geometry "$(printf "%+d%+d" $(($2 - tip)) $(($3 - tip)))" -composite \
      -resize "${MAX_WIDTH}x>" "$4"
  fi
}
while read -r frame px py ms; do
  out=$(printf "%s/out-%04d.png" "$work" "$k")
  render "$frame" "$px" "$py" "$out"
  frame_args+=(-d "$ms" -lossy -q "$QUALITY" "$out")
  k=$((k + 1))
  progress "$k" "$total"
done <<<"$plan"
first="$work/out-0000.png" last="$out"
# A copy of `source` with its opacity times `factor`, as an animation frame of `ms`.
faded() { # source factor ms
  local out
  out=$(printf "%s/out-%04d.png" "$work" "$k")
  magick "$1" -channel A -evaluate multiply "$2" +channel "$out"
  fade_args+=(-d "$3" -lossy -q "$QUALITY" "$out")
  k=$((k + 1))
  progress "$k" "$total"
}
fade_args=()
for ((f = 0; f < FADE_FRAMES; f++)); do
  faded "$first" "$(awk -v f="$f" -v n="$FADE_FRAMES" 'BEGIN { print f / n }')" "$FADE_MS"
done
args=(-loop 0 -min_size "${fade_args[@]}" "${frame_args[@]}")
fade_args=()
for ((f = 1; f <= FADE_FRAMES; f++)); do
  faded "$last" "$(awk -v f="$f" -v n="$FADE_FRAMES" 'BEGIN { print 1 - f / n }')" \
    "$([ "$f" -eq "$FADE_FRAMES" ] && echo "$END_PAUSE_MS" || echo "$FADE_MS")"
done
args+=("${fade_args[@]}")
img2webp "${args[@]}" -o "$OUTPUT" >/dev/null 2>&1
done_in

echo "wrote $OUTPUT ($total frames from $count captures, $(du -h "$OUTPUT" | cut -f1))"
