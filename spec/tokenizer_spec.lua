local addon = require("spec.helpers.addon")

-- Search.lua and scripts/build_data.py tokenize the same way: the data's words must meet the typed ones.
describe("Tokenizer in Search.lua and build_data.py", function()
  local Search = addon.load().Search

  local TEXTS = {
    "Hunter's Mark",
    "Jäger’s Blade of the Ancients",
    "Marked for Death",
    "Healing Potions and Elixirs",
    "Straße ẞ Æther Þorn Ñandú Øre",
    "boxes classes wishes axes glasses",
    "ring rings running cried studied flies dies",
    "12 bags, 3 keys & 40 coins",
    "Ëmerald Çrown",
  }
  local FILES = {
    "inv_misc_gem_emerald_01",
    "Ability_Hunter_SniperShot",
    "spell_holy_SoothingMists",
    "INV_Sword_04",
    "achievement_boss_ragnaros",
  }

  -- Runs build_data.py's tokenizer on `lines` (one input per line); returns its output lines.
  local function python(code, lines)
    local input = os.tmpname()
    local file = assert(io.open(input, "w"))
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    local script = os.tmpname()
    file = assert(io.open(script, "w"))
    file:write(
      "import sys\nsys.path.insert(0, sys.argv[1])\nimport build_data as b\n",
      "for line in open(sys.argv[2], encoding='utf-8').read().splitlines():\n",
      "    print(",
      code,
      ")\n"
    )
    file:close()
    local pipe = assert(io.popen(("python3 -I '%s' '%s' '%s'"):format(script, addon.root .. "/scripts", input)))
    local out = {}
    for line in pipe:lines() do
      out[#out + 1] = line
    end
    pipe:close()
    os.remove(input)
    os.remove(script)
    assert.are.equal(#lines, #out, "python3 gave no output for " .. code)
    return out
  end

  it("normalizes, drops stopwords and stems the same", function()
    local expected = python("' '.join(b.tokens(line))", TEXTS)
    for i, text in ipairs(TEXTS) do
      assert.are.equal(expected[i], table.concat(Search.Tokens(text), " "), text)
    end
  end)

  it("folds every accented Latin letter the same", function()
    local letters = { "\225\186\158" }
    for code = 0xC0, 0xFF do
      if code ~= 0xD7 and code ~= 0xF7 then
        letters[#letters + 1] = string.char(0xC3, code - 64)
      end
    end
    local expected = python("b.normalize(line)", letters)
    for i, letter in ipairs(letters) do
      assert.are.equal(expected[i], Search.Normalize(letter), letter)
    end
  end)

  it("splits file names the same", function()
    local expected = python("'||||' + ' '.join(dict.fromkeys(b.file_tokens(line))) + '|'", FILES)
    for i, file in ipairs(FILES) do
      assert.are.equal(expected[i], Search.FileText(file), file)
    end
  end)

  it("has the same stopwords", function()
    local source = assert(io.open(addon.root .. "/Search.lua")):read("*a")
    local block = assert(source:match("local STOPWORDS = {}.-%(%[%[(.-)%]%]%)"))
    local lua = {}
    for word in block:gmatch("%S+") do
      lua[#lua + 1] = word
    end
    table.sort(lua)
    local expected = python("' '.join(sorted(b.STOPWORDS))", { "" })
    assert.are.equal(expected[1], table.concat(lua, " "))
  end)
end)
