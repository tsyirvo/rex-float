-- Floats: each one is a command a key opens in a floating terminal, in the
-- directory of the focused pane. Copy this file to
-- ~/.config/rex/floats-config.lua and load it from init.lua:
--
--   require("floats").setup{ floats = require("floats-config") }
--
-- Fields:
--   name     Required. Lowercase letters, digits and underscores. The action
--            is floats_<name>.
--   title    The name shown in the command palette. Defaults to name.
--   key      The key that opens and closes the float, such as "cmd+shift+t".
--            Leave it out to bind floats_<name> yourself.
--   command  A string runs with sh -c. A list is the program and its
--            arguments. Leave it out for a plain shell.
--   cwd      "pane" (the default): the focused pane's directory.
--            "git": the root of the focused pane's git repository.
--   hold     When to keep the float open after the command ends, until a key
--            is pressed: "error" (the default), "always" or "never". Needs a
--            command.
--   bounds   { x, y, width, height } as fractions of the window. Defaults to
--            the bounds given to setup.

return {
  {
    name    = "diff",
    title   = "Diff",
    key     = "cmd+shift+t",
    command = "tuicr",
    cwd     = "git",
  },
  {
    name    = "lazygit",
    title   = "Lazygit",
    key     = "cmd+shift+g",
    command = { "lazygit" },
    cwd     = "git",
    bounds  = { 0.05, 0.05, 0.9, 0.9 },
  },
}
