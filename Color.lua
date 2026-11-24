local ADDON_NAME, ns = ...

local Color = {}
ns.Color = Color

-- Minimum share (0-100) of an icon in a chip's color band for the chip to match.
local MIN_SHARE = 10
Color.MIN_SHARE = MIN_SHARE

-- Color words that suggest a chip: each is one shade (hex), with other words that suggest it.
Color.PRESETS = {
  { key = "red", label = "Red", hex = "dd3333", hints = { "blood", "scarlet" } },
  { key = "darkred", label = "Dark red", hex = "8b1e1e" },
  { key = "crimson", label = "Crimson", hex = "b0182f" },
  { key = "ruby", label = "Ruby", hex = "c21e56" },
  { key = "orange", label = "Orange", hex = "e67d1e" },
  { key = "copper", label = "Copper", hex = "b8733d" },
  { key = "rust", label = "Rust", hex = "a0461e" },
  { key = "amber", label = "Amber", hex = "f0a020" },
  { key = "yellow", label = "Yellow", hex = "ebd237" },
  { key = "gold", label = "Gold", hex = "d4a72c", hints = { "golden" } },
  { key = "green", label = "Green", hex = "4cbb44", hints = { "verdant" } },
  { key = "darkgreen", label = "Dark green", hex = "1f5f2a" },
  { key = "lightgreen", label = "Light green", hex = "9be07a" },
  { key = "lime", label = "Lime", hex = "a6e22e" },
  { key = "olive", label = "Olive", hex = "7d7a2a" },
  { key = "emerald", label = "Emerald", hex = "1f9e5a", hints = { "jade" } },
  { key = "fel", label = "Fel", hex = "8fe000" },
  { key = "teal", label = "Teal", hex = "1ea5a0", hints = { "aqua" } },
  { key = "turquoise", label = "Turquoise", hex = "30d5c8" },
  { key = "cyan", label = "Cyan", hex = "2ad4e6" },
  { key = "blue", label = "Blue", hex = "4b7ce8", hints = { "azure" } },
  { key = "darkblue", label = "Dark blue", hex = "1f2f78", hints = { "navy" } },
  { key = "lightblue", label = "Light blue", hex = "8cc4f0", hints = { "sky" } },
  { key = "sapphire", label = "Sapphire", hex = "1f4fb0" },
  { key = "purple", label = "Purple", hex = "a060e0", hints = { "amethyst" } },
  { key = "violet", label = "Violet", hex = "8a4fd6" },
  { key = "lavender", label = "Lavender", hex = "b9a0e8" },
  { key = "darkpurple", label = "Dark purple", hex = "4a2370", hints = { "void" } },
  { key = "pink", label = "Pink", hex = "f078be" },
  { key = "magenta", label = "Magenta", hex = "d0309a" },
  { key = "rose", label = "Rose", hex = "e67fa0" },
  { key = "brown", label = "Brown", hex = "a87848", hints = { "wood" } },
  { key = "darkbrown", label = "Dark brown", hex = "4a2f1c" },
  { key = "bronze", label = "Bronze", hex = "a8743a" },
  { key = "leather", label = "Leather", hex = "8b5a33" },
  { key = "black", label = "Black", hex = "262626", hints = { "obsidian", "onyx", "ebon" } },
  { key = "gray", label = "Gray", hex = "a0a0a0", hints = { "grey", "steel", "stone" } },
  { key = "silver", label = "Silver", hex = "c0c0c8" },
  { key = "white", label = "White", hex = "ffffff", hints = { "pale", "ivory", "snow" } },
}

local presetByKey = {}
for _, preset in ipairs(Color.PRESETS) do
  presetByKey[preset.key] = preset
end

function Color.Preset(key)
  return presetByKey[key]
end

-- Group swatch shades that differ from the preset of the same key.
local GROUP_HEX = { black = "707070" }

-- Color names in display order (keys as in scripts/build_colors.py): the preset of the same key, with its group
-- swatch shade.
Color.NAMES = {}
for i, key in ipairs({
  "red",
  "orange",
  "yellow",
  "green",
  "teal",
  "blue",
  "purple",
  "pink",
  "brown",
  "black",
  "white",
  "gray",
}) do
  local preset = presetByKey[key]
  Color.NAMES[i] = { key = key, label = preset.label, hex = GROUP_HEX[key] or preset.hex }
end

-- The client language's extra color words (Locales/*.lua), by preset key.
for _, preset in ipairs(Color.PRESETS) do
  local extra = ns.LocaleColorHints and ns.LocaleColorHints[ns.locale]
  for _, hint in ipairs(extra and extra[preset.key] or {}) do
    preset.hints = preset.hints or {}
    preset.hints[#preset.hints + 1] = hint
  end
end

-- A chip's color band, in OKLab x100 as the data stores it: colors within HUE_WIDTH degrees of its hue, or, for a
-- chip under ACHROMATIC chroma (gray, black, white), colorless ones within LIGHT_WIDTH of its lightness.
local HUE_WIDTH, ACHROMATIC, LIGHT_WIDTH = 30, 5, 20
-- Inside the band, a color counts fully at the chip's shade and down to CLOSE_FLOOR of its weight far from it.
local CLOSE_RADIUS, CLOSE_FLOOR = 12, 0.3

-- OKLab of an sRGB color with channels from 0 to 1.
local function oklab(r, g, b)
  local function linear(c)
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  local function cbrt(v)
    return v < 0 and -((-v) ^ (1 / 3)) or v ^ (1 / 3)
  end
  r, g, b = linear(r), linear(g), linear(b)
  local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

-- Reference shades (sRGB 0-255) per color name; a dominant color takes the name of the nearest one.
-- Must match COLORS in scripts/build_colors.py.
local REFS = {
  red = { { 205, 40, 40 }, { 120, 20, 25 } },
  orange = { { 230, 125, 30 }, { 170, 85, 25 } },
  yellow = { { 235, 210, 55 }, { 190, 160, 40 } },
  green = { { 60, 170, 55 }, { 30, 90, 30 }, { 150, 210, 70 } },
  teal = { { 30, 165, 160 }, { 20, 95, 100 } },
  blue = { { 45, 95, 215 }, { 25, 45, 120 }, { 110, 170, 240 } },
  purple = { { 130, 60, 195 }, { 70, 30, 105 } },
  pink = { { 240, 120, 190 }, { 200, 60, 140 } },
  brown = { { 115, 72, 40 }, { 150, 105, 65 } },
  black = { { 18, 18, 20 } },
  white = { { 235, 235, 230 } },
  gray = { { 176, 176, 176 }, { 125, 125, 125 }, { 75, 75, 78 } },
}
local refNames, refL, refA, refB = {}, {}, {}, {}
for _, color in ipairs(Color.NAMES) do
  for _, rgb in ipairs(REFS[color.key]) do
    local L, a, b = oklab(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255)
    refNames[#refNames + 1], refL[#refNames + 1], refA[#refNames + 1], refB[#refNames + 1] =
      color.key, L * 100, a * 100, b * 100
  end
end
local nameCache = {}

-- Color name of an OKLab color scaled like the data (x100): the name of the nearest reference shade.
function Color.Name(L, a, b)
  local key = (L * 512 + a + 256) * 512 + b + 256
  local name = nameCache[key]
  if name then
    return name
  end
  local best, bestD = 1, math.huge
  for i = 1, #refNames do
    local dL, da, db = L - refL[i], a - refA[i], b - refB[i]
    local d = dL * dL + da * da + db * db
    if d < bestD then
      best, bestD = i, d
    end
  end
  nameCache[key] = refNames[best]
  return refNames[best]
end

-- A picked sRGB color (channels 0-1) as an OKLab target scaled like the data, for a color chip.
function Color.ChipTarget(r, g, b)
  local L, a, bb = oklab(r, g, b)
  return { L * 100, a * 100, bb * 100 }
end

-- "rrggbb" as sRGB channels 0-1.
function Color.FromHex(hex)
  return {
    r = tonumber(hex:sub(1, 2), 16) / 255,
    g = tonumber(hex:sub(3, 4), 16) / 255,
    b = tonumber(hex:sub(5, 6), 16) / 255,
  }
end

-- The color name each preset's shade falls under, for icon counts.
for _, preset in ipairs(Color.PRESETS) do
  local c = Color.FromHex(preset.hex)
  local t = Color.ChipTarget(c.r, c.g, c.b)
  preset.name = Color.Name(t[1], t[2], t[3])
end

local CLOSE_SPREAD = 2 * CLOSE_RADIUS * CLOSE_RADIUS
local deg, atan2, sqrt, exp, abs = math.deg, math.atan2, math.sqrt, math.exp, math.abs

-- A chip's band, worked out once per search: hue and chroma of its target.
function Color.ChipBand(chip)
  local t = chip.target
  local chroma = sqrt(t[2] * t[2] + t[3] * t[3])
  return { L = t[1], a = t[2], b = t[3], hue = chroma >= ACHROMATIC and deg(atan2(t[3], t[2])) or nil }
end

-- A chip's part of an icon: nil when under MIN_SHARE of the icon lies in its band, else the band's weight, each
-- color counted less the farther it lies from the chip's shade. Also returns the share in the band.
function Color.ChipValue(index, row, band)
  local share, value, slots = 0, 0, index.colorSlots
  for k = 1, #slots do
    local slot = slots[k]
    local w = slot.w[row]
    if w and w > 0 then
      local L, a, b = slot.l[row], slot.a[row], slot.b[row]
      local chroma = sqrt(a * a + b * b)
      local inBand
      if band.hue then
        local diff = abs(deg(atan2(b, a)) - band.hue) % 360
        inBand = chroma >= ACHROMATIC and (diff <= HUE_WIDTH or diff >= 360 - HUE_WIDTH)
      else
        inBand = chroma < ACHROMATIC and abs(L - band.L) <= LIGHT_WIDTH
      end
      if inBand then
        local dL, da, db = L - band.L, a - band.a, b - band.b
        share = share + w
        value = value + w * (CLOSE_FLOOR + (1 - CLOSE_FLOOR) * exp(-(dL * dL + da * da + db * db) / CLOSE_SPREAD))
      end
    end
  end
  return share >= MIN_SHARE and value or nil, share
end

-- Share (0-100) of a named color in an index row: the weight of its dominant colors with that name.
function Color.Share(index, row, name)
  local share = 0
  for _, slot in ipairs(index.colorSlots) do
    if slot.name[row] == name then
      share = share + slot.w[row]
    end
  end
  return share
end

-- Color part of a score, or nil when a chip misses: the chips' values averaged by their weights (default 1).
-- `bands` are the chips' ChipBand.
function Color.ChipScore(index, row, chips, bands)
  local total, weights = 0, 0
  for i = 1, #chips do
    local value = Color.ChipValue(index, row, bands[i])
    if not value then
      return nil
    end
    local weight = chips[i].weight or 1
    total, weights = total + weight * value, weights + weight
  end
  return total / weights
end
