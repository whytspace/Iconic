-- Loads the add-on's non-UI files under plain Lua 5.1, with the same ("Iconic", ns) varargs WoW passes.

local M = {}

local helpersDir = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/[^/]*$")
local root = helpersDir:gsub("/spec/helpers$", "")
M.root = root

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/Iconic.toc") do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") and not line:match("^UI/") then
      files[#files + 1] = line
    end
  end
  return files
end

-- File IDs by lowercase "interface\icons\name" path of the icons in the latest fakeData.
local fileIds = {}

-- Returns (ns, env). `globals` seeds the fake WoW globals.
function M.load(globals)
  local ns = {}
  local env = setmetatable({}, { __index = _G })
  env.GetFileIDFromPath = function(path)
    return fileIds[path:lower()]
  end
  for name, value in pairs(globals or {}) do
    env[name] = value
  end
  for _, file in ipairs(tocFiles()) do
    local chunk = assert(loadfile(root .. "/" .. file))
    setfenv(chunk, env)
    chunk("Iconic", ns)
  end
  return ns, env
end

-- Runs a data add-on file and returns the table it defines in `global` (default IconicData).
function M.rawData(file, global)
  local env = {}
  local chunk = assert(loadfile(root .. "/Iconic_Data/" .. file))
  setfenv(chunk, env)
  chunk()
  return env[global or "IconicData"]
end

-- Search field as scripts/build_data.py writes it: name buckets (1st, 2nd, 3rd-4th, rest), file and tags, description.
local function searchField(Search, names, file, desc)
  local buckets = { { names[1] }, { names[2] }, { names[3], names[4] }, {} }
  for i = 5, #names do
    table.insert(buckets[4], names[i])
  end
  local fields, seen = {}, {}
  for i, bucket in ipairs(buckets) do
    local list = {}
    for _, token in ipairs(Search.Tokens(table.concat(bucket, " "))) do
      if not seen[token] then
        seen[token] = true
        list[#list + 1] = token
      end
    end
    fields[i] = table.concat(list, " ")
  end
  fields[5] = Search.FileText(file):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
  fields[6] = table.concat(Search.Tokens(desc or ""), " ")
  return table.concat(fields, "|")
end

local SOURCE_BITS = { S = 1, I = 2, M = 4, P = 8, A = 16, C = 32 }

-- Space-separated values into a list, or nil when there are none, as list columns hold them.
local function list(text, convert)
  local values = {}
  for value in (text or ""):gmatch("%S+") do
    values[#values + 1] = convert(value)
  end
  return #values > 0 and values or nil
end

local function category(key)
  local class, subclass = key:match("^(%d+):(%d+)$")
  return tonumber(class) * 256 + tonumber(subclass)
end

-- OKLab (x100) of each color's first reference shade in scripts/build_colors.py, for fake dominant colors.
local COLOR_LAB = {
  red = { 55, 18, 9 },
  orange = { 69, 9, 13 },
  yellow = { 86, -3, 16 },
  green = { 65, -15, 11 },
  teal = { 65, -11, -2 },
  blue = { 52, -2, -19 },
  purple = { 52, 11, -17 },
  pink = { 73, 16, -4 },
  brown = { 44, 4, 6 },
  black = { 18, 0, 0 },
  white = { 94, 0, 1 },
  gray = { 76, 0, 0 },
}
M.COLOR_LAB = COLOR_LAB

-- Builds a tiny IconicData table in the column format of scripts/build_data.py. Rows: { id, file,
-- names = {...}, desc, tags = "wolf beast", src = "IS", cls = "4", cats = "2:7 4:1", profs = "185", spells = "1130",
-- colors = "green:62 red:18 35/-9/7:20" }; each color becomes a dominant color with that weight, at a named
-- reference shade or at the given OKLab (x100).
function M.fakeData(ns, rows)
  fileIds = {}
  local icons = { id = {}, refs = {}, text = {}, tags = {}, src = {}, cls = {}, cats = {}, profs = {}, spells = {} }
  local colors = {}
  for _, r in ipairs(rows) do
    if r.colors then
      for k = 1, 4 do
        for _, field in ipairs({ "l", "a", "b", "w" }) do
          colors[field .. k] = {}
        end
      end
    end
  end
  for row, r in ipairs(rows) do
    local names = r.names or {}
    icons.id[row] = tonumber(r[1])
    fileIds["interface\\icons\\" .. r[2]:lower()] = icons.id[row]
    icons.refs[row] = #names > 0 and table.concat(names, "|") or nil
    icons.text[row] = ns.Search.PadText(searchField(ns.Search, names, r[2], r.desc))
    icons.tags[row] = r.tags
    local src = 0
    for letter in (r.src or ""):gmatch(".") do
      src = src + SOURCE_BITS[letter]
    end
    icons.src[row] = src
    icons.cls[row] = tonumber(r.cls) or 0
    icons.cats[row] = list(r.cats, category)
    icons.profs[row] = list(r.profs, tonumber)
    icons.spells[row] = list(r.spells, tonumber)
    if next(colors) then
      for k = 1, 4 do
        colors["l" .. k][row], colors["a" .. k][row], colors["b" .. k][row], colors["w" .. k][row] = 0, 0, 0, 0
      end
    end
    local k = 0
    for token in (r.colors or ""):gmatch("%S+") do
      k = k + 1
      local color, share = token:match("^(%a+):(%d+)$")
      local lab = COLOR_LAB[color]
      if not lab then
        local l, a, b
        l, a, b, share = token:match("^(%-?%d+)/(%-?%d+)/(%-?%d+):(%d+)$")
        lab = { tonumber(l), tonumber(a), tonumber(b) }
      end
      colors["l" .. k][row], colors["a" .. k][row], colors["b" .. k][row] = lab[1], lab[2], lab[3]
      colors["w" .. k][row] = tonumber(share)
    end
  end
  icons.colors = colors
  return {
    flavor = "test",
    build = "0",
    classes = "3\tHunter\n8\tMage\n",
    itemClasses = "0\tConsumable\n2\tWeapon\n2:7\tOne-Handed Swords\n4\tArmor\n4:6\tShields\n",
    professions = "185\tCooking\n",
    icons = icons,
  }
end

return M
