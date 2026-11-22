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

-- Returns (ns, env). `globals` seeds the fake WoW globals.
function M.load(globals)
  local ns = {}
  local env = setmetatable({}, { __index = _G })
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

-- Runs a data add-on file and returns the IconicData table it defines.
function M.rawData(file)
  local env = {}
  local chunk = assert(loadfile(root .. "/Iconic_Data/" .. file))
  setfenv(chunk, env)
  chunk()
  return env.IconicData
end

-- Search field as scripts/build_data.py writes it: name buckets (1st, 2nd, 3rd-4th, rest), file, description.
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
  fields[5] = Search.FileText(file):gsub("|", "")
  fields[6] = table.concat(Search.Tokens(desc or ""), " ")
  return table.concat(fields, "|")
end

-- Builds a tiny IconicData table. Rows: { id, file, names = {...}, desc, src, cls, cats, profs, spells }.
function M.fakeData(ns, rows)
  local lines = {}
  for _, r in ipairs(rows) do
    local names = r.names or {}
    lines[#lines + 1] = table.concat({
      r[1],
      r[2],
      table.concat(names, "|"),
      searchField(ns.Search, names, r[2], r.desc),
      r.src or "",
      r.cls or "",
      r.cats or "",
      r.profs or "",
      r.spells or "",
    }, "\t")
  end
  return {
    flavor = "test",
    build = "0",
    classes = "3\tHunter\n8\tMage\n",
    itemClasses = "0\tConsumable\n2\tWeapon\n2:7\tOne-Handed Swords\n4\tArmor\n",
    professions = "185\tCooking\n",
    icons = table.concat(lines, "\n") .. "\n",
  }
end

return M
