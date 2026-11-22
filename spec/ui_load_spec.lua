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
    for line in io.lines(addon.root .. "/Iconic.toc") do
      line = line:gsub("%s+$", "")
      if line:match("%.lua$") then
        local chunk = assert(loadfile(addon.root .. "/" .. line))
        setfenv(chunk, env)
        chunk("Iconic", ns)
      end
    end
    assert.is_function(env.Iconic.OpenPicker)
    assert.is_function(env.Iconic.RegisterPicker)
    assert.is_function(env.SlashCmdList.ICONIC)
  end)
end)
