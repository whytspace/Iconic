local ADDON_NAME, ns = ...

local L = ns.L

-- Whether a tooltip setting ("always", "shift", "ctrl", "alt", "never") shows the icon ID right now.
function ns.ShowIconID(mode)
  if mode == "always" then
    return true
  elseif mode == "shift" then
    return IsShiftKeyDown()
  elseif mode == "ctrl" then
    return IsControlKeyDown()
  elseif mode == "alt" then
    return IsAltKeyDown()
  end
  return false
end

-- Icon of the thing a tooltip shows, per tooltip data type.
local ICON_OF = {
  Spell = function(id)
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
  end,
  Item = function(id)
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  end,
  Toy = function(id)
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  end,
  Mount = function(id)
    return C_MountJournal and C_MountJournal.GetMountInfoByID and select(3, C_MountJournal.GetMountInfoByID(id))
  end,
  Currency = function(id)
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    return info and info.iconFileID
  end,
}

local function addIconLine(tooltip, icon)
  local id = type(icon) == "number" and icon or (ns.data and ns.Catalog.ResolveId(ns.data, icon))
  if id then
    tooltip:AddLine(L["Icon ID: %d"]:format(id), 0.5, 0.8, 1)
  end
end

function ns.SetupTooltips()
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
    return
  end
  for typeName, iconOf in pairs(ICON_OF) do
    local dataType = Enum.TooltipDataType[typeName]
    if dataType then
      TooltipDataProcessor.AddTooltipPostCall(dataType, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
          return
        end
        if not (data and data.id and ns.db and ns.ShowIconID(ns.db.settings.tooltipGame)) then
          return
        end
        local ok, icon = pcall(iconOf, data.id)
        if ok and icon then
          addIconLine(tooltip, icon)
        end
      end)
    end
  end
end

-- Re-renders an Iconic button's tooltip so a modifier press shows or hides the icon ID at once.
function ns.OnModifierChanged()
  if not GameTooltip:IsShown() then
    return
  end
  local owner = GameTooltip:GetOwner()
  if owner and owner.iconicButton then
    owner:GetScript("OnEnter")(owner)
  end
end
