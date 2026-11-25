local addon = require("spec.helpers.addon")

-- UI files build frames, so they are only checked to load without errors against a catch-all fake API.
describe("UI files", function()
  it("load without errors", function()
    local dummy = {}
    setmetatable(dummy, {
      __index = function()
        return dummy
      end,
      __call = function()
        return dummy
      end,
    })
    local env = setmetatable({ SlashCmdList = {} }, {
      __index = function(_, key)
        local real = rawget(_G, key)
        if real ~= nil then
          return real
        end
        return dummy
      end,
    })
    local ns = {}
    for _, file in ipairs(addon.tocFiles(true)) do
      local chunk = assert(loadfile(addon.root .. "/" .. file))
      setfenv(chunk, env)
      chunk("Iconic", ns)
    end
    assert.is_function(env.Iconic.OpenPicker)
    assert.is_function(env.Iconic.RegisterPicker)
    assert.is_function(env.SlashCmdList.ICONIC)
  end)
end)

describe("Picker integrations", function()
  local function loadPickers()
    local dummy = {}
    setmetatable(dummy, {
      __index = function()
        return dummy
      end,
      __call = function()
        return dummy
      end,
    })
    local env = setmetatable({}, {
      __index = function(_, key)
        local real = rawget(_G, key)
        if real ~= nil then
          return real
        end
        return dummy
      end,
    })
    local ns = { L = {} }
    local chunk = assert(loadfile(addon.root .. "/UI/Pickers.lua"))
    setfenv(chunk, env)
    chunk("Iconic", ns)
    ns.db = { disabledIntegrations = {} }
    return ns.Pickers, ns.db
  end

  it("skip the pickers of a turned-off integration until it is turned on", function()
    local Pickers, db = loadPickers()
    local looked = 0
    Pickers.AddAdapter({
      addon = "Some",
      integration = { id = "Some", name = "Some", addons = { "Some" } },
      frames = function()
        looked = looked + 1
        return {}
      end,
    })
    db.disabledIntegrations.Some = true
    Pickers.OnAddonLoaded("Some")
    assert.are.equal(0, looked)
    Pickers.SetIntegrationEnabled("Some", true)
    assert.is_nil(db.disabledIntegrations.Some)
    assert.are.equal(1, looked)
    Pickers.SetIntegrationEnabled("Some", false)
    assert.is_true(db.disabledIntegrations.Some)
  end)

  it("list each integration once", function()
    local Pickers = loadPickers()
    local shared = { id = "Shared", name = "Shared", addons = { "Shared" } }
    for _ = 1, 3 do
      Pickers.AddAdapter({
        integration = shared,
        frames = function()
          return {}
        end,
      })
    end
    Pickers.AddAdapter({
      frames = function()
        return {}
      end,
    })
    assert.are.same({ shared }, Pickers.Integrations())
  end)
end)
