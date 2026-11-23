local addon = require("spec.helpers.addon")

-- Loads UI/Tooltips.lua against a fake GameTooltip owned by `owner`; returns ns and the tooltip.
local function load(owner)
  local tooltip = { refreshed = 0 }
  function tooltip.IsShown()
    return true
  end
  function tooltip.GetOwner()
    return owner
  end
  function tooltip.GetPrimaryTooltipData()
    return { type = 1 }
  end
  function tooltip:RefreshData()
    self.refreshed = self.refreshed + 1
  end
  local env = setmetatable({ GameTooltip = tooltip, Enum = { TooltipDataType = { Spell = 1 } } }, { __index = _G })
  local ns = { L = {}, db = { settings = { tooltipGame = "shift", tooltipPicker = "shift" } } }
  local chunk = assert(loadfile(addon.root .. "/UI/Tooltips.lua"))
  setfenv(chunk, env)
  chunk("Iconic", ns)
  return ns, tooltip
end

describe("OnModifierChanged", function()
  it("redraws the tooltip of an Iconic button", function()
    local entered = 0
    local button = { iconicButton = true }
    function button.GetScript()
      return function()
        entered = entered + 1
      end
    end
    local ns = load(button)
    ns.OnModifierChanged()
    assert.are.equal(1, entered)
  end)

  it("never rebuilds a game tooltip", function()
    local ns, tooltip = load({})
    ns.OnModifierChanged()
    assert.are.equal(0, tooltip.refreshed)
  end)
end)
