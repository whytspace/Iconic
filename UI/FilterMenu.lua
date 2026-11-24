local ADDON_NAME, ns = ...

local L = ns.L
local Catalog, View = ns.Catalog, ns.View

-- Keys of a map sorted by their values; with `numericOnly`, only the number keys.
local function sortedKeys(map, numericOnly)
  local keys = {}
  for key in pairs(map) do
    if not numericOnly or type(key) == "number" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return tostring(map[a]) < tostring(map[b])
  end)
  return keys
end

local MENU_ICON = 16

-- Class name in its class color, with the class icon.
local function classLabel(classId, name)
  local file = View.ClassFile(classId)
  if not file then
    return name
  end
  local color = (C_ClassColor and C_ClassColor.GetClassColor(file)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file])
  local text = color and color:WrapTextInColorCode(name) or name
  return CreateAtlasMarkup(GetClassAtlas(file), MENU_ICON, MENU_ICON) .. " " .. text
end

local function iconLabel(icon, name)
  return icon and ("|T" .. icon .. ":" .. MENU_ICON .. ":" .. MENU_ICON .. "|t " .. name) or name
end

local MENU_ROW_HEIGHT, MENU_CHECK_WIDTH, MENU_COUNT_GAP, MENU_ARROW_WIDTH = 20, 22, 18, 22

local function grayed(text)
  return "|cff808080" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
end

-- Shows a right-aligned count in a menu entry (in front of the submenu arrow when there is one) and grays
-- the label when the count is zero. Runs on every menu refresh, so it reads the count live.
local function addCount(description, label, getCount, isSelected, hasSubmenu)
  description:AddInitializer(function(button)
    local count = getCount()
    button.fontString:SetText((count == 0 and not isSelected()) and grayed(label) or label)
    local text = button:AttachFontString()
    text:SetFontObject("GameFontDisableSmall")
    text:SetHeight(MENU_ROW_HEIGHT)
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", hasSubmenu and -MENU_ARROW_WIDTH or -4, 0)
    text:SetText(count)
    local width = MENU_CHECK_WIDTH
      + button.fontString:GetUnboundedStringWidth()
      + MENU_COUNT_GAP
      + text:GetUnboundedStringWidth()
      + (hasSubmenu and MENU_ARROW_WIDTH or 4)
    return width, MENU_ROW_HEIGHT
  end)
end

-- Subclass keys ("2:7") of an item class, sorted by name.
local function subcategories(itemClasses, top)
  local prefix, keys = top .. ":", {}
  for key in pairs(itemClasses) do
    if type(key) == "string" and key:sub(1, #prefix) == prefix then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return itemClasses[a] < itemClasses[b]
  end)
  return keys
end

function View:SetupFilterMenu()
  local view = self
  local function toggle(dim, value)
    return function()
      local set = view:FilterSet(dim)
      set[value] = not set[value] or nil
      view:Refresh()
      return MenuResponse.Refresh
    end
  end
  local function isSet(dim, value)
    return function()
      return view.filters[dim] and view.filters[dim][value] or false
    end
  end
  local function allSet(dim, values)
    return function()
      local set = view.filters[dim] or {}
      for _, value in ipairs(values) do
        if not set[value] then
          return false
        end
      end
      return true
    end
  end
  -- Selects every value, or clears them all when every one is already selected.
  local function toggleAll(dim, values)
    return function()
      local set, all = view:FilterSet(dim), true
      for _, value in ipairs(values) do
        all = all and set[value] == true
      end
      for _, value in ipairs(values) do
        set[value] = (not all) or nil
      end
      view:Refresh()
      return MenuResponse.Refresh
    end
  end

  self.filter:SetupMenu(function(_, root)
    local data = view.data
    -- Totals decide which values exist at all; facet counts (under the other active filters and the search)
    -- are shown, and values with none are grayed out but stay visible.
    local totals = view.counts or {}
    local function total(dim, value)
      return totals[dim] and totals[dim][value] or 0
    end
    local function facet(dim, value)
      local facets = view:FacetCounts()
      return facets[dim] and facets[dim][value] or 0
    end
    local function present(dim, values)
      local list = {}
      for _, value in ipairs(values) do
        if total(dim, value) > 0 then
          list[#list + 1] = value
        end
      end
      return list
    end
    -- A checkbox entry with its right-aligned count; grayed at zero unless it is ticked.
    local function entry(parent, label, dim, value, isSelected, setSelected, hasSubmenu)
      local description = parent:CreateCheckbox(label, isSelected, setSelected)
      addCount(description, label, function()
        return facet(dim, value)
      end, isSelected, hasSubmenu)
      return description
    end

    root:CreateCheckbox(L["Only my spells & items"], function()
      return view.filters.usable or false
    end, function()
      view.filters.usable = not view.filters.usable or nil
      view:Refresh()
      return MenuResponse.Refresh
    end)
    root:CreateDivider()

    local sources = {}
    for _, source in ipairs(Catalog.SOURCES) do
      if total("source", source.key) > 0 then
        sources[#sources + 1] = source
      end
    end
    if #sources > 0 then
      local menu = root:CreateButton(L["Source"])
      for _, source in ipairs(sources) do
        entry(menu, L[source.label], "source", source.key, isSet("source", source.key), toggle("source", source.key))
      end
    end
    if not data then
      return
    end

    local classIds = present("class", sortedKeys(data.classes))
    if #classIds > 0 then
      local menu = root:CreateButton(L["Class"])
      for _, classId in ipairs(classIds) do
        local label = classLabel(classId, data.classes[classId])
        entry(menu, label, "class", classId, isSet("class", classId), toggle("class", classId))
      end
    end

    local tops = present("category", sortedKeys(data.itemClasses, true))
    if #tops > 0 then
      local menu = root:CreateButton(L["Item category"])
      for _, top in ipairs(tops) do
        local keys = present("category", subcategories(data.itemClasses, top))
        local name = data.itemClasses[top]
        if #keys <= 1 then
          -- A lone subcategory adds nothing; filter by it straight from the category entry.
          local key = keys[1] or top
          entry(menu, name, "category", key, isSet("category", key), toggle("category", key))
        else
          -- Checking the category selects all its subcategories; hovering opens them.
          local sub = entry(menu, name, "category", top, allSet("category", keys), toggleAll("category", keys), true)
          for _, key in ipairs(keys) do
            entry(sub, data.itemClasses[key], "category", key, isSet("category", key), toggle("category", key))
          end
        end
      end
    end

    local profs = present("profession", sortedKeys(data.professions))
    if #profs > 0 then
      local menu = root:CreateButton(L["Profession"])
      for _, prof in ipairs(profs) do
        local label = iconLabel(data.professionIcons and data.professionIcons[prof], data.professions[prof])
        entry(menu, label, "profession", prof, isSet("profession", prof), toggle("profession", prof))
      end
    end
  end)

  self.filter:SetIsDefaultCallback(function()
    return Catalog.ActiveFilterCount(view.filters) == 0
  end)
  self.filter:SetDefaultCallback(function()
    view.filters = {}
    view:Refresh()
  end)
end

-- Filter-style button whose fixed text names the current grouping.
function View:UpdateGroupText()
  local current = View.SavedGroupBy()
  for _, entry in ipairs(Catalog.GROUPS) do
    if entry.key == current then
      self.group:SetText(L["Group by: %s"]:format(L[entry.label]))
    end
  end
end

function View:SetupGroupMenu()
  local view = self
  self.group:SetupMenu(function(_, root)
    for _, entry in ipairs(Catalog.GROUPS) do
      root:CreateRadio(L[entry.label], function()
        return View.SavedGroupBy() == entry.key
      end, function()
        if ns.db then
          ns.db.groupBy = entry.key
        end
        view:UpdateGroupText()
        view:Refresh()
      end, entry.key)
    end
  end)
  self:UpdateGroupText()
end
