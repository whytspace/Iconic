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
    assert.are.equal(" 185 ", index.profs[index.byKey[40]])
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

  it("counts active filters", function()
    assert.are.equal(3, Catalog.ActiveFilterCount({ usable = true, class = { [3] = true, [8] = true } }))
  end)
end)
