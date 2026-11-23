#!/usr/bin/env bash
#
# Shared by process-shots.sh and make-demo.sh: transparent images from black+white screenshot pairs.

# Difference matte. The plates aren't pure black/white — WoW renders the page
# over a near-black backdrop — so sample each plate's corner for its true backdrop
# (b0, b1) and use the general matte: alpha = 1 - (white - black)/(b1 - b0),
# colour = (black - (1 - alpha)*b0) / alpha (un-premultiplied). Full screen size; callers crop.
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
    "$3"
}

# Box (WxH+X+Y) of the largest opaque region of an image, where regions less than ~24px apart merge: the captured
# window with its attached tooltip and menus. Leaves out anything floating apart, like the cursor ring or a stray
# unit tooltip. The box includes up to 24px of margin.
window_box() { # file
  magick "$1" -alpha extract -threshold 50% -morphology Dilate Octagon:24 \
    -define connected-components:verbose=true -connected-components 8 null: |
    awk '$NF == "srgb(255,255,255)" && $(NF-1) > max { max = $(NF-1); box = $2 } END { print box }'
}
