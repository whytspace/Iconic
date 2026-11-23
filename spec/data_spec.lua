local addon = require("spec.helpers.addon")

-- Whether a row's names column holds one of the references (names are looked up in the game by reference).
local function hasRef(index, row, refs)
  for entry in (index.refs[row] or ""):gmatch("[^|]+") do
    for _, ref in ipairs(refs) do
      if entry == ref then
        return true
      end
    end
  end
end

-- Runs the shipped data files through the real search, guarding the build script and the parser together.
for _, file in ipairs({ "Forever.lua", "Retail.lua" }) do
  describe("data " .. file, function()
    local ns, data, rows, opts

    setup(function()
      ns = addon.load()
      data = ns.Catalog.Parse(addon.rawData(file))
      local textures = {}
      for row = 1, data.index.count do
        textures[row] = data.index.key[row]
      end
      rows = ns.Catalog.Rows(data, textures)
      opts = { synonyms = ns.Search.BuildSynonyms(ns.SYNONYMS) }
    end)

    it("finds icons by German and English words with the German data", function()
      local german = ns.Catalog.Parse(addon.rawData(file))
      ns.Catalog.ApplyLocale(german, addon.rawData(file:gsub("%.lua$", "_deDE.lua"), "IconicDataLocale"))
      local textures = {}
      for row = 1, german.index.count do
        textures[row] = german.index.key[row]
      end
      local germanRows = ns.Catalog.Rows(german, textures)
      assert.are.equal("Jäger", german.classes[3])
      -- Names come from the game in its language; the German and English search words find the same icons.
      local top = {}
      for _, query in ipairs({ "pyroschlag", "pyroblast" }) do
        top[query] = {}
        for i, row in ipairs(ns.Search.Find(german.index, germanRows, query, opts)) do
          if i > 3 then
            break
          end
          top[query][german.index.key[row]] = true
        end
      end
      local shared
      for key in pairs(top.pyroschlag) do
        shared = shared or top.pyroblast[key]
      end
      assert.is_true(shared, "no icon in the top 3 for both pyroschlag and pyroblast")
    end)

    it("finds icons by their picture tags", function()
      -- 538517 (spell_druid_tirelesspursuit) shows a werewolf; only its tags say so.
      local found
      for i, row in ipairs(ns.Search.Find(data.index, rows, "werewolf", opts)) do
        found = found or (i <= 3 and data.index.key[row] == 538517)
      end
      assert.is_true(found, "538517 not in the top 3 for 'werewolf'")
    end)

    it("has icons and lookups", function()
      assert.is_true(#rows > 25000)
      assert.are.equal("Hunter", data.classes[3])
      assert.are.equal("Cooking", data.professions[185])
    end)

    it("ranks Hunter's Mark in the top 3 for 'target'", function()
      local results = ns.Search.Find(data.index, rows, "target", opts)
      local rank
      for i = 1, math.min(3, #results) do
        if hasRef(data.index, results[i], { "s1130", "s257284" }) then
          rank = rank or i
        end
      end
      assert.is_not_nil(rank, "Hunter's Mark not in the top 3 for 'target'")
    end)

    it("finds every icon of an item category by its name", function()
      local shield, missing = 4 * 256 + 6, 0
      local found = {}
      for _, row in ipairs((ns.Search.Find(data.index, rows, "shield", opts))) do
        found[row] = true
      end
      for row = 1, data.index.count do
        for _, number in ipairs(data.index.cats[row] or {}) do
          if number == shield and not found[row] then
            missing = missing + 1
          end
        end
      end
      assert.are.equal(0, missing)
    end)

    it("lists only playable classes", function()
      for classId in pairs(data.classes) do
        assert.is_true(classId <= 13, "unexpected class " .. classId .. " " .. data.classes[classId])
      end
      for row = 1, data.index.count do
        assert.is_true(data.index.cls[row] < 2 ^ 13, "class bit above Evoker on " .. tostring(data.index.key[row]))
      end
    end)

    it("ranks icons with much of a chip's colour first", function()
      local green = ns.Search.PickTarget(0x4c / 255, 0xbb / 255, 0x44 / 255)
      local results = ns.Search.Find(data.index, rows, "", { chips = { { target = green } } })
      assert.is_true(#results > 100)
      for i = 1, 10 do
        assert.is_true(ns.Search.ColorShare(data.index, results[i], "green") >= 40)
      end
    end)

    it("tags hunter spells with the hunter class", function()
      local row = data.index.byKey[data.byFile["ability_hunter_snipershot"]]
      assert.is_true(ns.Catalog.HasClass(data.index.cls[row], 3))
    end)

    it("tokenizes file names like the build script", function()
      local index = data.index
      local checked = 0
      for row = 1, index.count, 31 do
        local field = " " .. select(5, index.text[row]:match("^ (.-) | (.-) | (.-) | (.-) | (.-) |")) .. " "
        for token in ns.Search.FileText(index.file[row]):gsub("|", ""):gmatch("%S+") do
          assert.is_truthy(
            field:find(" " .. token .. " ", 1, true),
            index.file[row] .. " -> " .. token .. " in" .. field
          )
        end
        checked = checked + 1
      end
      assert.is_true(checked > 500)
    end)

    it("stores names as game references or text", function()
      local index, refs = data.index, 0
      for row = 1, index.count do
        for entry in (index.refs[row] or ""):gmatch("[^|]+") do
          refs = refs + (entry:match("^[sic]%d+$") and 1 or 0)
        end
      end
      assert.is_true(refs > 10000)
    end)
  end)
end
