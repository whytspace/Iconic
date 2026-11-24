local addon = require("spec.helpers.addon")

describe("Search", function()
  local ns, Search, Catalog, data, rows, synonyms

  local function keys(results, n)
    local list = {}
    for i = 1, math.min(n or #results, #results) do
      list[i] = data.index.key[results[i]]
    end
    return list
  end

  local function find(query, opts)
    opts = opts or {}
    opts.synonyms = synonyms
    return Search.Find(data.index, rows, query, opts)
  end

  it("splits camel-case words in file names", function()
    local text = addon.load().Search.FileText("Ability_Monk_SoothingMists")
    assert.equals("||||monk sooth mist|", text)
  end)

  before_each(function()
    ns = addon.load()
    Search, Catalog = ns.Search, ns.Catalog
    data = Catalog.Parse(addon.fakeData(ns, {
      {
        "132212",
        "ability_hunter_snipershot",
        names = { "Hunter's Mark", "Sniper Shot" },
        desc = "places hunters mark target increasing ranged attack power",
        src = "S",
        cls = "4",
        spells = "1130",
      },
      { "236188", "ability_hunter_markedfordeath", names = { "Marked for Death" }, src = "S", cls = "4" },
      { "135274", "inv_sword_04", names = { "Worn Shortsword", "Shadow Sword" }, src = "I", cats = "2:7" },
      { "132690", "inv_misc_bone_skull_01", names = { "Skull of Impending Doom" }, src = "I", cats = "15:0" },
      { "1001", "inv_shirt_white_01", names = { "White Linen Shirt" }, src = "I", cats = "4:0" },
      { "1002", "inv_misc_cape_01", names = { "Tattered Cape" }, src = "I" },
      { "133971", "inv_misc_food_15", names = { "Prowler Steak", "Roasted Quail" }, src = "IS", cats = "0:5" },
    }))
    rows = Catalog.Rows(data, { 132212, 236188, 135274, 132690, 1001, 1002, 133971 })
    synonyms = Search.BuildSynonyms(ns.SYNONYMS)
  end)

  it("normalizes apostrophes, case and punctuation", function()
    assert.are.equal("hunters mark", Search.Normalize("Hunter's  MARK!"))
  end)

  it("uses the client language's texts and colour words", function()
    local german = addon.load({
      GetLocale = function()
        return "deDE"
      end,
    })
    assert.are.equal("Rot", german.L["Red"])
    assert.are.equal("Gruppieren: %s", german.L["Group by: %s"])
    assert.is_truthy(table.concat(german.Search.Preset("gold").hints, " "):find("goldene", 1, true))
    assert.are.equal("Red", ns.L["Red"])
  end)

  it("folds accented letters to their base letters", function()
    assert.are.equal("jager der weisse strasse", Search.Normalize("Jäger der Weiße STRAẞE"))
    assert.are.equal("aou aou ae cafe", Search.Normalize("ÄÖÜ äöü Æ Café"))
  end)

  it("stems common suffixes to one form", function()
    assert.are.equal("mark", Search.Stem("marks"))
    assert.are.equal("mark", Search.Stem("marked"))
    assert.are.equal("mark", Search.Stem("marking"))
    assert.are.equal("boss", Search.Stem("boss"))
  end)

  it("finds a spell by a word that is only in its description", function()
    assert.are.same({ 132212 }, keys((find("target")), 1))
  end)

  it("ranks a name hit above a description-only hit", function()
    assert.are.same({ 132212, 236188 }, keys((find("mark")), 2))
  end)

  it("finds icons through synonyms", function()
    assert.are.same({ 1002 }, keys((find("cloak"))))
  end)

  it("matches synonyms as whole words only", function()
    assert.are.same({}, keys((find("helmet"))))
    assert.are.same({}, Search.Explain(data.index, 6, "helmet", { synonyms = synonyms }))
    assert.are.equal("Tattered Cape", Search.Highlight("Tattered Cape", "helmet", { synonyms = synonyms }))
  end)

  it("matches word prefixes while typing", function()
    assert.are.same({ 135274 }, keys((find("shorts"))))
  end)

  it("requires every word in strict mode", function()
    local results, loose = find("shadow sword")
    assert.is_false(loose)
    assert.are.same({ 135274 }, keys(results))
  end)

  it("falls back to close matches for typos", function()
    local results, loose = find("skuul", {
      vocabulary = function()
        return Search.Vocabulary(data.index.text)
      end,
    })
    assert.is_true(loose)
    assert.are.same({ 132690 }, keys(results, 1))
  end)

  it("finds an icon by its file ID", function()
    assert.are.same({ 135274 }, keys((find("135274")), 1))
  end)

  it("boosts icons the player can use", function()
    local _, _, plain = find("sword")
    local _, _, boosted = find("sword", { usable = { [135274] = true } })
    local row = data.index.byKey[135274]
    assert.is_true(boosted[row] > plain[row])
  end)

  it("returns nothing for an unknown word without typo data", function()
    assert.are.same({}, keys((find("zzzz"))))
  end)

  describe("item categories", function()
    before_each(function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "inv_shield_01", names = { "Ward of the Violet Citadel" }, src = "I", cats = "4:6" },
        { "2", "inv_shield_02", names = { "Kite Shield" }, src = "I", cats = "4:6" },
        { "3", "spell_holy_powerwordshield", names = { "Power Word: Shield" }, src = "S" },
        { "4", "inv_misc_cape_01", names = { "Tattered Cloak" }, src = "I", cats = "4:0" },
      }))
      rows = Catalog.Rows(data, { 1, 2, 3, 4 })
    end)

    it("finds icons by their item category's name, below icons named so", function()
      assert.are.same({ 2, 3, 1 }, keys((find("shield"))))
    end)

    it("finds icons by their parent category's name", function()
      assert.are.same({ 1, 2, 4 }, keys((find("armor"))))
    end)
  end)

  describe("colours", function()
    local function chip(name, weight)
      return { target = addon.COLOR_LAB[name], weight = weight }
    end

    local function chips(...)
      return { chips = { ... } }
    end

    before_each(function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "inv_misc_gem_emerald_01", names = { "Emerald" }, colors = "green:70 teal:12" },
        { "2", "inv_misc_herb_01", names = { "Dark Herb" }, colors = "35/-9/7:60" },
        { "3", "inv_misc_herb_02", names = { "Light Herb" }, colors = "85/-14/12:50" },
        { "4", "inv_misc_gem_ruby_01", names = { "Ruby" }, colors = "red:65" },
        { "5", "inv_misc_gem_green_01", names = { "Green Gem" }, colors = "grey:60" },
        { "6", "inv_misc_flower_01", names = { "Fireflower" }, colors = "red:60 green:12" },
        { "7", "inv_misc_flower_02", names = { "Peacebloom" }, colors = "red:20 green:60" },
        { "8", "inv_misc_leaf_01", names = { "Leaf" }, colors = "green:8 brown:80" },
        { "9", "inv_misc_coal_01", names = { "Coal" }, colors = "black:70" },
      }))
      rows = Catalog.Rows(data, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
    end)

    it("names colours by the nearest reference shade", function()
      assert.are.equal("green", Search.ColorName(65, -15, 11))
      assert.are.equal("grey", Search.ColorName(76, 0, 0))
      assert.are.equal("green", data.index.colorSlots[1].name[data.index.byKey[2]])
    end)

    it("matches every shade in the chip's hue band, closest first", function()
      assert.are.same({ 1, 7, 3, 2, 6 }, keys((find("", chips(chip("green"))))))
    end)

    it("matches colourless chips by lightness", function()
      assert.are.same({ 9 }, keys((find("", chips(chip("black"))))))
    end)

    it("ranks by the weighted average of the chips", function()
      assert.are.same({ 7, 6 }, keys((find("", chips(chip("red"), chip("green"))))))
      assert.are.same({ 6, 7 }, keys((find("", chips(chip("red"), chip("green", 0.3))))))
    end)

    it("weighs word matches against colour", function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "inv_shield_01", names = { "Emerald Shield" }, colors = "green:40" },
        { "2", "inv_chest_01", names = { "Guardian Plate" }, desc = "sturdy as a shield", colors = "green:70" },
      }))
      rows = Catalog.Rows(data, { 1, 2 })
      assert.are.same({ 1, 2 }, keys((find("shield", chips(chip("green"))))))
      assert.are.same({ 2, 1 }, keys((find("", chips(chip("green"))))))
    end)

    it("treats a typed colour word as text", function()
      assert.are.same({ 5 }, keys((find("green"))))
    end)

    it("combines chips with text", function()
      assert.are.same({ 1 }, keys((find("emerald", chips(chip("green"))))))
      assert.are.same({ 6 }, keys((find("fireflower", chips(chip("green"))))))
      assert.are.same({}, keys((find("coal", chips(chip("green"))))))
    end)

    it("converts a picked colour to OKLab scaled like the data", function()
      local red = Search.PickTarget(205 / 255, 40 / 255, 40 / 255)
      for i = 1, 3 do
        assert.is_true(math.abs(red[i] - addon.COLOR_LAB.red[i]) < 0.5)
      end
    end)
  end)

  it("computes edit distance with adjacent swaps", function()
    assert.are.equal(1, Search.Distance("skul", "skull", 2))
    assert.are.equal(1, Search.Distance("makr", "mark", 2))
    assert.are.equal(3, Search.Distance("abc", "xyzabc", 2))
  end)

  describe("explaining matches", function()
    local index

    before_each(function()
      local explained = Catalog.Parse(addon.fakeData(ns, {
        {
          "1",
          "spell_druid_tirelesspursuit",
          names = { "Tireless Pursuit" },
          desc = "increases movement speed",
          tags = "werewolf wolf",
          colors = "purple:34 black:40",
        },
      }))
      index = explained.index
    end)

    it("says where each search word matched", function()
      local opts = { synonyms = synonyms }
      assert.are.same({ { word = "werewolf", where = "tag" } }, Search.Explain(index, 1, "werewolf", opts))
      assert.are.same({ { word = "druid", where = "tag" } }, Search.Explain(index, 1, "druid", opts))
      assert.are.same({ { word = "pursuit", where = "name" } }, Search.Explain(index, 1, "pursuit", opts))
      assert.are.same({ { word = "movement", where = "description" } }, Search.Explain(index, 1, "movement", opts))
      assert.are.same(
        { { word = "wolf", where = "tag" }, { word = "druid", where = "tag" } },
        Search.Explain(index, 1, "wolf druid", opts)
      )
    end)

    it("names the synonym a search word matched through", function()
      local potion = Catalog.Parse(addon.fakeData(ns, { { "1", "inv_potion_158", names = { "Shadow Protection" } } }))
      assert.are.same(
        { { word = "shield", via = "protection", where = "name" } },
        Search.Explain(potion.index, 1, "shield", { synonyms = synonyms })
      )
    end)

    it("gives a colour chip's share of the icon", function()
      local chip = { target = addon.COLOR_LAB.purple, preset = "purple" }
      assert.are.same({ { color = "purple", share = 34 } }, Search.Explain(index, 1, "", { chips = { chip } }))
    end)

    it("colours the words of a name that a search word finds", function()
      local gold = "|cffffd100"
      assert.are.equal("Kite " .. gold .. "Shield|r", Search.Highlight("Kite Shield", "shields"))
      assert.are.equal(gold .. "Shield|rwall", Search.Highlight("Shieldwall", "shield"))
      assert.are.equal("Mal des " .. gold .. "Jägers|r", Search.Highlight("Mal des Jägers", "jager"))
      assert.are.equal("Tireless Pursuit", Search.Highlight("Tireless Pursuit", "wolf"))
      assert.are.equal(gold .. "Inc|rorporeal Defense", Search.Highlight("Incorporeal Defense", "inc"))
      assert.are.equal("Blessing of " .. gold .. "Prot|rection", Search.Highlight("Blessing of Protection", "prot"))
    end)
  end)
end)
