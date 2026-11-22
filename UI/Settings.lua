local ADDON_NAME, ns = ...

local L = ns.L

local MODE_LABELS = {
  always = "Always",
  shift = "While holding Shift",
  ctrl = "While holding Ctrl",
  alt = "While holding Alt",
  never = "Never",
}

local function modeOptions()
  local container = Settings.CreateControlTextContainer()
  for _, mode in ipairs(ns.TOOLTIP_MODES) do
    container:Add(mode, L[MODE_LABELS[mode]])
  end
  return container:GetData()
end

function ns.SetupSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then
    return
  end
  local category = Settings.RegisterVerticalLayoutCategory(L["Iconic"])
  local settings = ns.db.settings

  local picker = Settings.RegisterAddOnSetting(
    category,
    "ICONIC_TOOLTIP_PICKER",
    "tooltipPicker",
    settings,
    Settings.VarType.String,
    L["Icon ID in the icon picker"],
    ns.DEFAULTS.settings.tooltipPicker
  )
  Settings.CreateDropdown(category, picker, modeOptions, L["When the tooltip of an icon in the picker shows its ID."])

  local game = Settings.RegisterAddOnSetting(
    category,
    "ICONIC_TOOLTIP_GAME",
    "tooltipGame",
    settings,
    Settings.VarType.String,
    L["Icon ID in game tooltips"],
    ns.DEFAULTS.settings.tooltipGame
  )
  Settings.CreateDropdown(
    category,
    game,
    modeOptions,
    L["When spell, item, mount and currency tooltips elsewhere in the game show their icon ID."]
  )

  Settings.RegisterCanvasLayoutSubcategory(category, ns.CreateAboutPanel(), L["About"])
  Settings.RegisterAddOnCategory(category)
  ns.settingsCategory = category
end

function ns.OpenSettings()
  if ns.settingsCategory then
    Settings.OpenToCategory(ns.settingsCategory:GetID())
  end
end
