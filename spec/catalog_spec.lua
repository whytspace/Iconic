local addon = require("spec.helpers.addon")

describe("Catalog", function()
  local ns, Catalog, data, rows

  local function keys(list)
    local result = {}
    for i, row in ipairs(list) do
      result[i] = data.index.key[row]
    end
    return result
  end

  before_each(function()
    ns = addon.load()
    Catalog = ns.Catalog
    data = Catalog.Parse(addon.fakeData(ns, {
      { "10", "ability_hunter_snipershot", names = { "Hunter's Mark" }, sources = "S", classMask = "4" },
      { "20", "spell_fire_fireball02", names = { "Fireball" }, sources = "S", classMask = "128" },
      { "30", "inv_sword_04", names = { "Worn Shortsword" }, sources = "I", categories = "2:7" },
      {
        "40",
        "inv_misc_food_15",
        names = { "Prowler Steak" },
        sources = "IS",
        categories = "0:5",
        professions = "185",
      },
      { "50", "inv_misc_questionmark" },
    }))
    rows =
      Catalog.Rows(data, { 10, 20, "Interface\\Icons\\INV_Sword_04", 40, 50, 30, "Interface\\Icons\\Unknown_Thing" })
  end)

  it("parses lookups and icon rows", function()
    local index = data.index
    assert.are.equal("Hunter", data.classes[3])
    assert.are.equal("One-Handed Swords", data.itemClasses["2:7"])
    assert.are.equal("Cooking", data.professions[185])
    assert.are.same({ "Prowler Steak" }, Catalog.Names(index, index.byKey[40]))
    assert.are.same({ 185 }, index.professions[index.byKey[40]])
  end)

  it("applies a translation's names, search words, tag words and labels", function()
    data.index.text[data.index.byKey[10]] = " hunter mark |  |  | x "
    Catalog.ApplyLocale(data, {
      classes = "3\tJäger\n",
      translatedWords = "werwolf\twerewolf\n",
      icons = { id = { 10, 999 }, refs = { "Mal des Jägers", "Unbekannt" }, text = { "mal jager||wolf", "x" } },
    })
    local row = data.index.byKey[10]
    assert.are.equal("Jäger", data.classes[3])
    assert.are.equal("werewolf", data.translatedWords.werwolf)
    assert.are.same({ "Mal des Jägers" }, Catalog.Names(data.index, row))
    assert.are.equal(" mal jager hunter mark |  | wolf | x ", data.index.text[row])
    assert.are.same({ "Fireball" }, Catalog.Names(data.index, data.index.byKey[20]))
    assert.are.equal("One-Handed Swords", data.itemClasses["2:7"])
  end)

  it("resolves texture paths to file IDs, drops duplicates and keeps unknown textures", function()
    assert.are.same({ 10, 20, 30, 40, 50, "Interface\\Icons\\Unknown_Thing" }, keys(rows))
  end)

  it("combines filter values with OR inside and AND across dimensions", function()
    local function filtered(filters)
      return keys(Catalog.Filter(data.index, rows, filters))
    end
    assert.are.same({ 10, 20 }, filtered({ class = { [3] = true, [8] = true } }))
    assert.are.same({ 30, 40 }, filtered({ source = { I = true } }))
    assert.are.same({ 30 }, filtered({ category = { [2] = true } }))
    assert.are.same({ 30 }, filtered({ category = { ["2:7"] = true } }))
    assert.are.same({ 40 }, filtered({ source = { S = true }, profession = { [185] = true } }))
  end)

  it("filters to usable icons", function()
    assert.are.same({ 10 }, keys(Catalog.Filter(data.index, rows, { usable = true }, { [10] = true })))
  end)

  it("groups icons into every matching section, the rest under Other", function()
    local titles = {}
    for i, section in ipairs(Catalog.Sections(data, rows, "class")) do
      titles[i] = section.title .. ":" .. table.concat(keys(section.rows), ",")
    end
    assert.are.same({ "Hunter:10", "Mage:20", "Other:30,40,50,Interface\\Icons\\Unknown_Thing" }, titles)
  end)

  it("orders source sections like the filter menu", function()
    local sections = Catalog.Sections(data, rows, "source")
    assert.are.equal("Spells", sections[1].title)
    assert.are.equal("Items", sections[2].title)
  end)

  it("groups by top-level item category", function()
    local sections = Catalog.Sections(data, rows, "category")
    assert.are.equal("Consumable", sections[1].title)
    assert.are.equal("Weapon", sections[2].title)
  end)

  it("puts recent icons first", function()
    local recent = Catalog.RecentRows(data, rows, { 30, 999, 10 })
    local sections = Catalog.Sections(data, rows, "none", recent)
    assert.are.equal("Recently used", sections[1].title)
    assert.are.same({ 30, 10 }, keys(sections[1].rows))
    assert.are.equal("All icons", sections[2].title)
  end)

  it("puts suggested icons before recent ones", function()
    local suggested = Catalog.SuggestedRows(data, rows, { 40 })
    local recent = Catalog.RecentRows(data, rows, { 30 })
    local sections = Catalog.Sections(data, rows, "none", recent, suggested)
    assert.are.equal("Suggested", sections[1].title)
    assert.is_true(sections[1].suggested)
    assert.are.equal("Recently used", sections[2].title)
  end)

  it("builds suggestions from textures and queries, unique, filtered and capped", function()
    local suggested = Catalog.SuggestedRows(data, rows, { 30, { query = "fireball" }, 999, 10, 30 })
    assert.are.same({ 30, 20, 10 }, keys(suggested))
    local spells = Catalog.SuggestedRows(data, rows, { 30, { query = "fireball" }, 10 }, { source = { S = true } })
    assert.are.same({ 20, 10 }, keys(spells))
    assert.are.same(
      { 30, 20 },
      keys(Catalog.SuggestedRows(data, rows, { 30, { query = "fireball" }, 10 }, nil, nil, 2))
    )
  end)

  it("reads spells, items and slots from a macro", function()
    local body = table.concat({
      "#showtooltip Fireball",
      "/cast [mod:shift] Frost Nova; Fireball",
      "/use 13",
      "/castsequence reset=3 Arcane Shot, !Steady Shot",
      "/use [@focus,help] Healthstone",
      "/cast [nocombat]",
      "/target focus",
    }, "\n")
    assert.are.same({
      { name = "Fireball" },
      { name = "Frost Nova" },
      { slot = 13 },
      { name = "Arcane Shot" },
      { name = "Steady Shot" },
      { name = "Healthstone" },
    }, Catalog.MacroTerms(body))
    assert.are.same({}, Catalog.MacroTerms(nil))
  end)

  it("keeps the recent list unique and capped", function()
    local list = { 1, 2, 3 }
    Catalog.AddRecent(list, 2, 3)
    assert.are.same({ 2, 1, 3 }, list)
    Catalog.AddRecent(list, 4, 3)
    assert.are.same({ 4, 2, 1 }, list)
  end)

  it("counts icons per filter value", function()
    local counts = Catalog.Counts(data.index, rows)
    assert.are.equal(3, counts.source.S)
    assert.are.equal(2, counts.source.I)
    assert.are.equal(1, counts.class[3])
    assert.are.equal(1, counts.category["2:7"])
    assert.are.equal(1, counts.category[2])
    assert.are.equal(1, counts.profession[185])
  end)

  describe("colors", function()
    before_each(function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "a", colors = "green:40 red:22" },
        { "2", "b", colors = "green:70" },
        { "3", "c", colors = "red:65" },
        { "4", "d", colors = "gray:15" },
      }))
      rows = Catalog.Rows(data, { 1, 2, 3, 4 })
    end)

    it("groups each icon under its strongest vivid color, most of it first", function()
      local titles = {}
      for i, section in ipairs(Catalog.Sections(data, rows, "color")) do
        titles[i] = section.title .. ":" .. table.concat(keys(section.rows), ",")
      end
      assert.are.same({ "Red:3", "Green:2,1", "Gray:4" }, titles)
    end)

    it("ignores color filters", function()
      assert.are.same({ 1, 2, 3, 4 }, keys(Catalog.Filter(data.index, rows, { color = { red = true } })))
    end)

    it("hints a color for its name and aliases", function()
      for word, preset in pairs({ blood = "red", crimson = "crimson" }) do
        local hint = Catalog.Hints(data, word, Catalog.Counts(data.index, rows))[1]
        assert.are.equal("color", hint.dim)
        assert.are.equal(preset, hint.value)
        assert.are.same({ word }, hint.words)
      end
    end)

    it("hints a two-word color for both words", function()
      local hint = Catalog.Hints(data, "sword dark green", Catalog.Counts(data.index, rows))[1]
      assert.are.equal("darkgreen", hint.value)
      assert.are.same({ "dark", "green" }, hint.words)
    end)

    it("counts icons per color", function()
      local counts = Catalog.Counts(data.index, rows)
      assert.are.equal(2, counts.color.green)
      assert.are.equal(2, counts.color.red)
      assert.are.equal(1, counts.color.gray)
    end)
  end)

  describe("tag categories", function()
    local tagData, tagRows

    before_each(function()
      tagData = Catalog.Parse(addon.fakeData(ns, {
        { "1", "inv_helmet_01", tags = "helmet skull metal" },
        { "2", "inv_misc_cowl", tags = "cowl cloth" },
        { "3", "inv_sword_01", tags = "sword blade" },
        { "4", "spell_fire_01", tags = "swirl fire" },
        { "5", "inv_misc_thing", tags = "thingamajig" },
        { "6", "inv_misc_skull", tags = "skull helmet" },
        { "7", "inv_misc_none" },
      }))
      local textures = {}
      for row = 1, tagData.index.count do
        textures[row] = tagData.index.key[row]
      end
      tagRows = Catalog.Rows(tagData, textures)
    end)

    local function tagKeys(list)
      local result = {}
      for i, row in ipairs(list) do
        result[i] = tagData.index.key[row]
      end
      return result
    end

    local function filtered(selected)
      return tagKeys(Catalog.Filter(tagData.index, tagRows, { tag = selected }))
    end

    it("puts an icon in the category of its first tag only", function()
      assert.are.same({ 6 }, filtered({ ["creatures.undead"] = true }))
      assert.are.same({ 1, 2 }, filtered({ ["armor.head"] = true }))
    end)

    it("counts a word's synonyms toward its category", function()
      assert.are.same({ 1, 2 }, filtered({ ["armor.head"] = true }))
    end)

    it("filters by a top category or one of its subcategories", function()
      assert.are.same({ 1, 2, 3 }, filtered({ armor = true, ["weapons.swords"] = true }))
      assert.are.same({ 4 }, filtered({ magic = true }))
    end)

    it("counts subcategories and their top category", function()
      local counts = Catalog.Counts(tagData.index, tagRows).tag
      assert.are.equal(2, counts["armor.head"])
      assert.are.equal(2, counts.armor)
      assert.are.equal(1, counts.magic)
      assert.is_nil(counts["magic.magic"])
    end)

    it("groups by top category in table order, untagged icons under Unknown, unmapped subjects under Other", function()
      local titles = {}
      for i, section in ipairs(Catalog.Sections(tagData, tagRows, "tag")) do
        titles[i] = section.title .. ":" .. table.concat(tagKeys(section.rows), ",")
      end
      assert.are.same({ "Armor:1,2", "Weapons:3", "Creatures:6", "Magic & effects:4", "Unknown:7", "Other:5" }, titles)
    end)

    it("puts textures without data under Unknown", function()
      local newRows = Catalog.Rows(tagData, { 3, "Interface\\Icons\\Brand_New_Icon" })
      assert.are.same(
        { "Interface\\Icons\\Brand_New_Icon" },
        tagKeys(Catalog.Filter(tagData.index, newRows, { tag = { unknown = true } }))
      )
    end)

    it("offers tag categories as search hints", function()
      local counts = Catalog.Counts(tagData.index, tagRows)
      local hints = Catalog.Hints(tagData, "head", counts)
      assert.are.equal("Armor › Head", hints[1].label)
      assert.are.equal("Iconic category", hints[1].group)
    end)
  end)

  describe("hints", function()
    local counts
    before_each(function()
      counts = Catalog.Counts(data.index, rows)
    end)

    local function labels(list)
      local result = {}
      for i, s in ipairs(list) do
        result[i] = s.group .. ": " .. s.label
      end
      return result
    end

    it("offers filter values whose label starts with a typed word", function()
      assert.are.same({ "Class: Hunter" }, labels(Catalog.Hints(data, "hunt", counts)))
    end)

    it("matches words inside labels and names the parent category", function()
      assert.are.same(
        { "Blizzard category: Weapon › One-Handed Swords" },
        labels(Catalog.Hints(data, "sword", counts))
      )
    end)

    it("skips values without icons and active filters", function()
      assert.are.same({}, labels(Catalog.Hints(data, "armor", counts)))
      assert.are.same({}, labels(Catalog.Hints(data, "hunter", counts, { class = { [3] = true } })))
    end)

    it("reports the query word to drop", function()
      local hint = Catalog.Hints(data, "fire hunter", counts)[1]
      assert.are.same({ "hunter" }, hint.words)
      assert.are.equal("fire", Catalog.RemoveWord("fire Hunter", hint.words[1]))
    end)
  end)

  it("counts facets: other groups narrow, the own group does not", function()
    local counts = Catalog.FacetCounts(data.index, rows, { source = { I = true } })
    -- Source counts ignore the Source filter itself.
    assert.are.equal(3, counts.source.S)
    -- Other groups count only items.
    assert.is_nil(counts.class[3])
    assert.are.equal(1, counts.category["2:7"])
    assert.are.equal(1, counts.profession[185])
  end)

  it("counts active filters", function()
    assert.are.equal(3, Catalog.ActiveFilterCount({ usable = true, class = { [3] = true, [8] = true } }))
  end)

  describe("names from game references", function()
    local requested, Game

    before_each(function()
      requested = {}
      Game = addon.load({
        C_Spell = {
          GetSpellName = function(id)
            return ({ [133] = "Feuerball" })[id]
          end,
          RequestLoadSpellData = function(id)
            requested[#requested + 1] = id
          end,
        },
        C_Item = {
          GetItemNameByID = function(id)
            return ({ [6948] = "Ruhestein" })[id]
          end,
          RequestLoadItemDataByID = function(id)
            requested[#requested + 1] = id
          end,
        },
        C_CurrencyInfo = {
          GetCurrencyInfo = function(id)
            return id == 1792 and { name = "Ehre" } or nil
          end,
        },
      }).Catalog
    end)

    it("looks up spells, items and currencies in the game's language", function()
      assert.are.equal("Feuerball", Game.NameOf("s133"))
      assert.are.equal("Ruhestein", Game.NameOf("i6948"))
      assert.are.equal("Ehre", Game.NameOf("c1792"))
    end)

    it("requests spells the game hasn't loaded and reports them as pending", function()
      local name, pending = Game.NameOf("s116")
      assert.is_nil(name)
      assert.is_true(pending)
      assert.are.same({ 116 }, requested)
    end)

    it("keeps names stored as text", function()
      assert.are.equal("Some Name", Game.NameOf("Some Name"))
    end)

    it("requests items the game hasn't loaded and reports them as pending", function()
      local name, pending = Game.NameOf("i19019")
      assert.is_nil(name)
      assert.is_true(pending)
      assert.are.same({ 19019 }, requested)
      local index = { refs = { "s133|i19019|i6948" } }
      local names, anyPending = Game.Names(index, 1)
      assert.are.same({ "Feuerball", "Ruhestein" }, names)
      assert.is_true(anyPending)
    end)
  end)
end)

-- Every subject (first picture tag) in scripts/icon_tags.json has a tag category in Data/TagCategories.lua.
describe("Tag categories", function()
  it("cover every icon's first tag", function()
    local Catalog = addon.load().Catalog
    local text = assert(io.open(addon.root .. "/scripts/icon_tags.json")):read("*a")
    local missing, seen = {}, {}
    for first in text:gmatch('%[%s*"(.-)"') do
      if not seen[first] and not Catalog.TagCategoryOf(first) then
        missing[#missing + 1] = first
      end
      seen[first] = true
    end
    table.sort(missing)
    assert.are.same({}, missing)
  end)
end)
