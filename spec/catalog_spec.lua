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
      { "10", "ability_hunter_snipershot", names = { "Hunter's Mark" }, src = "S", cls = "4" },
      { "20", "spell_fire_fireball02", names = { "Fireball" }, src = "S", cls = "128" },
      { "30", "inv_sword_04", names = { "Worn Shortsword" }, src = "I", cats = "2:7" },
      { "40", "inv_misc_food_15", names = { "Prowler Steak" }, src = "IS", cats = "0:5", profs = "185" },
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
    assert.are.same({ 185 }, index.profs[index.byKey[40]])
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

  describe("colours", function()
    before_each(function()
      data = Catalog.Parse(addon.fakeData(ns, {
        { "1", "a", colors = "green:40 red:22" },
        { "2", "b", colors = "green:70" },
        { "3", "c", colors = "red:65" },
        { "4", "d", colors = "grey:15" },
      }))
      rows = Catalog.Rows(data, { 1, 2, 3, 4 })
    end)

    it("groups each icon under its strongest vivid colour, most of it first", function()
      local titles = {}
      for i, section in ipairs(Catalog.Sections(data, rows, "color")) do
        titles[i] = section.title .. ":" .. table.concat(keys(section.rows), ",")
      end
      assert.are.same({ "Red:3", "Green:2,1", "Grey:4" }, titles)
    end)

    it("ignores colour filters", function()
      assert.are.same({ 1, 2, 3, 4 }, keys(Catalog.Filter(data.index, rows, { color = { red = true } })))
    end)

    it("suggests a colour for related words and aliases", function()
      for _, word in ipairs({ "blood", "crimson" }) do
        local suggestion = Catalog.Suggest(data, word, Catalog.Counts(data.index, rows))[1]
        assert.are.equal("color", suggestion.dim)
        assert.are.equal("red", suggestion.value)
        assert.are.equal(word, suggestion.word)
      end
    end)

    it("counts icons per colour", function()
      local counts = Catalog.Counts(data.index, rows)
      assert.are.equal(2, counts.color.green)
      assert.are.equal(2, counts.color.red)
      assert.is_nil(counts.color.grey)
    end)
  end)

  describe("suggestions", function()
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
      assert.are.same({ "Class: Hunter" }, labels(Catalog.Suggest(data, "hunt", counts)))
    end)

    it("matches words inside labels and names the parent category", function()
      assert.are.same({ "Item category: Weapon › One-Handed Swords" }, labels(Catalog.Suggest(data, "sword", counts)))
    end)

    it("skips values without icons and active filters", function()
      assert.are.same({}, labels(Catalog.Suggest(data, "armor", counts)))
      assert.are.same({}, labels(Catalog.Suggest(data, "hunter", counts, { class = { [3] = true } })))
    end)

    it("reports the query word to drop", function()
      local suggestion = Catalog.Suggest(data, "fire hunter", counts)[1]
      assert.are.equal("hunter", suggestion.word)
      assert.are.equal("fire", Catalog.RemoveWord("fire Hunter", suggestion.word))
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
end)
