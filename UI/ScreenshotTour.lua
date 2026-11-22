local ADDON_NAME, ns = ...

-- Maintainer tool behind /iconic shot tour: stages each README view, captures it, then restores the UI.
local Tour = {}
ns.ScreenshotTour = Tour

-- Lets a search (debounced in View) and the grid layout settle before capturing.
local SETTLE = 0.8
-- Selected in the browser view; Phoenix Hatchling, found by "egg".
local BROWSER_ICON = 134373

local function chat(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Iconic:|r " .. message)
end

-- Set by Run: aborts the tour and restores the UI when a step errors.
local fail

local function after(delay, fn)
  C_Timer.After(delay, function()
    xpcall(fn, fail)
  end)
end

-- Search, filters and grouping for one view; nil keeps the current value.
local function stage(view, query, filters, groupBy)
  ns.db.groupBy = groupBy
  view.filters = filters
  view.search:SetText(query)
  view.search:ClearFocus()
  view:UpdateGroupText()
  view:Refresh()
end

-- The button of the macro's current icon.
local function selectedButton(view)
  local found
  view.scrollBox:ForEachFrame(function(frame)
    for _, button in ipairs(frame.buttons or {}) do
      if button:IsShown() and view.data.index.key[button.row] == view.selectedKey then
        found = button
      end
    end
  end)
  return found
end

local function openMacroPicker()
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_MacroUI")
  end
  if not MacroFrame then
    return nil
  end
  ShowUIPanel(MacroFrame)
  -- Character macros, first one selected; a new macro when there are none.
  MacroFrame:ChangeTab(2)
  local _, characterMacros = GetNumMacros()
  if characterMacros > 0 then
    MacroEditButton:Click()
  else
    MacroNewButton:Click()
  end
  local state = ns.Pickers.attached[MacroPopupFrame]
  return state and state.view
end

local function closeMacroPicker()
  if MacroPopupFrame and MacroPopupFrame:IsShown() then
    MacroPopupFrame:CancelButton_OnClick()
  end
  if MacroFrame then
    HideUIPanel(MacroFrame)
  end
end

local VIEWS = {
  {
    name = "picker",
    run = function(capture)
      local view = openMacroPicker()
      if not view then
        return capture(nil)
      end
      local query, filters = view.search:GetText(), view.filters
      stage(view, "focus mark", {}, "none")
      after(SETTLE, function()
        local button = selectedButton(view)
        if button then
          view:ShowTooltip(button)
        end
        capture(MacroFrame, function()
          GameTooltip:Hide()
          view.filters = filters
          view.search:SetText(query)
          closeMacroPicker()
        end)
      end)
    end,
  },
  {
    name = "colours",
    run = function(capture)
      ns.Browser:Open()
      local view = ns.Browser.view
      stage(view, "gem", { color = { green = true } }, "none")
      after(SETTLE, function()
        view.filter:OpenMenu()
        after(0.1, function()
          if view.colorMenu then
            view.colorMenu:ForceOpenSubmenu()
          end
          capture(ns.Browser.frame, function()
            view.filter:CloseMenu()
          end)
        end)
      end)
    end,
  },
  {
    name = "browser",
    run = function(capture)
      ns.Browser:Open()
      local view = ns.Browser.view
      stage(view, "egg", {}, "color")
      after(SETTLE, function()
        ns.Browser:SetSelected(BROWSER_ICON)
        capture(ns.Browser.frame)
      end)
    end,
  },
}

Tour.VIEWS = VIEWS

local function snapshot()
  local view = ns.Browser.view
  return {
    groupBy = ns.db.groupBy,
    tooltipPicker = ns.db.settings.tooltipPicker,
    browserShown = ns.Browser.frame and ns.Browser.frame:IsShown(),
    macroShown = MacroFrame and MacroFrame:IsShown(),
    query = view and view.search:GetText(),
    filters = view and view.filters,
    selected = ns.Browser.selected,
  }
end

local function restore(saved)
  if not saved.macroShown then
    closeMacroPicker()
  end
  ns.db.groupBy = saved.groupBy
  ns.db.settings.tooltipPicker = saved.tooltipPicker
  for _, state in pairs(ns.Pickers.attached) do
    if state.view then
      state.view:UpdateGroupText()
    end
  end
  local view = ns.Browser.view
  if view then
    view.filters = saved.filters or {}
    view.search:SetText(saved.query or "")
    view:UpdateGroupText()
    view:Refresh()
    ns.Browser:SetSelected(saved.selected)
  end
  if ns.Browser.frame and not saved.browserShown then
    ns.Browser.frame:Hide()
  end
end

-- Runs the views in order; `only` limits it to one view by name.
function Tour:Run(only)
  if self.running then
    chat("the screenshot tour is already running.")
    return
  end
  self.running = true
  local saved = snapshot()
  local cleanup
  local function finish()
    if cleanup then
      pcall(cleanup)
      cleanup = nil
    end
    restore(saved)
    self.running = false
  end
  fail = function(err)
    chat("screenshot tour stopped: " .. tostring(err))
    finish()
  end
  -- The README shows icon IDs in tooltips.
  ns.db.settings.tooltipPicker = "always"

  local queue = {}
  for _, view in ipairs(VIEWS) do
    if not only or view.name == only then
      queue[#queue + 1] = view
    end
  end

  local index = 0
  local function nextView()
    index = index + 1
    local view = queue[index]
    if not view then
      finish()
      chat(("captured %d views."):format(#queue))
      return
    end
    view.run(function(target, viewCleanup)
      cleanup = viewCleanup
      if not target then
        chat("skipped " .. view.name .. ".")
        return nextView()
      end
      ns.Screenshot:Capture(target, function(err)
        if err then
          return fail(err)
        end
        if cleanup then
          cleanup()
          cleanup = nil
        end
        after(SETTLE, nextView)
      end)
    end)
  end
  after(0, nextView)
end
