local ADDON_NAME, ns = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == ADDON_NAME then
      IconicDB = ns.InitDB(IconicDB)
      ns.SettingsPage.Setup()
      ns.Tooltips.Setup()
    end
    if ns.db then
      ns.Pickers.OnAddonLoaded(name)
      ns.Pickers.RetryPending()
    end
  elseif event == "PLAYER_LOGIN" then
    ns.Pickers.AttachAll()
    ns.Pickers.RetryPending()
  end
end)

SLASH_ICONIC1 = "/iconic"
SlashCmdList.ICONIC = function(msg)
  local command = strtrim(msg or ""):lower()
  if command == "settings" then
    ns.SettingsPage.Open()
    --@do-not-package@
    -- Maintainer tools (README screenshots and animation); the packager strips them from releases.
  elseif command == "shot" then
    ns.Screenshot:Capture()
  elseif command == "shot demo" then
    ns.Demo:Run()
  elseif command == "shot stop" then
    ns.Demo:Stop()
  elseif command:match("^shot tour") then
    ns.ScreenshotTour:Run(command:match("^shot tour%s+(%S+)"))
    --@end-do-not-package@
  else
    ns.Browser:Toggle()
  end
end
