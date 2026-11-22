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
  { key = "A", bit = 16, label = "Achievements" },
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
-- profs (profession IDs), spells (spell IDs); list columns are nil when empty. colors: colour -> row -> share.
function Catalog.NewIndex()
  return {
    count = 0,
    byKey = {},
    key = {},
    id = {},
    texture = {},
    file = {},
    names = {},
    text = {},
    src = {},
    cls = {},
    cats = {},
    profs = {},
    spells = {},
    colors = {},
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

local COLUMNS = { "file", "names", "text", "src", "cls", "cats", "profs", "spells" }

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
  index.colors = icons.colors or {}
  index.hasColors = next(index.colors) ~= nil
  local key, texture, byKey, byFile, file = index.key, index.texture, index.byKey, data.byFile, index.file
  for row = 1, #ids do
    local id = ids[row]
    key[row], texture[row], byKey[id] = id, id, row
    byFile[file[row]] = id
  end
  index.count = #ids
  return data
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

-- Per filter group: does a row match one of the selected values?
local DIMENSION_MATCHERS = {
  source = function(index, row, selected)
    local src = index.src[row]
    for key in pairs(selected) do
      if hasBit(src, SOURCE_BITS[key]) then
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
  color = function(index, row, selected)
    for color in pairs(selected) do
      if ns.Search.ColorShare(index, row, color) >= ns.Search.COLOR_MIN then
        return true
      end
    end
    return false
  end,
}
Catalog.DIMENSIONS = { "source", "class", "category", "profession", "color" }

-- filters: { source = {S=true}, class = {[8]=true}, category = {[2]=true, ["2:7"]=true},
-- profession = {[164]=true}, color = {green=true}, usable = true }; usableSet: key -> true.
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
  local function add(dim, value)
    counts[dim][value] = (counts[dim][value] or 0) + 1
  end
  for _, row in ipairs(rows) do
    local src = index.src[row]
    for _, source in ipairs(Catalog.SOURCES) do
      if hasBit(src, source.bit) then
        add("source", source.key)
      end
    end
    for _, classId in ipairs(classIds(index.cls[row])) do
      add("class", classId)
    end
    local tops = {}
    for _, number in ipairs(index.cats[row] or NONE) do
      add("category", CATEGORY_KEYS[number])
      tops[floor(number / 256)] = true
    end
    for top in pairs(tops) do
      add("category", top)
    end
    for _, prof in ipairs(index.profs[row] or NONE) do
      add("profession", prof)
    end
    for _, color in ipairs(Catalog.GroupValues(index, row, "color")) do
      add("color", color)
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
  local counts = { source = {}, class = {}, category = {}, profession = {}, color = {} }
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
  for _, dim in ipairs({ "source", "class", "category", "profession", "color" }) do
    for _ in pairs(filters and filters[dim] or {}) do
      count = count + 1
    end
  end
  return count
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
    for _, color in ipairs(ns.Search.COLORS) do
      if ns.Search.ColorShare(index, row, color.key) >= ns.Search.COLOR_MIN then
        values[#values + 1] = color.key
      end
    end
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
function Catalog.Sections(data, rows, groupBy, recentRows)
  local index = data.index
  local sections = {}
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
      -- Strongest share first; equal shares keep the incoming order.
      local position, shares = {}, index.colors[value] or NONE
      for i, row in ipairs(list) do
        position[row] = i
      end
      table.sort(list, function(a, b)
        local sa, sb = shares[a] or 0, shares[b] or 0
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
  for _, color in ipairs(ns.Search.COLORS) do
    add("color", color.key, L[color.label], L["Color"], color.hints)
  end
  return list
end

-- Filter values a query's words point at, best first: { dim, value, label, group, word, count }. A word
-- matches when it equals or starts a word of the value's label; only values with icons and not yet
-- active are offered. `word` is the query word to drop when the suggestion is taken.
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
    local count = counts and counts[candidate.dim] and counts[candidate.dim][candidate.value] or 0
    local active = filters and filters[candidate.dim] and filters[candidate.dim][candidate.value]
    if count > 0 and not active then
      local best, bestWord
      local labelWords = Search.Tokens(candidate.label)
      for _, hint in ipairs(candidate.hints or {}) do
        labelWords[#labelWords + 1] = Search.Stem(hint)
      end
      for _, labelWord in ipairs(labelWords) do
        for _, word in ipairs(words) do
          local stem = Search.Stem(word)
          local score = (labelWord == stem and 3) or (labelWord:sub(1, #stem) == stem and 2) or nil
          if score and (not best or score > best) then
            best, bestWord = score, word
          end
        end
      end
      if best then
        candidate.score, candidate.word, candidate.count = best, bestWord, count
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

-- Display names of a row as a list.
function Catalog.Names(index, row)
  local names = index.names[row]
  local list = {}
  if names then
    for name in names:gmatch("[^|]+") do
      list[#list + 1] = name
    end
  end
  return list
end
