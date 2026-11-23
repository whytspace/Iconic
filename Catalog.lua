local ADDON_NAME, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local L = ns.L
local floor = math.floor

-- Sources in display order; `bit` is the source's bit in the src column, as written by scripts/build_data.py.
Catalog.SOURCES = {
  { key = "S", bit = 1, label = "Spells" },
  { key = "I", bit = 2, label = "Items" },
  { key = "M", bit = 4, label = "Mounts" },
  { key = "P", bit = 8, label = "Pets" },
  { key = "C", bit = 32, label = "Currencies" },
}

local SOURCE_BITS = {}
for _, source in ipairs(Catalog.SOURCES) do
  SOURCE_BITS[source.key] = source.bit
end

-- Stands in for an empty list column.
local NONE = {}

local function hasBit(mask, bit)
  return floor(mask / bit) % 2 == 1
end

-- Category number (class * 256 + subclass, as in the data) -> "class:subclass" filter key.
local CATEGORY_KEYS = setmetatable({}, {
  __index = function(keys, number)
    local key = floor(number / 256) .. ":" .. number % 256
    keys[number] = key
    return key
  end,
})

Catalog.GROUPS = {
  { key = "none", label = "None" },
  { key = "source", label = "Source" },
  { key = "class", label = "Class" },
  { key = "category", label = "Item category" },
  { key = "profession", label = "Profession" },
  { key = "color", label = "Color" },
}

-- "key<TAB>name[<TAB>icon]" lines into key -> name and key -> icon.
local function lookup(body)
  local map, icons = {}, {}
  for line in (body or ""):gmatch("[^\n]+") do
    local key, name, icon = line:match("^([^\t]+)\t([^\t]*)\t?(%d*)$")
    if key then
      key = tonumber(key) or key
      map[key] = name
      icons[key] = tonumber(icon)
    end
  end
  return map, icons
end

-- Column store, one row per icon. Columns: key (file ID or texture path), id, texture, file, names
-- (display, "a|b"), text (padded search text), src (source bits), cls (class bits), cats (category numbers),
-- profs (profession IDs), spells (spell IDs); list columns are nil when empty. colorSlots: per dominant colour, the
-- columns l, a, b (OKLab * 100), w (weight 0-100) and name (nearest colour key).
function Catalog.NewIndex()
  return {
    count = 0,
    byKey = {},
    key = {},
    id = {},
    texture = {},
    file = {},
    refs = {},
    text = {},
    src = {},
    cls = {},
    cats = {},
    profs = {},
    spells = {},
    colorSlots = {},
  }
end

-- A row for a texture without data: only its file name is searched.
local function addRow(index, key, id, texture, file)
  local row = index.count + 1
  index.count = row
  index.byKey[key] = row
  index.key[row] = key
  index.id[row] = id
  index.texture[row] = texture
  index.file[row] = file
  index.text[row] = ns.Search.PadText(ns.Search.FileText(file))
  index.src[row] = 0
  index.cls[row] = 0
  return row
end

local COLUMNS = { "file", "refs", "text", "src", "cls", "cats", "profs", "spells" }

-- Search words per item category number (class * 256 + subclass) the icons use: its own and its class's name, padded
-- like search text (" a b "), for Search.Find.
local function categoryWords(data)
  local words, labels, Search = {}, data.itemClasses or {}, ns.Search
  for _, list in pairs(data.index.cats) do
    for _, number in ipairs(list) do
      if not words[number] then
        local class = math.floor(number / 256)
        local name = (labels[class .. ":" .. number % 256] or "") .. " " .. (labels[class] or "")
        words[number] = " " .. table.concat(Search.Tokens(name), " ") .. " "
      end
    end
  end
  return words
end
Catalog.CategoryWords = categoryWords

-- Turns the table a data add-on leaves in the global IconicData into lookups and an index. The index takes
-- over the data's columns, so `raw` must not be parsed twice.
function Catalog.Parse(raw)
  local data = {
    flavor = raw.flavor,
    build = raw.build,
    classes = lookup(raw.classes),
    itemClasses = lookup(raw.itemClasses),
    professions = nil,
    professionIcons = nil,
    index = Catalog.NewIndex(),
    byFile = {},
  }
  data.professions, data.professionIcons = lookup(raw.professions)
  local index, icons = data.index, raw.icons or {}
  local ids = icons.id or {}
  index.id = ids
  for _, name in ipairs(COLUMNS) do
    index[name] = icons[name] or {}
  end
  local colors = icons.colors or {}
  for k = 1, math.huge do
    if not colors["w" .. k] then
      break
    end
    local slot = { l = colors["l" .. k], a = colors["a" .. k], b = colors["b" .. k], w = colors["w" .. k], name = {} }
    for row = 1, #slot.w do
      if slot.w[row] > 0 then
        slot.name[row] = ns.Search.ColorName(slot.l[row], slot.a[row], slot.b[row])
      end
    end
    index.colorSlots[k] = slot
  end
  index.hasColors = #index.colorSlots > 0
  local key, texture, byKey, byFile, file = index.key, index.texture, index.byKey, data.byFile, index.file
  for row = 1, #ids do
    local id = ids[row]
    key[row], texture[row], byKey[id] = id, id, row
    byFile[file[row]:lower()] = id
  end
  index.count = #ids
  index.categoryWords = categoryWords(data)
  return data
end

-- Takes over a translation's labels, display names and search text (translated words first, then English).
-- Its rows are keyed by file ID; icons it does not list keep their English data.
function Catalog.ApplyLocale(data, raw)
  if raw.classes then
    data.classes = lookup(raw.classes)
  end
  if raw.itemClasses then
    data.itemClasses = lookup(raw.itemClasses)
    data.index.categoryWords = categoryWords(data)
  end
  if raw.professions then
    data.professions, data.professionIcons = lookup(raw.professions)
  end
  local index, icons = data.index, raw.icons or {}
  local refs, text = icons.refs or {}, icons.text or {}
  for i, id in ipairs(icons.id or {}) do
    local row = index.byKey[id]
    if row then
      index.refs[row] = refs[i] or index.refs[row]
      index.text[row] = text[i] or index.text[row]
    end
  end
end

-- File ID for a provider texture: a number, or an "Interface\Icons\name" path.
function Catalog.ResolveId(data, texture)
  if type(texture) == "number" then
    return texture
  end
  if type(texture) == "string" then
    local name = string.lower(texture):gsub("^interface[\\/]icons[\\/]", ""):gsub("%.blp$", "")
    return tonumber(name) or (data and data.byFile[name])
  end
end

-- Rows for a list of provider textures, in order and without duplicates. Textures without data get
-- a row with just their file name. Also returns the data and row -> position of its texture in `textures`.
function Catalog.Rows(data, textures)
  data = data or { index = Catalog.NewIndex(), byFile = {}, classes = {}, itemClasses = {}, professions = {} }
  local index, rows, seen = data.index, {}, {}
  for position, texture in ipairs(textures) do
    local id = Catalog.ResolveId(data, texture)
    local key = id or texture
    local row = index.byKey[key]
    if not row then
      local file = type(texture) == "string" and string.lower(texture):match("([^\\/]+)$") or nil
      row = addRow(index, key, id, texture, file)
    end
    if not seen[row] then
      seen[row] = position
      rows[#rows + 1] = row
    end
  end
  return rows, data, seen
end

function Catalog.HasClass(mask, classId)
  return hasBit(mask, 2 ^ (classId - 1))
end

local function classIds(mask)
  local list, classId = {}, 1
  while mask > 0 do
    if mask % 2 == 1 then
      list[#list + 1] = classId
    end
    mask = floor(mask / 2)
    classId = classId + 1
  end
  return list
end

-- Decoded masks, cached: few distinct masks occur. The lists are shared, so never change them.
local function cachedLists(decode)
  return setmetatable({}, {
    __index = function(cache, mask)
      local list = decode(mask)
      cache[mask] = list
      return list
    end,
  })
end
local CLASS_IDS = cachedLists(classIds)
local SOURCE_KEYS = cachedLists(function(mask)
  local list = {}
  for _, source in ipairs(Catalog.SOURCES) do
    if hasBit(mask, source.bit) then
      list[#list + 1] = source.key
    end
  end
  return list
end)

-- Per filter group: does a row match one of the selected values?
local DIMENSION_MATCHERS = {
  source = function(index, row, selected)
    local src = index.src[row]
    for key in pairs(selected) do
      -- A saved filter may name a source that is gone (achievements).
      if SOURCE_BITS[key] and hasBit(src, SOURCE_BITS[key]) then
        return true
      end
    end
    return false
  end,
  class = function(index, row, selected)
    local mask = index.cls[row]
    for classId in pairs(selected) do
      if Catalog.HasClass(mask, classId) then
        return true
      end
    end
    return false
  end,
  category = function(index, row, selected)
    local cats = index.cats[row]
    if not cats then
      return false
    end
    for _, number in ipairs(cats) do
      if selected[floor(number / 256)] or selected[CATEGORY_KEYS[number]] then
        return true
      end
    end
    return false
  end,
  profession = function(index, row, selected)
    local profs = index.profs[row]
    if not profs then
      return false
    end
    for _, prof in ipairs(profs) do
      if selected[prof] then
        return true
      end
    end
    return false
  end,
}
Catalog.DIMENSIONS = { "source", "class", "category", "profession" }

-- filters: { source = {S=true}, class = {[8]=true}, category = {[2]=true, ["2:7"]=true},
-- profession = {[164]=true}, usable = true }; usableSet: key -> true.
-- Values within a group combine with OR, groups with AND. `skip` names a group to ignore.
function Catalog.Matches(index, row, filters, usableSet, skip)
  if not filters then
    return true
  end
  if filters.usable and not (usableSet and usableSet[index.key[row]]) then
    return false
  end
  for _, dim in ipairs(Catalog.DIMENSIONS) do
    local selected = filters[dim]
    if dim ~= skip and selected and next(selected) and not DIMENSION_MATCHERS[dim](index, row, selected) then
      return false
    end
  end
  return true
end

function Catalog.Filter(index, rows, filters, usableSet)
  if Catalog.ActiveFilterCount(filters) == 0 then
    return rows
  end
  local list = {}
  for _, row in ipairs(rows) do
    if Catalog.Matches(index, row, filters, usableSet) then
      list[#list + 1] = row
    end
  end
  return list
end

-- Icons per filter value: { source = {S=n}, class = {[id]=n}, category = {[2]=n, ["2:7"]=n}, profession = {[id]=n} }.
function Catalog.Counts(index, rows)
  local counts = { source = {}, class = {}, category = {}, profession = {}, color = {} }
  local source, class, category, profession = counts.source, counts.class, counts.category, counts.profession
  local srcs, clss, catLists, profLists = index.src, index.cls, index.cats, index.profs
  for _, row in ipairs(rows) do
    for _, key in ipairs(SOURCE_KEYS[srcs[row]]) do
      source[key] = (source[key] or 0) + 1
    end
    for _, classId in ipairs(CLASS_IDS[clss[row]]) do
      class[classId] = (class[classId] or 0) + 1
    end
    local cats = catLists[row]
    if cats then
      for i, number in ipairs(cats) do
        local key, top = CATEGORY_KEYS[number], floor(number / 256)
        category[key] = (category[key] or 0) + 1
        -- Lists are sorted, so a top category repeats only right after itself.
        if i == 1 or floor(cats[i - 1] / 256) ~= top then
          category[top] = (category[top] or 0) + 1
        end
      end
    end
    for _, prof in ipairs(profLists[row] or NONE) do
      profession[prof] = (profession[prof] or 0) + 1
    end
  end
  local minimum, color, slots = ns.Search.COLOR_MIN, counts.color, index.colorSlots
  local shares = {}
  for _, row in ipairs(rows) do
    for _, slot in ipairs(slots) do
      local name = slot.name[row]
      if name then
        shares[name] = (shares[name] or 0) + slot.w[row]
      end
    end
    for name, share in pairs(shares) do
      if share >= minimum then
        color[name] = (color[name] or 0) + 1
      end
      shares[name] = nil
    end
  end
  return counts
end

-- Counts per filter value as if that value were also ticked: each group's counts honour every other
-- group's active filters (and the usable filter) but not its own, since values in one group combine with OR.
function Catalog.FacetCounts(index, rows, filters, usableSet)
  local active = {}
  for _, dim in ipairs(Catalog.DIMENSIONS) do
    if filters and filters[dim] and next(filters[dim]) then
      active[#active + 1] = dim
    end
  end
  local counts = { source = {}, class = {}, category = {}, profession = {} }
  local buckets = {}
  for _, row in ipairs(rows) do
    if not (filters and filters.usable) or (usableSet and usableSet[index.key[row]]) then
      local failed, failedDim = 0, nil
      for _, dim in ipairs(active) do
        if not DIMENSION_MATCHERS[dim](index, row, filters[dim]) then
          failed = failed + 1
          failedDim = dim
          if failed > 1 then
            break
          end
        end
      end
      -- Matching every group counts for all; failing exactly one counts only for that group's values.
      if failed == 0 then
        buckets.all = buckets.all or {}
        table.insert(buckets.all, row)
      elseif failed == 1 then
        buckets[failedDim] = buckets[failedDim] or {}
        table.insert(buckets[failedDim], row)
      end
    end
  end
  local all = Catalog.Counts(index, buckets.all or {})
  for _, dim in ipairs(Catalog.DIMENSIONS) do
    counts[dim] = all[dim]
    if buckets[dim] then
      for value, n in pairs(Catalog.Counts(index, buckets[dim])[dim]) do
        counts[dim][value] = (counts[dim][value] or 0) + n
      end
    end
  end
  return counts
end

function Catalog.ActiveFilterCount(filters)
  local count = filters and filters.usable and 1 or 0
  for _, dim in ipairs(Catalog.DIMENSIONS) do
    for _ in pairs(filters and filters[dim] or {}) do
      count = count + 1
    end
  end
  return count
end

local DULL = { grey = true, black = true, white = true, brown = true }
-- Minimum weight (0-100) of a colour that names a group, and OKLab chroma (x100) a vivid colour needs.
local GROUP_MIN_WEIGHT, VIVID_CHROMA = 10, 4

-- Colour group of a row and the weight of that colour: its strongest vivid colour covering GROUP_MIN_WEIGHT, else
-- such a brown, else its strongest colour of any kind.
local function colorGroup(index, row)
  local vivid, vividWeight, brownWeight, strongest, strongestWeight
  for _, slot in ipairs(index.colorSlots) do
    local name, weight = slot.name[row], slot.w[row]
    if name and weight > 0 then
      if not strongestWeight or weight > strongestWeight then
        strongest, strongestWeight = name, weight
      end
      if weight >= GROUP_MIN_WEIGHT then
        if name == "brown" then
          brownWeight = math.max(brownWeight or 0, weight)
        elseif not DULL[name] and (not vividWeight or weight > vividWeight) then
          local a, b = slot.a[row], slot.b[row]
          if a * a + b * b >= VIVID_CHROMA * VIVID_CHROMA then
            vivid, vividWeight = name, weight
          end
        end
      end
    end
  end
  if vivid then
    return vivid, vividWeight
  elseif brownWeight then
    return "brown", brownWeight
  end
  return strongest, strongestWeight
end

-- Group values of a row for a group-by key; an empty list puts it under "Other".
function Catalog.GroupValues(index, row, groupBy)
  local values = {}
  if groupBy == "source" then
    local src = index.src[row]
    for _, source in ipairs(Catalog.SOURCES) do
      if hasBit(src, source.bit) then
        values[#values + 1] = source.key
      end
    end
  elseif groupBy == "class" then
    values = classIds(index.cls[row])
  elseif groupBy == "category" then
    local seen = {}
    for _, number in ipairs(index.cats[row] or NONE) do
      local top = floor(number / 256)
      if not seen[top] then
        seen[top] = true
        values[#values + 1] = top
      end
    end
  elseif groupBy == "profession" then
    for i, prof in ipairs(index.profs[row] or NONE) do
      values[i] = prof
    end
  elseif groupBy == "color" then
    values[1] = colorGroup(index, row)
  end
  return values
end

-- Display name of one group value.
function Catalog.GroupLabel(data, groupBy, value)
  if groupBy == "source" then
    for _, source in ipairs(Catalog.SOURCES) do
      if source.key == value then
        return L[source.label]
      end
    end
  elseif groupBy == "class" then
    return data and data.classes[value] or tostring(value)
  elseif groupBy == "category" then
    return data and data.itemClasses[value] or tostring(value)
  elseif groupBy == "profession" then
    return data and data.professions[value] or tostring(value)
  elseif groupBy == "color" then
    for _, color in ipairs(ns.Search.COLORS) do
      if color.key == value then
        return L[color.label]
      end
    end
  end
  return tostring(value)
end

local SOURCE_RANK = {}
for i, source in ipairs(Catalog.SOURCES) do
  SOURCE_RANK[source.key] = i
end

local COLOR_RANK = {}
for i, color in ipairs(ns.Search.COLORS) do
  COLOR_RANK[color.key] = i
end

local function groupOrder(data, groupBy, a, b)
  if groupBy == "source" then
    return (SOURCE_RANK[a] or 99) < (SOURCE_RANK[b] or 99)
  elseif groupBy == "color" then
    return COLOR_RANK[a] < COLOR_RANK[b]
  elseif groupBy == "profession" then
    return Catalog.GroupLabel(data, groupBy, a) < Catalog.GroupLabel(data, groupBy, b)
  end
  return a < b
end

-- Splits rows into sections ({ title, rows, value }), keeping the order inside each. Rows appear in every
-- section they belong to; rows without a value land in "Other".
function Catalog.Sections(data, rows, groupBy, recentRows, suggestedRows)
  local index = data.index
  local sections = {}
  if suggestedRows and #suggestedRows > 0 then
    sections[#sections + 1] = { title = L["Suggested"], rows = suggestedRows, suggested = true }
  end
  if recentRows and #recentRows > 0 then
    sections[#sections + 1] = { title = L["Recently used"], rows = recentRows, recent = true }
  end
  if groupBy == nil or groupBy == "none" then
    if #rows > 0 then
      sections[#sections + 1] = { title = (#sections > 0) and L["All icons"] or nil, rows = rows }
    end
    return sections
  end

  local byValue, values, other = {}, {}, {}
  for _, row in ipairs(rows) do
    local list = Catalog.GroupValues(index, row, groupBy)
    if #list == 0 then
      other[#other + 1] = row
    end
    for _, value in ipairs(list) do
      if not byValue[value] then
        byValue[value] = {}
        values[#values + 1] = value
      end
      table.insert(byValue[value], row)
    end
  end
  table.sort(values, function(a, b)
    return groupOrder(data, groupBy, a, b)
  end)
  for _, value in ipairs(values) do
    local list = byValue[value]
    if groupBy == "color" then
      -- Most of the group's colour first; equal weights keep the incoming order.
      local position, share = {}, {}
      for i, row in ipairs(list) do
        position[row] = i
        share[row] = select(2, colorGroup(index, row))
      end
      table.sort(list, function(a, b)
        local sa, sb = share[a], share[b]
        if sa ~= sb then
          return sa > sb
        end
        return position[a] < position[b]
      end)
    end
    sections[#sections + 1] = { title = Catalog.GroupLabel(data, groupBy, value), rows = list, value = value }
  end
  if #other > 0 then
    sections[#sections + 1] = { title = L["Other"], rows = other }
  end
  return sections
end

-- Every filter value as a suggestion candidate: { dim, value, label, group }.
local function filterCandidates(data)
  local list = {}
  local function add(dim, value, label, group, hints)
    list[#list + 1] = { dim = dim, value = value, label = label, group = group, hints = hints }
  end
  for _, source in ipairs(Catalog.SOURCES) do
    add("source", source.key, L[source.label], L["Source"])
  end
  for classId, name in pairs(data.classes or {}) do
    add("class", classId, name, L["Class"])
  end
  for key, name in pairs(data.itemClasses or {}) do
    local top = type(key) == "string" and tonumber(key:match("^(%d+):"))
    local parent = top and data.itemClasses[top]
    add("category", key, (parent and parent ~= name) and (parent .. " › " .. name) or name, L["Item category"])
  end
  for prof, name in pairs(data.professions or {}) do
    add("profession", prof, name, L["Profession"])
  end
  for _, preset in ipairs(ns.Search.COLOR_PRESETS) do
    add("color", preset.key, L[preset.label], L["Color"], preset.hints)
    -- Icons are counted per colour name; a preset counts those of the name its shade falls under.
    list[#list].countKey = preset.name
  end
  return list
end

-- Filter values a query's words point at, best first: { dim, value, label, group, words, count }. A word
-- matches when it equals or starts a word of the value's label; a label whose every word is matched ranks above
-- one matched in part. Only values with icons and not yet active are offered. `words` are the query words to drop
-- when the suggestion is taken.
function Catalog.Suggest(data, query, counts, filters, max)
  local Search = ns.Search
  local words = {}
  for word in Search.Normalize(query):gmatch("%S+") do
    if #word >= 2 then
      words[#words + 1] = word
    end
  end
  if #words == 0 then
    return {}
  end
  local results = {}
  for _, candidate in ipairs(filterCandidates(data)) do
    local count = counts and counts[candidate.dim] and counts[candidate.dim][candidate.countKey or candidate.value] or 0
    local active = filters and filters[candidate.dim] and filters[candidate.dim][candidate.value]
    if count > 0 and not active then
      local best, bestWord
      local labelWords = Search.Tokens(candidate.label)
      local tokenCount, whole, filled, used = #labelWords, {}, 0, {}
      for _, hint in ipairs(candidate.hints or {}) do
        labelWords[#labelWords + 1] = Search.Stem(hint)
      end
      for i, labelWord in ipairs(labelWords) do
        for _, word in ipairs(words) do
          local stem = Search.Stem(word)
          local score = (labelWord == stem and 3) or (labelWord:sub(1, #stem) == stem and 2) or nil
          if score and (not best or score > best) then
            best, bestWord = score, word
          end
          if score and i <= tokenCount and not whole[i] and not used[word] then
            whole[i], used[word], filled = word, true, filled + 1
          end
        end
      end
      local matchedWords = { bestWord }
      if tokenCount > 1 and filled == tokenCount then
        best, matchedWords = 3 + tokenCount, whole
      end
      if best then
        candidate.score, candidate.words, candidate.count = best, matchedWords, count
        results[#results + 1] = candidate
      end
    end
  end
  table.sort(results, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if #a.label ~= #b.label then
      return #a.label < #b.label
    end
    return a.count > b.count
  end)
  for i = #results, (max or 5) + 1, -1 do
    results[i] = nil
  end
  return results
end

-- The query without the first word that normalizes to `word`.
function Catalog.RemoveWord(query, word)
  local kept, removed = {}, false
  for part in (query or ""):gmatch("%S+") do
    if not removed and ns.Search.Normalize(part) == word then
      removed = true
    else
      kept[#kept + 1] = part
    end
  end
  return table.concat(kept, " ")
end

-- Moves `texture` to the front of the recent list.
function Catalog.AddRecent(list, texture, max)
  if texture == nil then
    return list
  end
  for i = #list, 1, -1 do
    if list[i] == texture then
      table.remove(list, i)
    end
  end
  table.insert(list, 1, texture)
  for i = #list, (max or ns.MAX_RECENT) + 1, -1 do
    list[i] = nil
  end
  return list
end

-- Rows of the recent textures that are among `rows` and pass the filters.
function Catalog.RecentRows(data, rows, recent, filters, usableSet)
  local index, present = data.index, {}
  for _, row in ipairs(rows) do
    present[row] = true
  end
  local list = {}
  for _, texture in ipairs(recent or {}) do
    local row = index.byKey[Catalog.ResolveId(data, texture) or texture]
    if row and present[row] and Catalog.Matches(index, row, filters, usableSet) then
      list[#list + 1] = row
    end
  end
  return list
end

-- Rows for suggestion entries, in order, unique, among `rows`, passing the filters and at most `max`. An entry
-- is a texture or { query = text }, which adds the search results for that text.
function Catalog.SuggestedRows(data, rows, entries, filters, usableSet, max, synonyms)
  local index, present = data.index, {}
  for _, row in ipairs(rows) do
    present[row] = true
  end
  local list, seen = {}, {}
  local function add(row)
    if row and present[row] and not seen[row] and Catalog.Matches(index, row, filters, usableSet) then
      seen[row] = true
      list[#list + 1] = row
    end
    return max and #list >= max
  end
  for _, entry in ipairs(entries or {}) do
    if type(entry) == "table" then
      if entry.query and #ns.Search.Tokens(entry.query) > 0 then
        for _, row in ipairs((ns.Search.Find(index, rows, entry.query, { synonyms = synonyms }))) do
          if add(row) then
            return list
          end
        end
      end
    elseif add(index.byKey[Catalog.ResolveId(data, entry) or entry]) then
      return list
    end
  end
  return list
end

local MACRO_COMMANDS = { cast = "one", use = "one", castsequence = "list", castrandom = "list", userandom = "list" }

-- Spells and items a macro casts or uses, in order and unique: { name = text } or { slot = inventorySlot }.
function Catalog.MacroTerms(body)
  local terms, seen = {}, {}
  local function add(text, command)
    text = text:gsub("^%s*!?%s*", ""):gsub("%s+$", "")
    local slot = command == "use" and tonumber(text)
    local key = slot and ("slot:" .. slot) or text:lower()
    if text == "" or seen[key] or (not slot and text:match("^[%d%s]+$")) then
      return
    end
    seen[key] = true
    terms[#terms + 1] = slot and { slot = slot } or { name = text }
  end
  for line in (body or ""):gmatch("[^\r\n]+") do
    local command, args = line:match("^%s*/(%a+)%s*(.*)$")
    command = command and command:lower()
    if not command then
      args = line:match("^%s*#showtooltip%s+(.+)$")
      command = args and "cast"
    end
    local kind = MACRO_COMMANDS[command]
    if kind then
      for clause in (args .. ";"):gmatch("([^;]*);") do
        clause = clause:gsub("%b[]", "")
        if kind == "list" then
          clause = clause:gsub("reset=%S+", "")
          for part in (clause .. ","):gmatch("([^,]*),") do
            add(part, command)
          end
        else
          add(clause, command)
        end
      end
    end
  end
  return terms
end

-- Name of a names-column entry: a reference the game resolves in the player's language ("s133" spell, "i6948" item,
-- "c1792" currency) or the name itself. Second result: true while the game is still loading it.
function Catalog.NameOf(entry)
  local kind, id = entry:match("^([sic])(%d+)$")
  id = tonumber(id)
  if not kind then
    return entry
  elseif kind == "s" then
    if C_Spell and C_Spell.GetSpellName then
      local name = C_Spell.GetSpellName(id)
      if not name and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(id)
        return nil, true
      end
      return name
    end
    return GetSpellInfo and (GetSpellInfo(id))
  elseif kind == "i" then
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(id)
      return nil, true
    end
    return name
  end
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
  return info and info.name
end

-- Display names of a row as a list, and true when some are still loading.
function Catalog.Names(index, row)
  local names = index.refs[row]
  local list, pending = {}, false
  if names then
    for entry in names:gmatch("[^|]+") do
      local name, loading = Catalog.NameOf(entry)
      if name and name ~= "" then
        list[#list + 1] = name
      end
      pending = pending or loading or false
    end
  end
  return list, pending
end
