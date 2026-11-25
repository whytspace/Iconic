local ADDON_NAME, ns = ...

local L = ns.L

-- Iconic's page in the game's settings; the local name avoids shadowing Blizzard's `Settings`.
local SettingsPage = {}
ns.SettingsPage = SettingsPage

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

function SettingsPage.Setup()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then
    return
  end
  local category, layout = Settings.RegisterVerticalLayoutCategory(L["Iconic"])
  local settings = ns.db.settings
  -- A section header, which also gives the page some room.
  local function section(title)
    if layout and CreateSettingsListSectionHeaderInitializer then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
    end
  end

  section(L["Tooltips"])

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

  local names = Settings.RegisterAddOnSetting(
    category,
    "ICONIC_TOOLTIP_NAMES",
    "tooltipNames",
    settings,
    Settings.VarType.String,
    L["All names in the icon picker"],
    ns.DEFAULTS.settings.tooltipNames
  )
  Settings.CreateDropdown(
    category,
    names,
    modeOptions,
    L["When the tooltip of an icon in the picker lists all its names, not only the ones the search finds."]
  )

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

  section(L["Icon picker"])
  local suggested = Settings.RegisterAddOnSetting(
    category,
    "ICONIC_SHOW_SUGGESTED",
    "showSuggested",
    settings,
    Settings.VarType.Boolean,
    L["Show suggested icons"],
    ns.DEFAULTS.settings.showSuggested
  )
  Settings.CreateCheckbox(
    category,
    suggested,
    L["Icons that fit what you're editing, such as the items of an equipment set, appear first."]
  )

  local recent = Settings.RegisterAddOnSetting(
    category,
    "ICONIC_SHOW_RECENT",
    "showRecent",
    settings,
    Settings.VarType.Boolean,
    L["Show recently used icons"],
    ns.DEFAULTS.settings.showRecent
  )
  Settings.CreateCheckbox(category, recent, L["Icons you picked recently appear first."])

  -- One switch per integration with another add-on, for installed ones; on unless turned off.
  local exists = C_AddOns and C_AddOns.DoesAddOnExist
  local installed = {}
  for _, integration in ipairs(ns.Pickers.Integrations()) do
    for _, addon in ipairs(integration.addons) do
      if exists and exists(addon) then
        installed[#installed + 1] = integration
        break
      end
    end
  end
  if #installed > 0 and Settings.RegisterProxySetting then
    section(L["Other add-ons"])
  end
  for _, integration in ipairs(Settings.RegisterProxySetting and installed or {}) do
    local id = integration.id
    local setting = Settings.RegisterProxySetting(
      category,
      "ICONIC_INTEGRATION_" .. id:upper(),
      Settings.VarType.Boolean,
      integration.name,
      true,
      function()
        return not ns.db.disabledIntegrations[id]
      end,
      function(enabled)
        ns.Pickers.SetIntegrationEnabled(id, enabled)
      end
    )
    Settings.CreateCheckbox(
      category,
      setting,
      L["Iconic replaces this add-on's icon picker. Turning it off takes effect after /reload."]
    )
  end

  Settings.RegisterCanvasLayoutSubcategory(category, ns.About.CreatePanel(), L["About"])
  Settings.RegisterAddOnCategory(category)
  SettingsPage.category = category
end

function SettingsPage.Open()
  if SettingsPage.category then
    Settings.OpenToCategory(SettingsPage.category:GetID())
  end
end

-- A small gear button on `parent` that opens Iconic's settings.
function SettingsPage.CreateButton(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(15, 16)
  -- Classic Era (interface 1.15) lacks the atlas's texture file.
  if select(4, GetBuildInfo()) < 11600 then
    button:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    button:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
  else
    button:SetNormalAtlas("questlog-icon-setting")
    button:SetHighlightAtlas("questlog-icon-setting", "ADD")
  end
  button:GetHighlightTexture():SetAlpha(0.4)
  button:SetScript("OnClick", SettingsPage.Open)
  button:SetScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Settings"])
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return button
end
