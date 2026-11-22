local ADDON_NAME, ns = ...

function ns.AddRecent(texture)
  if ns.db and texture then
    ns.Catalog.AddRecent(ns.db.recent, texture)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MODIFIER_STATE_CHANGED")

events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == ADDON_NAME then
      IconicDB = ns.InitDB(IconicDB)
      ns.SetupSettings()
      ns.SetupTooltips()
    end
    if ns.db then
      ns.Pickers.AttachBlizzard()
      ns.Pickers.RetryPending()
    end
  elseif event == "PLAYER_LOGIN" then
    ns.Pickers.AttachBlizzard()
    ns.Pickers.RetryPending()
  elseif event == "MODIFIER_STATE_CHANGED" then
    ns.OnModifierChanged()
  end
end)

SLASH_ICONIC1 = "/iconic"
SlashCmdList.ICONIC = function(msg)
  if strtrim(msg or ""):lower() == "settings" then
    ns.OpenSettings()
  else
    ns.Browser:Toggle()
  end
end
