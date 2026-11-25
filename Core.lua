local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

ns.TOOLTIP_MODES = { "always", "shift", "ctrl", "alt", "never" }

ns.DEFAULTS = {
  settings = {
    tooltipPicker = "always",
    tooltipNames = "shift",
    tooltipGame = "shift",
    showSuggested = true,
    showRecent = true,
  },
  groupBy = "none",
  recent = {},
  -- groupBy -> section key -> true
  collapsed = {},
  -- Integration id -> true for the other add-ons' pickers the player turned off; all others are on.
  disabledIntegrations = {},
}

ns.MAX_RECENT = 24

-- Equipment slots GetInventoryItemTexture knows.
ns.EQUIPPED_SLOTS = 19

local function fill(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      fill(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

-- Returns the saved variables table with missing defaults filled in.
function ns.InitDB(saved)
  ns.db = fill(type(saved) == "table" and saved or {}, ns.DEFAULTS)
  return ns.db
end

-- Moves `texture` to the front of the saved recent icons.
function ns.AddRecent(texture)
  if ns.db and texture then
    ns.Catalog.AddRecent(ns.db.recent, texture)
  end
end
