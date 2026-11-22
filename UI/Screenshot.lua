local ADDON_NAME, ns = ...

local L = ns.L

local Shot = {}
ns.Screenshot = Shot

-- Wait for a recolour to render; the client drops a second screenshot taken too soon after the first.
local RENDER_DELAY = 0.5
local SHOT_GAP = 1.5

local function print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Iconic:|r " .. message)
end

-- The browser if open, else the window of an open Blizzard picker (the macro window for macros).
local function findTarget()
  if IconicBrowserFrame and IconicBrowserFrame:IsShown() then
    return IconicBrowserFrame
  end
  for _, entry in ipairs(ns.Pickers.BLIZZARD) do
    local ok, popup = pcall(entry.frame)
    if ok and popup and popup:IsShown() then
      local owner = popup:GetParent()
      return owner and owner ~= UIParent and owner or popup
    end
  end
end

-- A solid backdrop just below the target in its own strata; the target is never restrata'd,
-- as that corrupts Blizzard's macro list.
local function backdrop(target)
  local frame = Shot.backdrop
  if not frame then
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    Shot.backdrop = frame
  end
  frame:SetFrameStrata(target:GetFrameStrata())
  frame:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1))
  return frame
end

-- Menus and tooltips stay visible; they belong in the shot.
local KEEP_STRATA = { FULLSCREEN_DIALOG = true, TOOLTIP = true }

local function topLevel(frame)
  while frame:GetParent() and frame:GetParent() ~= UIParent do
    frame = frame:GetParent()
  end
  return frame
end

-- Fades every other shown UI frame (action bars, minimap, help tips) and returns a restore function.
local function fadeOthers(target)
  local keep = topLevel(target)
  local faded = {}
  for _, child in ipairs({ UIParent:GetChildren() }) do
    pcall(function()
      if
        child ~= keep
        and child ~= Shot.backdrop
        and not (child.IsForbidden and child:IsForbidden())
        and child:IsShown()
        and not KEEP_STRATA[child:GetFrameStrata()]
      then
        local alpha = child:GetAlpha()
        child:SetAlpha(0)
        faded[child] = alpha
      end
    end)
  end
  return function()
    for child, alpha in pairs(faded) do
      pcall(child.SetAlpha, child, alpha)
    end
  end
end

-- Captures the target (default: open browser or picker) on black, then white; onDone(err) runs after.
function Shot:Capture(target, onDone)
  if self.busy then
    return
  end
  target = target or findTarget()
  if not target then
    print(L["Open the icon browser or an icon picker first."])
    return
  end
  if C_CVar.GetCVar("screenshotFormat") ~= "png" then
    C_CVar.SetCVar("screenshotFormat", "png")
  end

  self.busy = true
  local frame = backdrop(target)
  local restore
  local function finish(err)
    frame:Hide()
    if restore then
      restore()
    end
    self.busy = false
    if err then
      print(L["Screenshot failed: %s"]:format(tostring(err)))
    end
    if onDone then
      onDone(err)
    end
  end
  local function step(delay, fn)
    C_Timer.After(delay, function()
      xpcall(fn, finish)
    end)
  end
  local function paint(value)
    frame.texture:SetColorTexture(value, value, value, 1)
    frame:Show()
  end

  restore = fadeOthers(target)
  paint(0)
  step(RENDER_DELAY, function()
    Screenshot()
    step(SHOT_GAP, function()
      paint(1)
      step(RENDER_DELAY, function()
        Screenshot()
        step(RENDER_DELAY, function()
          finish()
        end)
      end)
    end)
  end)
end
