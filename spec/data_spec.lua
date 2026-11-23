local addon = require("spec.helpers.addon")

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

    it("finds icons by German and English names with the German data", function()
      local german = ns.Catalog.Parse(addon.rawData(file))
      ns.Catalog.ApplyLocale(german, addon.rawData(file:gsub("%.lua$", "_deDE.lua"), "IconicDataLocale"))
      local textures = {}
      for row = 1, german.index.count do
        textures[row] = german.index.key[row]
      end
      local germanRows = ns.Catalog.Rows(german, textures)
      assert.are.equal("Jäger", german.classes[3])
      for _, query in ipairs({ "pyroschlag", "pyroblast" }) do
        local found
        for i, row in ipairs(ns.Search.Find(german.index, germanRows, query, opts)) do
          if i > 3 then
            break
          end
          for _, name in ipairs(ns.Catalog.Names(german.index, row)) do
            found = found or name == "Pyroschlag"
          end
        end
        assert.is_true(found, "Pyroschlag not in the top 3 for " .. query)
      end
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
        for _, name in ipairs(ns.Catalog.Names(data.index, results[i])) do
          if name == "Hunter's Mark" then
            rank = rank or i
          end
        end
      end
      assert.is_not_nil(rank, "Hunter's Mark not in the top 3 for 'target'")
    end)

    it("lists only playable classes", function()
      for classId in pairs(data.classes) do
        assert.is_true(classId <= 13, "unexpected class " .. classId .. " " .. data.classes[classId])
      end
      for row = 1, data.index.count do
        assert.is_true(data.index.cls[row] < 2 ^ 13, "class bit above Evoker on " .. tostring(data.index.key[row]))
      end
    end)

    it("ranks icons by colour share for a named colour chip", function()
      local results = ns.Search.Find(data.index, rows, "", { chips = { { key = "green" } } })
      assert.is_true(#results > 100)
      for i = 1, 10 do
        assert.is_true(ns.Search.ColorShare(data.index, results[i], "green") >= 50)
      end
    end)

    it("tags hunter spells with the hunter class", function()
      local row = data.index.byKey[data.byFile["ability_hunter_snipershot"]]
      assert.is_true(ns.Catalog.HasClass(data.index.cls[row], 3))
    end)

    it("tokenizes names like the build script", function()
      local index = data.index
      local checked = 0
      for row = 1, index.count, 31 do
        local first = ns.Catalog.Names(index, row)[1]
        if first then
          local field = " " .. index.text[row]:match("^ ([^|]*) |") .. " "
          for _, token in ipairs(ns.Search.Tokens(first)) do
            assert.is_truthy(field:find(" " .. token .. " ", 1, true), first .. " -> " .. token .. " in" .. field)
          end
          checked = checked + 1
        end
      end
      assert.is_true(checked > 50)
    end)
  end)
end
