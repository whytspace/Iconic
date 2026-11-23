local ADDON_NAME, ns = ...

-- Public API for other add-ons, global `Iconic`.
--
-- Textures are what Blizzard's pickers use: a file ID (number) or an "Interface\Icons\..." path.
Iconic = {
  apiVersion = 1,
}

-- Opens Iconic as a standalone picker. opts: title, icon (preselected texture).
-- onChoose(texture) runs when the player confirms with Choose.
function Iconic.OpenPicker(onChoose, opts)
  if type(onChoose) ~= "function" then
    return false, "onChoose must be a function"
  end
  opts = opts or {}
  ns.Browser:Open({ onChoose = onChoose, title = opts.title, icon = opts.icon })
  return true
end

-- Replaces the icon grid of another add-on's picker with Iconic's. `frame` is the picker frame, or a
-- function returning it once it exists. Frames built on IconSelectorPopupFrameTemplate need no adapter;
-- others pass functions overriding Pickers.TemplateAdapter (each gets the frame first):
--   Anchor(frame, viewFrame), GetTextures(frame) -> textures, extras, GetIcon(frame) -> texture,
--   SetIcon(frame, texture, position), IsDragging(frame) -> bool, HideNative(frame),
--   HookStateChanges(frame, onChange), HookConfirm(frame, onConfirm),
--   ShowSelectedState(frame, state) with state "visible", "hidden" or "absent", HookSelected(frame, onClick, onTextReset),
--   GetSuggestions(frame) -> list of textures or { query = text } shown first while the search is empty,
--   HookSuggestionChanges(frame, onChange)
-- Returns true when attached now, false when waiting for the frame.
function Iconic.RegisterPicker(frame, adapter)
  if frame == nil then
    return false, "frame is required"
  end
  if adapter ~= nil and type(adapter) ~= "table" then
    return false, "adapter must be a table"
  end
  return ns.Pickers.Register(frame, adapter)
end
