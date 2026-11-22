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

  describe("colours", function()
    before_each(function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "inv_misc_gem_emerald_01", names = { "Emerald" }, colors = "green:70 teal:12" },
        { "2", "inv_misc_herb_01", names = { "Peacebloom" }, colors = "green:35 yellow:25" },
        { "3", "inv_misc_gem_ruby_01", names = { "Ruby" }, colors = "red:65" },
        { "4", "inv_misc_gem_green_01", names = { "Green Gem" }, colors = "grey:60" },
        { "5", "inv_misc_flower_01", names = { "Fireflower" }, colors = "red:30 green:28" },
      }))
      rows = Catalog.Rows(data, { 1, 2, 3, 4, 5 })
    end)

    local function named(...)
      local chips = {}
      for i, key in ipairs({ ... }) do
        chips[i] = { key = key }
      end
      return { chips = chips }
    end

    it("ranks icons by how much of a named colour they show", function()
      assert.are.same({ 1, 2, 5 }, keys((find("", named("green")))))
    end)

    it("treats a typed colour word as text", function()
      assert.are.same({ 4 }, keys((find("green"))))
    end)

    it("requires every chip and ranks by the weakest", function()
      assert.are.same({ 5 }, keys((find("", named("red", "green")))))
    end)

    it("combines chips with text", function()
      assert.are.same({ 1 }, keys((find("emerald", named("green")))))
    end)

    describe("picked colour", function()
      local green, red

      before_each(function()
        green = Search.PickTarget(60 / 255, 170 / 255, 55 / 255)
        red = Search.PickTarget(205 / 255, 40 / 255, 40 / 255)
      end)

      it("converts a colour to OKLab scaled like the data", function()
        local lab = addon.COLOR_LAB.red
        for i = 1, 3 do
          assert.is_true(math.abs(red[i] - lab[i]) < 0.5)
        end
      end)

      it("ranks icons by how much of them is near the colour and drops distant ones", function()
        assert.are.same({ 1, 2, 5 }, keys((find("", { chips = { { target = green } } }))))
        assert.are.same({ 3, 5 }, keys((find("", { chips = { { target = red } } }))))
      end)

      it("filters by words and still ranks by closeness", function()
        assert.are.same({ 1 }, keys((find("gem", { chips = { { target = green } } }))))
        assert.are.same({ 3 }, keys((find("gem", { chips = { { target = red } } }))))
        assert.are.same({ 5 }, keys((find("flower", { chips = { { target = red } } }))))
        assert.are.same({}, keys((find("peacebloom", { chips = { { target = red } } }))))
      end)

      it("combines a picked colour with a named one", function()
        assert.are.same({ 5 }, keys((find("", { chips = { { target = red }, { key = "green" } } }))))
      end)
    end)
  end)

  it("computes edit distance with adjacent swaps", function()
    assert.are.equal(1, Search.Distance("skul", "skull", 2))
    assert.are.equal(1, Search.Distance("makr", "mark", 2))
    assert.are.equal(3, Search.Distance("abc", "xyzabc", 2))
  end)
end)
