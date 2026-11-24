local ADDON_NAME, ns = ...

-- Maintainer tool behind /iconic check: a smoke test of the data, search, client APIs and pickers in this client.
local Check = {}
ns.Check = Check

-- Wait for a picker's grid, which fills a frame after it shows.
local FILL_DELAY = 0.5

-- Client APIs Iconic calls without a guard.
local REQUIRED = {
  "C_AddOns.LoadAddOn",
  "C_Container.GetContainerItemInfo",
  "C_Container.GetContainerNumSlots",
  "C_Item.GetItemIconByID",
  "C_Spell.GetSpellTexture",
  "C_Timer.After",
  "CreateAndInitFromMixin",
  "CreateAtlasMarkup",
  "CreateScrollBoxListLinearView",
  "GetClassAtlas",
  "GetFileIDFromPath",
  "IconDataProviderMixin",
  "MinimalSliderWithSteppersMixin",
  "ScrollUtil.InitScrollBoxListWithScrollBar",
  "Settings.CreateCheckbox",
  "Settings.CreateDropdown",
  "Settings.RegisterAddOnCategory",
  "Settings.RegisterAddOnSetting",
  "Settings.RegisterCanvasLayoutSubcategory",
}

-- Client APIs Iconic guards; missing ones only turn a feature off.
local OPTIONAL = {
  "C_ClassTalents.GetActiveConfigID",
  "C_CurrencyInfo.GetCurrencyInfo",
  "C_MountJournal.GetMountInfoByID",
  "C_SpellBook.IsSpellKnown",
  "C_TransmogOutfitInfo",
  "C_Traits.GetGroupDisplayInfoByTreeID",
  "ColorPickerFrame.SetupColorPickerAndShow",
  "TooltipDataProcessor.AddTooltipPostCall",
}

-- Searches every client's data answers.
local QUERIES = { "sword", "fire", "shield", "heal" }

-- Picker frames of the game's UI, with the load-on-demand add-on that creates each. Only the macro UI is loaded
-- here: other clients' add-ons can be present but broken in this one.
local PICKERS = {
  {
    name = "Macros",
    addon = "Blizzard_MacroUI",
    load = true,
    frame = function()
      return MacroPopupFrame
    end,
  },
  {
    name = "Equipment sets",
    frame = function()
      return GearManagerPopupFrame
    end,
  },
  {
    name = "Bank tabs",
    frame = function()
      return BankPanel and BankPanel.TabSettingsMenu
    end,
  },
  {
    name = "Guild bank",
    addon = "Blizzard_GuildBankUI",
    frame = function()
      return GuildBankPopupFrame
    end,
  },
  {
    name = "Outfits",
    addon = "Blizzard_Transmog",
    frame = function()
      return TransmogFrame and TransmogFrame.OutfitPopup
    end,
  },
}

local function print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Iconic check:|r " .. message)
end

local function resolve(path)
  local value = _G
  for part in path:gmatch("[^.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

-- Runs `fn` protected; it returns ok, detail. Counts the outcome.
function Check:Run(label, fn)
  local ran, ok, detail = pcall(fn)
  if not ran then
    ok, detail = false, ok
  end
  if ok == nil then
    print("|cff999999–|r " .. label .. (detail and (": " .. tostring(detail)) or ""))
    return
  end
  if ok then
    self.passed = self.passed + 1
  else
    self.failed = self.failed + 1
  end
  print((ok and "|cff33dd33OK|r " or "|cffdd3333FAIL|r ") .. label .. (detail and (": " .. tostring(detail)) or ""))
end

function Check:Client()
  local version, build, _, interface = GetBuildInfo()
  print(("client %s.%s, interface %s"):format(version, build, tostring(interface)))
end

function Check:Data()
  self:Run("icon data", function()
    local data = ns.LoadData()
    if not data then
      return false, "Iconic_Data did not load"
    end
    local version = GetBuildInfo()
    local client = version:match("^(%d+%.%d+)")
    local shipped = tostring(data.build):match("^(%d+%.%d+)")
    local detail = ("%s %s, %d icons"):format(tostring(data.flavor), tostring(data.build), data.index.count)
    return client == shipped and data.index.count > 0, detail
  end)
end

function Check:Searches()
  local data = ns.LoadData()
  if not data then
    return
  end
  local textures = {}
  for row = 1, data.index.count do
    textures[row] = data.index.key[row]
  end
  local rows = ns.Catalog.Rows(data, textures)
  local opts = { synonyms = ns.synonyms }
  for _, query in ipairs(QUERIES) do
    self:Run(("search %q"):format(query), function()
      local results, isLoose = ns.Search.Find(data.index, rows, query, opts)
      return #results > 0 and not isLoose, #results .. " results"
    end)
  end
  self:Run("color chip red", function()
    local red = ns.Color.FromHex(ns.Color.Preset("red").hex)
    local chip = { target = ns.Color.ChipTarget(red.r, red.g, red.b) }
    local results = ns.Search.Find(data.index, rows, "", { chips = { chip } })
    return #results > 0, #results .. " results"
  end)
end

function Check:APIs()
  local missing = {}
  for _, path in ipairs(REQUIRED) do
    if resolve(path) == nil then
      missing[#missing + 1] = path
    end
  end
  self:Run("required APIs", function()
    return #missing == 0, #missing > 0 and table.concat(missing, ", ") or (#REQUIRED .. " present")
  end)
  local absent = {}
  for _, path in ipairs(OPTIONAL) do
    if resolve(path) == nil then
      absent[#absent + 1] = path
    end
  end
  if #absent > 0 then
    self:Run("optional APIs", function()
      return nil, "absent " .. table.concat(absent, ", ")
    end)
  end
end

function Check:Pickers()
  for _, picker in ipairs(PICKERS) do
    self:Run("picker " .. picker.name, function()
      local loaded = not picker.addon or C_AddOns.IsAddOnLoaded(picker.addon)
      if not loaded and picker.load then
        loaded = C_AddOns.LoadAddOn(picker.addon)
      end
      local frame = picker.frame()
      if not frame then
        return nil, loaded and "not in this client" or "not loaded yet, open it once"
      end
      if not frame.IconSelector then
        return nil, "Blizzard's old picker, not replaced"
      end
      return ns.Pickers.attached[frame] ~= nil, ns.Pickers.attached[frame] and "attached" or "not attached"
    end)
  end
end

-- Whether a view shows icons from the data.
local function viewFilled(view)
  if not (view and view.frame:IsShown() and view.rows) then
    return false, "Iconic's grid not shown"
  end
  return #view.rows > 0 and next(view.visibleRows or {}) ~= nil, #view.rows .. " icons"
end

-- Opens the macro picker and the browser, then reports once their grids have filled.
function Check:Windows(done)
  local tour = ns.ScreenshotTour
  local opened = pcall(tour.OpenMacroPicker)
  local browserOpened, browserError = pcall(ns.Browser.Open, ns.Browser)
  C_Timer.After(FILL_DELAY, function()
    self:Run("macro picker opens", function()
      if not opened then
        return false, "could not open"
      end
      local state = ns.Pickers.attached[MacroPopupFrame]
      local ok, detail = viewFilled(state and state.view)
      return ok and not MacroPopupFrame.IconSelector:IsShown(), detail
    end)
    pcall(tour.CloseMacroPicker)
    self:Run("browser opens", function()
      if not browserOpened then
        return false, browserError
      end
      return viewFilled(ns.Browser.view)
    end)
    if ns.Browser.frame then
      ns.Browser.frame:Hide()
    end
    done()
  end)
end

function Check:Start()
  if InCombatLockdown() then
    print("not in combat")
    return
  end
  self.passed, self.failed = 0, 0
  self:Client()
  self:Data()
  self:Searches()
  self:APIs()
  self:Pickers()
  self:Windows(function()
    local color = self.failed > 0 and "|cffdd3333" or "|cff33dd33"
    print(("%s%d passed, %d failed|r"):format(color, self.passed, self.failed))
  end)
end
