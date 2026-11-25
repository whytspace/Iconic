local ADDON_NAME, ns = ...

local Pickers = ns.Pickers

-- Baganator's bank windows, one per skin, each with its own copies of Blizzard's bank tab settings menu.
Pickers.AddAdapter({
  addon = "Baganator",
  integration = { id = "Baganator", name = "Baganator", addons = { "Baganator" } },
  events = { "BANKFRAME_OPENED" },
  overrides = Pickers.BANK_OVERRIDES,
  frames = function()
    local frames = {}
    local skins = Baganator and Baganator.API and Baganator.API.Skins
    local skin = skins and skins.GetCurrentSkin and skins.GetCurrentSkin()
    if not skin then
      return frames
    end
    for _, kind in ipairs({ "Single", "Category" }) do
      local view = _G["Baganator_" .. kind .. "ViewBankViewFrame" .. skin]
      for _, tabs in ipairs({ view and view.Character or false, view and view.Warband or false }) do
        if tabs and tabs.TabSettingsMenu then
          frames[#frames + 1] = tabs.TabSettingsMenu
        end
      end
    end
    return frames
  end,
})
