local ADDON_NAME, ns = ...

local L = ns.L

local LOGO = "Interface\\AddOns\\Iconic\\Assets\\logo"

local function metadata(key)
  return C_AddOns.GetAddOnMetadata(ADDON_NAME, key)
end

local function label(parent, font, text, anchor, offset)
  local fontString = parent:CreateFontString(nil, "ARTWORK", font)
  fontString:SetPoint("TOP", anchor, "BOTTOM", 0, offset)
  fontString:SetWidth(460)
  fontString:SetJustifyH("CENTER")
  fontString:SetText(text)
  return fontString
end

-- Read-only edit box, so the project URL can be selected and copied.
local function linkBox(parent, url)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(320, 22)
  box:SetAutoFocus(false)
  box:SetText(url)
  box:SetCursorPosition(0)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEditFocusGained", box.HighlightText)
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetText() ~= url then
      self:SetText(url)
      self:HighlightText()
    end
  end)
  return box
end

function ns.CreateAboutPanel()
  local frame = CreateFrame("Frame")

  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetSize(96, 96)
  logo:SetPoint("TOP", frame, "TOP", 0, -48)
  logo:SetTexture(LOGO)

  local title = label(frame, "GameFontNormalHuge", L["Iconic"], logo, -16)
  local tagline = label(frame, "GameFontHighlight", L["A searchable icon picker for World of Warcraft."], title, -8)
  local meta = label(
    frame,
    "GameFontDisableSmall",
    string.format(L["v%s  \194\183  by %s"], metadata("Version"), metadata("Author")),
    tagline,
    -10
  )
  local pitch = label(
    frame,
    "GameFontHighlightSmall",
    L["Iconic replaces the icon grid wherever the game lets you choose an icon. Search by name, description or color, filter by source and class, and find the icon you mean in seconds."],
    meta,
    -22
  )
  local linkLabel = label(frame, "GameFontDisableSmall", L["Project page and bug reports (copy the link):"], pitch, -26)

  local link = linkBox(frame, metadata("X-Website"))
  link:SetPoint("TOP", linkLabel, "BOTTOM", 0, -8)

  return frame
end
