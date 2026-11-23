local ADDON_NAME, ns = ...

local Search = {}
ns.Search = Search

local byte, find, gsub, lower, sub = string.byte, string.find, string.gsub, string.lower, string.sub

-- Weights per search-text field: name buckets (1st, 2nd, 3rd-4th, rest), file name, description.
-- Names and file name compete for the best hit; the description adds on top.
local FIELD_WEIGHTS = { 10, 8, 6, 4, 6, 3 }
local DESC_FIELD = 6
local QUALITY_EXACT, QUALITY_PREFIX, QUALITY_SYNONYM, QUALITY_FUZZY = 1, 0.7, 0.6, 0.5
local BONUS_PHRASE, BONUS_USABLE, BONUS_PLAYER, SCORE_ID = 5, 2, 2, 1000

-- Must match STOPWORDS in scripts/build_data.py.
local STOPWORDS = {}
for word in
  ([[a an and are as at be but by can for from has have in into is it its of on or per than that the their them
  then they this to up upon when while will with you your yours also each all any not over after before]]):gmatch(
    "%S+"
  )
do
  STOPWORDS[word] = true
end

-- Must match FILE_NOISE in scripts/build_data.py.
local FILE_NOISE = { inv = true, misc = true, ability = true, spell = true, icon = true, achievement = true }

-- Accented Latin letters (UTF-8) to base letters. Must match FOLD in scripts/build_data.py.
local FOLD = { ["\225\186\158"] = "ss" }
do
  local bases = {
    { "\192\193\194\195\196\197\224\225\226\227\228\229", "a" },
    { "\198\230", "ae" },
    { "\199\231", "c" },
    { "\200\201\202\203\232\233\234\235", "e" },
    { "\204\205\206\207\236\237\238\239", "i" },
    { "\208\240", "d" },
    { "\209\241", "n" },
    { "\210\211\212\213\214\216\242\243\244\245\246\248", "o" },
    { "\217\218\219\220\249\250\251\252", "u" },
    { "\221\253\255", "y" },
    { "\222\254", "th" },
    { "\223", "ss" },
  }
  -- Latin-1 code point c (192-255) is "\195" followed by c - 64 in UTF-8.
  for _, entry in ipairs(bases) do
    for i = 1, #entry[1] do
      FOLD["\195" .. string.char(byte(entry[1], i) - 64)] = entry[2]
    end
  end
end

function Search.Normalize(text)
  text = gsub(gsub(text or "", "\225\186\158", FOLD), "\195[\128-\191]", FOLD)
  text = lower(text)
  text = gsub(text, "'", "")
  text = gsub(text, "\226\128\153", "")
  text = gsub(text, "[^%w]+", " ")
  return (gsub(gsub(text, "^%s+", ""), "%s+$", ""))
end

-- Light English suffix stripping so "marks", "marked" and "marking" meet at "mark". Mirrored in build_data.py.
function Search.Stem(token)
  local n = #token
  if n <= 3 or find(token, "^%d+$") then
    return token
  end
  if n > 5 and sub(token, -3) == "ing" then
    return sub(token, 1, -4)
  end
  if n > 4 and sub(token, -3) == "ies" then
    return sub(token, 1, -4) .. "y"
  end
  if n > 4 and sub(token, -2) == "ed" then
    return sub(token, 1, -3)
  end
  if n > 4 and (sub(token, -3) == "hes" or sub(token, -3) == "xes" or sub(token, -3) == "ses") then
    return sub(token, 1, -3)
  end
  if sub(token, -1) == "s" and sub(token, -2) ~= "ss" then
    return sub(token, 1, -2)
  end
  return token
end

-- Normalized, stemmed tokens without stopwords.
function Search.Tokens(text)
  local tokens = {}
  for token in gsub(Search.Normalize(text), "%s+", " "):gmatch("%S+") do
    if not STOPWORDS[token] then
      tokens[#tokens + 1] = Search.Stem(token)
    end
  end
  return tokens
end

-- Search text for an icon without data: only its file name is known.
function Search.FileText(file)
  local list = {}
  for _, token in ipairs(Search.Tokens(gsub(file or "", "%d+", " "))) do
    if not FILE_NOISE[token] then
      list[#list + 1] = token
    end
  end
  return "||||" .. table.concat(list, " ") .. "|"
end

-- Pads a data search field string ("a b|c|...") so every token is surrounded by spaces.
function Search.PadText(text)
  return " " .. gsub(text or "", "|", " | ") .. " "
end

-- Synonym groups ({ {"cloak", "cape", ...}, ... }) become token -> { other tokens }.
function Search.BuildSynonyms(groups)
  local map = {}
  for _, group in ipairs(groups or {}) do
    local stems = {}
    for _, word in ipairs(group) do
      for _, token in ipairs(Search.Tokens(word)) do
        stems[#stems + 1] = token
      end
    end
    for _, token in ipairs(stems) do
      map[token] = map[token] or {}
      local seen = {}
      for _, other in ipairs(map[token]) do
        seen[other] = true
      end
      for _, other in ipairs(stems) do
        if other ~= token and not seen[other] then
          seen[other] = true
          map[token][#map[token] + 1] = other
        end
      end
    end
  end
  return map
end

-- Edit distance with adjacent swaps, capped at `max` (returns max + 1 when exceeded).
function Search.Distance(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then
    return max + 1
  end
  local min = math.min
  local prev2, prev = nil, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    local cur = { [0] = i }
    local rowMin = i
    local ca = byte(a, i)
    for j = 1, lb do
      local cb = byte(b, j)
      local v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb and 0 or 1))
      if prev2 and j > 1 and ca == byte(b, j - 1) and byte(a, i - 1) == cb then
        v = min(v, prev2[j - 2] + 1)
      end
      cur[j] = v
      if v < rowMin then
        rowMin = v
      end
    end
    if rowMin > max then
      return max + 1
    end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

-- Cheap pre-check: typo candidates share the first letter, or swap the first two.
local function couldBeTypo(token, word)
  local t1, w1 = byte(token, 1), byte(word, 1)
  return t1 == w1 or (t1 == byte(word, 2) and byte(token, 2) == w1)
end

local function fuzzyBudget(token)
  if #token >= 7 then
    return 2
  elseif #token >= 4 then
    return 1
  end
  return 0
end

-- Every distinct token of the given texts, for typo lookups.
function Search.Vocabulary(texts)
  local seen, list = {}, {}
  for _, text in ipairs(texts) do
    for token in text:gmatch("[^%s|]+") do
      if not seen[token] then
        seen[token] = true
        list[#list + 1] = token
      end
    end
  end
  return list
end

-- Field (1-6) of a position in a padded search text.
local function fieldAt(text, pos)
  local field, p = 1, find(text, "|", 1, true)
  while p and p < pos do
    field = field + 1
    p = find(text, "|", p + 1, true)
  end
  return field
end

-- Best name/file hit and description hit of one term in a padded search text.
local function termScore(text, term, quality)
  local needle = " " .. term
  local p = find(text, needle, 1, true)
  if not p then
    return 0, 0
  end
  local allowPrefix = #term >= 3
  local name, desc = 0, 0
  local len = #needle
  while p do
    local exact = byte(text, p + len) == 32
    if exact or allowPrefix then
      local field = fieldAt(text, p)
      local score = FIELD_WEIGHTS[field] * quality * (exact and 1 or QUALITY_PREFIX)
      if field == DESC_FIELD then
        if score > desc then
          desc = score
        end
      elseif score > name then
        name = score
      end
    end
    p = find(text, needle, p + len, true)
  end
  return name, desc
end

-- Score of one query token over its variants (itself, synonyms, typo variants): the best name hit plus
-- the best description hit, which may come from different variants.
local function tokenScore(text, variants)
  local bestName, bestDesc = 0, 0
  for i = 1, #variants, 2 do
    local name, desc = termScore(text, variants[i], variants[i + 1])
    if name > bestName then
      bestName = name
    end
    if desc > bestDesc then
      bestDesc = desc
    end
  end
  return bestName + bestDesc
end

local function variantsFor(token, synonyms, vocabulary)
  local variants = { token, QUALITY_EXACT }
  for _, other in ipairs(synonyms[token] or {}) do
    variants[#variants + 1] = other
    variants[#variants + 1] = QUALITY_SYNONYM
  end
  if vocabulary then
    local budget = fuzzyBudget(token)
    if budget > 0 then
      for _, word in ipairs(vocabulary) do
        if word ~= token and couldBeTypo(token, word) and Search.Distance(token, word, budget) <= budget then
          variants[#variants + 1] = word
          variants[#variants + 1] = QUALITY_FUZZY
        end
      end
    end
  end
  return variants
end

-- Minimum share (0-100) of a named colour for a named colour chip to match.
local COLOR_MIN = 20
Search.COLOR_MIN = COLOR_MIN

-- Colour names in display order (keys as in scripts/build_colors.py), with a hex shade for swatches and other
-- words that suggest the colour.
Search.COLORS = {
  { key = "red", label = "Red", hex = "dd3333", hints = { "crimson", "scarlet", "blood", "ruby" } },
  { key = "orange", label = "Orange", hex = "e67d1e", hints = { "copper", "rust" } },
  { key = "yellow", label = "Yellow", hex = "ebd237", hints = { "gold", "golden", "amber" } },
  { key = "green", label = "Green", hex = "4cbb44", hints = { "emerald", "jade", "verdant", "fel" } },
  { key = "teal", label = "Teal", hex = "1ea5a0", hints = { "cyan", "turquoise", "aqua" } },
  { key = "blue", label = "Blue", hex = "4b7ce8", hints = { "azure", "sapphire", "sky" } },
  { key = "purple", label = "Purple", hex = "a060e0", hints = { "violet", "amethyst", "void" } },
  { key = "pink", label = "Pink", hex = "f078be", hints = { "magenta", "rose" } },
  { key = "brown", label = "Brown", hex = "a87848", hints = { "leather", "wood", "bronze" } },
  { key = "black", label = "Black", hex = "707070", hints = { "dark", "obsidian", "onyx", "ebon" } },
  { key = "white", label = "White", hex = "ffffff", hints = { "pale", "ivory", "snow" } },
  { key = "grey", label = "Grey", hex = "a0a0a0", hints = { "gray", "silver", "steel", "stone" } },
}

-- The client language's extra colour words (Locales/*.lua).
for _, color in ipairs(Search.COLORS) do
  local extra = ns.LocaleColorHints and ns.LocaleColorHints[ns.locale]
  for _, hint in ipairs(extra and extra[color.key] or {}) do
    color.hints[#color.hints + 1] = hint
  end
end

-- OKLab distance (x100, as the data stores it) over which a dominant colour stops matching a picked one.
local PICK_RADIUS = 5
-- Minimum closeness (0-100) of an icon to a picked colour.
local PICK_MIN = 10
Search.PICK_MIN = PICK_MIN

-- OKLab of an sRGB colour with channels from 0 to 1.
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

-- A picked sRGB colour (channels 0-1) as an OKLab target scaled like the data, for an exact colour chip.
function Search.PickTarget(r, g, b)
  local L, a, bb = oklab(r, g, b)
  return { L * 100, a * 100, bb * 100 }
end

local PICK_SPREAD = 2 * PICK_RADIUS * PICK_RADIUS
-- Beyond three radii a colour adds under 1.2% of its weight; it is skipped.
local PICK_FAR = 9 * PICK_RADIUS * PICK_RADIUS

-- Closeness (0-100) of an index row to a picked colour: the weight of its dominant colours, each counted by how
-- near it is to the pick.
local function pickScore(index, row, pick)
  local score, exp, slots = 0, math.exp, index.colorSlots
  local pL, pa, pb = pick[1], pick[2], pick[3]
  for k = 1, #slots do
    local slot = slots[k]
    local weight = slot.w[row]
    if weight and weight > 0 then
      local dL, da, db = slot.l[row] - pL, slot.a[row] - pa, slot.b[row] - pb
      local d2 = dL * dL + da * da + db * db
      if d2 < PICK_FAR then
        score = score + weight * exp(-d2 / PICK_SPREAD)
      end
    end
  end
  return score
end

-- Share (0-100) of a named colour in an index row: the weight of its dominant colours with that name.
function Search.ColorShare(index, row, color)
  local share = 0
  for _, slot in ipairs(index.colorSlots) do
    if slot.name[row] == color then
      share = share + slot.w[row]
    end
  end
  return share
end

-- Colour part of a score, or nil when a chip misses: a named chip ({ key }) needs COLOR_MIN of that colour name,
-- an exact one ({ target }, from PickTarget) PICK_MIN closeness. Ranks by the weakest chip.
local function chipScore(index, row, chips)
  local weakest
  for i = 1, #chips do
    local chip = chips[i]
    local score
    if chip.target then
      score = pickScore(index, row, chip.target)
      if score < PICK_MIN then
        return nil
      end
    else
      score = Search.ColorShare(index, row, chip.key)
      if score < COLOR_MIN then
        return nil
      end
    end
    if not weakest or score < weakest then
      weakest = score
    end
  end
  return weakest
end

-- One pass over the candidate rows. `index` holds the columns (see Catalog.NewIndex).
local function run(index, rows, query, opts, loose)
  local tokens = Search.Tokens(query)
  local synonyms = opts.synonyms or {}
  local usable = opts.usable
  local idQuery = tonumber(Search.Normalize(query))
  local phrase = #tokens > 1 and (" " .. table.concat(tokens, " ") .. " ") or nil

  local vocabulary = loose and opts.vocabulary and opts.vocabulary() or nil
  local variants = {}
  for i, token in ipairs(tokens) do
    variants[i] = variantsFor(token, synonyms, vocabulary)
  end

  local texts, ids, keys, spells = index.text, index.id, index.key, index.spells
  local chips = opts.chips and #opts.chips > 0 and opts.chips or nil
  local scores, closeness, results = {}, {}, {}
  for _, row in ipairs(rows) do
    local score = 0
    local colorPart = chips and chipScore(index, row, chips)
    if chips and not colorPart then
      score = 0
    elseif idQuery and ids[row] == idQuery then
      score = SCORE_ID
    elseif #tokens == 0 then
      -- Colour chips alone keep every icon that has their colours.
      score = chips and 1 or 0
    else
      local text = texts[row]
      local matched = 0
      for i = 1, #tokens do
        local s = tokenScore(text, variants[i])
        if s > 0 then
          matched = matched + 1
          score = score + s
        elseif not loose then
          score = 0
          break
        end
      end
      if score > 0 then
        if loose then
          score = score * matched / #tokens
        end
        if phrase and find(text, phrase, 1, true) then
          score = score + BONUS_PHRASE
        end
      end
    end
    if score > 0 then
      if usable and usable[keys[row]] then
        score = score + BONUS_USABLE
      end
      if spells[row] then
        score = score + BONUS_PLAYER
      end
      scores[row] = score
      closeness[row] = colorPart
      results[#results + 1] = row
    end
  end

  local position = {}
  for i, row in ipairs(rows) do
    position[row] = i
  end
  table.sort(results, function(a, b)
    if chips and closeness[a] ~= closeness[b] then
      return closeness[a] > closeness[b]
    end
    if scores[a] ~= scores[b] then
      return scores[a] > scores[b]
    end
    return position[a] < position[b]
  end)
  return results, scores
end

-- Ranked rows matching every query token; when none do, a looser pass (any token, typos) and
-- `isLoose = true`. Returns rows, isLoose, scores (row -> score).
-- opts: synonyms (from BuildSynonyms), usable (key -> true), vocabulary (function returning a token list),
-- chips (colour chips, see chipScore: keeps icons with every chip's colour and ranks them by the weakest first).
function Search.Find(index, rows, query, opts)
  opts = opts or {}
  local results, scores = run(index, rows, query, opts, false)
  if #results > 0 or #Search.Tokens(query) == 0 then
    return results, false, scores
  end
  results, scores = run(index, rows, query, opts, true)
  return results, true, scores
end
