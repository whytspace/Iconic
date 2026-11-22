local ADDON_NAME, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local L = ns.L
local find, floor = string.find, math.floor

-- Source letters as written by scripts/build_data.py, in display order.
Catalog.SOURCES = {
  { key = "S", label = "Spells" },
  { key = "I", label = "Items" },
  { key = "M", label = "Mounts" },
  { key = "P", label = "Pets" },
  { key = "A", label = "Achievements" },
  { key = "C", label = "Currencies" },
}

Catalog.GROUPS = {
  { key = "none", label = "None" },
  { key = "source", label = "Source" },
  { key = "class", label = "Class" },
  { key = "category", label = "Item category" },
  { key = "profession", label = "Profession" },
}

local function split(line, sep)
  local fields, start = {}, 1
  while true do
    local i = find(line, sep, start, true)
    if not i then
      fields[#fields + 1] = string.sub(line, start)
      return fields
    end
    fields[#fields + 1] = string.sub(line, start, i - 1)
    start = i + 1
  end
end

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

local function padded(list)
  return (list and list ~= "") and (" " .. list .. " ") or nil
end

-- Column store, one row per icon. Columns: key (file ID or texture path), id, texture, file, names
-- (display, "a|b"), text (padded search text), src, cls, cats (" 2:7 4:1 "), profs (" 185 "), spells.
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
  }
end

local function addRow(index, key, id, texture, file, names, text, src, cls, cats, profs, spells)
  local row = index.count + 1
  index.count = row
  index.byKey[key] = row
  index.key[row] = key
  index.id[row] = id
  index.texture[row] = texture
  index.file[row] = file
  index.names[row] = names
  index.text[row] = text
  index.src[row] = src or ""
  index.cls[row] = cls or 0
  index.cats[row] = cats
  index.profs[row] = profs
  index.spells[row] = spells
  return row
end

-- Parses the table a data add-on leaves in the global IconicData into lookups and an index.
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
  local index, PadText = data.index, ns.Search.PadText
  for line in (raw.icons or ""):gmatch("[^\n]+") do
    local f = split(line, "\t")
    local id = tonumber(f[1])
    if id then
      local names = f[3] ~= "" and f[3] or nil
      local text = (f[4] and f[4] ~= "") and PadText(f[4]) or PadText(ns.Search.FileText(f[2]))
      addRow(index, id, id, id, f[2], names, text, f[5], tonumber(f[6]), padded(f[7]), padded(f[8]), padded(f[9]))
      data.byFile[f[2]] = id
    end
  end
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
      row = addRow(index, key, id, texture, file, nil, ns.Search.PadText(ns.Search.FileText(file)))
    end
    if not seen[row] then
      seen[row] = position
      rows[#rows + 1] = row
    end
  end
  return rows, data, seen
end

function Catalog.HasClass(mask, classId)
  return floor(mask / 2 ^ (classId - 1)) % 2 == 1
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

-- filters: { source = {S=true}, class = {[8]=true}, category = {[2]=true, ["2:7"]=true},
-- profession = {[164]=true}, usable = true }; usableSet: key -> true.
function Catalog.Matches(index, row, filters, usableSet)
  if not filters then
    return true
  end
  if filters.usable and not (usableSet and usableSet[index.key[row]]) then
    return false
  end
  if next(filters.source or {}) then
    local ok, src = false, index.src[row]
    for key in pairs(filters.source) do
      if find(src, key, 1, true) then
        ok = true
        break
      end
    end
    if not ok then
      return false
    end
  end
  if next(filters.class or {}) then
    local ok, mask = false, index.cls[row]
    for classId in pairs(filters.class) do
      if Catalog.HasClass(mask, classId) then
        ok = true
        break
      end
    end
    if not ok then
      return false
    end
  end
  if next(filters.category or {}) then
    local ok, cats = false, index.cats[row]
    if cats then
      for key in pairs(filters.category) do
        local needle = type(key) == "number" and (" " .. key .. ":") or (" " .. key .. " ")
        if find(cats, needle, 1, true) then
          ok = true
          break
        end
      end
    end
    if not ok then
      return false
    end
  end
  if next(filters.profession or {}) then
    local ok, profs = false, index.profs[row]
    if profs then
      for prof in pairs(filters.profession) do
        if find(profs, " " .. prof .. " ", 1, true) then
          ok = true
          break
        end
      end
    end
    if not ok then
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
  local counts = { source = {}, class = {}, category = {}, profession = {} }
  local function add(dim, value)
    counts[dim][value] = (counts[dim][value] or 0) + 1
  end
  for _, row in ipairs(rows) do
    for letter in index.src[row]:gmatch(".") do
      add("source", letter)
    end
    for _, classId in ipairs(classIds(index.cls[row])) do
      add("class", classId)
    end
    local tops = {}
    for key, top in (index.cats[row] or ""):gmatch("((%d+):%d+)") do
      add("category", key)
      tops[tonumber(top)] = true
    end
    for top in pairs(tops) do
      add("category", top)
    end
    for prof in (index.profs[row] or ""):gmatch("%d+") do
      add("profession", tonumber(prof))
    end
  end
  return counts
end

function Catalog.ActiveFilterCount(filters)
  local count = filters and filters.usable and 1 or 0
  for _, dim in ipairs({ "source", "class", "category", "profession" }) do
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
      if find(src, source.key, 1, true) then
        values[#values + 1] = source.key
      end
    end
  elseif groupBy == "class" then
    values = classIds(index.cls[row])
  elseif groupBy == "category" then
    local seen = {}
    for top in (index.cats[row] or ""):gmatch(" (%d+):") do
      top = tonumber(top)
      if not seen[top] then
        seen[top] = true
        values[#values + 1] = top
      end
    end
  elseif groupBy == "profession" then
    for prof in (index.profs[row] or ""):gmatch("%d+") do
      values[#values + 1] = tonumber(prof)
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
  end
  return tostring(value)
end

local SOURCE_RANK = {}
for i, source in ipairs(Catalog.SOURCES) do
  SOURCE_RANK[source.key] = i
end

local function groupOrder(data, groupBy, a, b)
  if groupBy == "source" then
    return (SOURCE_RANK[a] or 99) < (SOURCE_RANK[b] or 99)
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
    sections[#sections + 1] = { title = Catalog.GroupLabel(data, groupBy, value), rows = byValue[value], value = value }
  end
  if #other > 0 then
    sections[#sections + 1] = { title = L["Other"], rows = other }
  end
  return sections
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
