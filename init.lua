-- Floats: a key opens a command in a floating terminal over the window, in the
-- directory of the focused pane. Quitting the command closes the float.
--
-- Clone into ~/.config/rex/floats, copy floats.example.lua to
-- ~/.config/rex/floats-config.lua, then in ~/.config/rex/init.lua:
--
--   require("floats").setup{ floats = require("floats-config") }
--
-- How the pieces fit:
--   Each float becomes an action, floats_<name>, which shows in the command
--   palette, and setup binds the float's key to it. The action opens a
--   floating layer holding one terminal, which runs the command through
--   run.sh. run.sh holds the terminal open when the command fails, so its
--   error can be read. When run.sh exits the terminal closes, and the layer
--   with it.
--
--   A session shows one float at a time. The float's own key closes it, and
--   another float's key replaces it. A key press finds the open float in
--   session.view by its block's label, so nothing is kept between presses and
--   a reload or a server restart loses no float.

local C = require((... or "floats") .. ".config")

local M = {}

-- Set by release-please on each release.
M.version = "0.1.0" -- x-release-please-version

local SHELL    = "com.superlogical.terminal.shell"
local TERMINAL = "com.superlogical.terminal"

M.options = {
  -- The floats' x, y, width and height, as fractions of the window. A float
  -- can set its own.
  bounds = C.DEFAULT_BOUNDS,
  -- See floats.example.lua.
  floats = {},
}

-- The first mistake setup found in the options. Raising it at load would stop
-- the rest of init.lua, and a log line goes unseen, so the actions report it.
local config_error

-- The sessions where a key press is running. A press waits on Rex calls and
-- on git, and Rex handles other keys meanwhile, so a second press could open
-- a second float.
local busy = {}

local function fail(message)
  error("floats: " .. message, 0)
end

local function check(result, err)
  if result == nil then fail(tostring(err)) end
  return result
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- run.sh, beside this file. Found once, at load. nil and the reason when it
-- isn't there.
local function find_runner()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  local dir = src:match("^(/.*)/[^/]*$")
  if dir == nil then return nil, "can't tell where Floats is installed, from " .. src end
  local path = dir .. "/run.sh"
  local file = io.open(path, "r")
  if file == nil then return nil, "run.sh is missing from " .. dir end
  file:close()
  return path
end

local runner, runner_error = find_runner()

-- The directory a terminal is in: its foreground program's, else its shell's,
-- else what it last reported. nil rather than a guess.
local function cwd_of(block_id)
  local p = rex.block.call(TERMINAL, "process", { block_id = block_id })
  if p then
    local cwd = (p.foreground or {}).cwd or (p.child or {}).cwd
    if cwd and cwd ~= "" then return cwd end
  end
  local pwd = rex.block.call(TERMINAL, "pwd", { block_id = block_id })
  return pwd and C.path_of(pwd.pwd)
end

local function git_root(dir)
  local r = rex.exec({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { timeout = 5 })
  if r and r.ok then return trim(r.stdout) end
  return nil
end

local function toggle(ctx, f)
  if config_error then fail("fix the setup in init.lua: " .. config_error) end
  if runner == nil then fail(runner_error) end

  local view = check(rex.session.view{})
  local plan = C.plan(view, f.name)

  local cwd
  if plan.open then
    -- Read before closing the float shown now: it may be the focused pane.
    local block_id = ctx.block_id or C.focused_block(view)
    cwd = block_id and cwd_of(block_id)
    if cwd == nil then fail("can't tell which directory the focused pane is in") end
    if f.cwd == "git" then
      local root = git_root(cwd)
      if root == nil then fail("not a git repository: " .. cwd) end
      cwd = root
    end
  end

  for _, layer_id in ipairs(plan.close) do
    -- It may have closed since the view was read, so a failure is fine.
    rex.session.close_layer{ layer_id = layer_id }
  end
  if not plan.open then return end

  check(rex.session.new_layer{
    bounds = f.bounds or M.options.bounds,
    focus  = true,
    layout = { block = { flavor = SHELL, label = C.label(f.name), options = C.terminal(f, cwd, runner) } },
  })
end

-- One press at a time in each session. A press while one runs is dropped.
local function run_once(ctx, fn)
  local session = ctx.session_id or ""
  if busy[session] then return end
  busy[session] = true
  local ok, err = pcall(fn)
  busy[session] = nil
  if not ok then error(err, 0) end
end

local function define(f)
  local action = "floats_" .. f.name
  rex.action{
    name        = action,
    title       = "Floats: " .. (f.title or f.name),
    description = "Open " .. (f.title or f.name) .. " in a floating terminal, or close it when it is open.",
    category    = "Floats",
    keywords    = "float floating popup overlay " .. f.name,
    run = function(ctx) run_once(ctx, function() toggle(ctx, f) end) end,
  }
  -- Rex reports a key it can't read, and skips the binding.
  if type(f.key) == "string" then rex.bind(f.key, action) end
end

-- For a float too broken to get its own action, so that its key still reports
-- the mistake rather than doing nothing.
local function define_error_action()
  rex.action{
    name        = "floats_setup_error",
    title       = "Floats: Show Setup Error",
    description = "Report the mistake in the Floats setup in init.lua.",
    category    = "Floats",
    run = function() fail("fix the setup in init.lua: " .. tostring(config_error)) end,
  }
end

function M.setup(opts)
  opts = opts or {}
  config_error = C.check(opts)
  if config_error then
    rex.log("error", "floats: " .. config_error)
  else
    for k, v in pairs(opts) do M.options[k] = v end
  end

  -- With a mistake, the floats that are whole enough still get their action
  -- and key, so pressing one reports the mistake. A float with no usable name
  -- gets its key bound to floats_setup_error.
  local floats = type(opts.floats) == "table" and opts.floats or {}
  local made, orphan_keys = {}, {}
  for _, f in ipairs(floats) do
    if type(f) == "table" and C.valid_name(f.name) and not made[f.name] then
      made[f.name] = true
      define(f)
    elseif type(f) == "table" and type(f.key) == "string" and f.key ~= "" then
      orphan_keys[#orphan_keys + 1] = f.key
    end
  end
  if #orphan_keys > 0 then
    define_error_action()
    for _, key in ipairs(orphan_keys) do rex.bind(key, "floats_setup_error") end
  end

  return M
end

return M
