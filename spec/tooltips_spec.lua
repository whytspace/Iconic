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
  local frame = { SetScript = function() end, RegisterEvent = function() end }
  local env = setmetatable({
    GameTooltip = tooltip,
    Enum = { TooltipDataType = { Spell = 1 } },
    CreateFrame = function()
      return frame
    end,
  }, { __index = _G })
  local ns = { L = {}, db = { settings = { tooltipGame = "shift", tooltipPicker = "shift" } } }
  local chunk = assert(loadfile(addon.root .. "/UI/Tooltips.lua"))
  setfenv(chunk, env)
  chunk("Iconic", ns)
  return ns, tooltip
end

describe("Tooltips.WatchModifiers", function()
  local ns, tooltip, env, frame, owned, shift

  before_each(function()
    owned, shift = true, false
    ns, tooltip = load({})
    function tooltip.IsOwned()
      return owned
    end
  end)

  -- Loads with fake key state and a frame whose OnUpdate the test runs by hand.
  local function setup()
    frame = {}
    function frame.SetScript(self, _, fn)
      self.onUpdate = fn
    end
    env = getfenv(ns.Tooltips.WatchModifiers)
    env.CreateFrame = function()
      return frame
    end
    env.IsShiftKeyDown = function()
      return shift
    end
    env.IsControlKeyDown = function()
      return false
    end
    env.IsAltKeyDown = function()
      return false
    end
  end

  it("redraws an Iconic tooltip when a modifier changes, then stops with the tooltip", function()
    setup()
    local redrawn = 0
    ns.Tooltips.WatchModifiers({}, function()
      redrawn = redrawn + 1
    end)
    frame:onUpdate()
    assert.are.equal(0, redrawn)
    shift = true
    frame:onUpdate()
    assert.are.equal(1, redrawn)
    owned = false
    frame:onUpdate()
    assert.is_nil(frame.onUpdate)
  end)

  it("never rebuilds a game tooltip", function()
    setup()
    ns.Tooltips.WatchModifiers({}, function() end)
    shift = true
    frame:onUpdate()
    assert.are.equal(0, tooltip.refreshed)
  end)
end)
