-- Omarchyform: open and close the board.
--
-- This file is only read if your own ~/.config/hypr/bindings.lua loads plugin
-- bindings; Omarchy does not pick them up on its own. See the README for the
-- loader snippet, or skip all of this and write the binding yourself.
--
-- Use one or the other. Binding the same key in both places means declaring it
-- twice.
o.bind(
  "SUPER + SHIFT + I",
  "Omarchyform",
  "omarchy-shell shell toggle thepixelgardener.omarchyform"
)
