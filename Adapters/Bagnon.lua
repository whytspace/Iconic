local ADDON_NAME, ns = ...

local Pickers = ns.Pickers

-- Bagnon's pickers, all built on IconSelectorPopupFrameTemplate, each in its own load-on-demand add-on.
local function templateFrame(popup)
  return popup and popup.IconSelector and { popup } or {}
end

-- Bank tab settings menu (retail only), a copy of Blizzard's.
Pickers.AddAdapter({
  addon = "Bagnon_Bank",
  overrides = Pickers.BANK_OVERRIDES,
  frames = function()
    local bag = Bagnon and Bagnon.BankBag
    return templateFrame(bag and bag.Settings)
  end,
})

-- Guild bank tab popup.
Pickers.AddAdapter({
  addon = "Bagnon_GuildBank",
  overrides = Pickers.GUILD_BANK_OVERRIDES,
  frames = function()
    return templateFrame(BagBrotherGuildTabEditPopup)
  end,
})

local footers = {}

-- The filter editor's Delete and Share buttons, shown for custom filters only, share the footer's row.
local function placeFooter(popup)
  local footer, box = footers[popup], popup.BorderBox
  local share = box.ShareButton
  if not footer or not share then
    return
  end
  footer.compact = share:IsShown()
  footer:ClearAllPoints()
  if footer.compact then
    footer:SetPoint("BOTTOMLEFT", share, "BOTTOMRIGHT", 12, -1)
  else
    footer:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 16, 12)
  end
  footer:SetPoint("TOPRIGHT", box.OkayButton, "TOPLEFT", -12, -1)
end

-- Filter editor: Display fills it after showing it.
Pickers.AddAdapter({
  addon = "Bagnon_Config",
  overrides = {
    AnchorFooter = function(popup, footer)
      Pickers.TemplateAdapter.AnchorFooter(popup, footer)
      footers[popup] = footer
      placeFooter(popup)
    end,
    HookRefill = function(popup, onRefill)
      hooksecurefunc(popup, "Display", function()
        placeFooter(popup)
        onRefill()
      end)
    end,
  },
  frames = function()
    return templateFrame(Bagnon and Bagnon.RuleEdit)
  end,
})
