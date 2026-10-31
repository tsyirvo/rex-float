-- Floats' options: the checks setup runs on them, the terminal each float
-- opens, and what a key press does to the session. Nothing here calls Rex, so
-- tests/config_test.lua runs it outside Rex.

local M = {}

-- x, y, width, height, as fractions of the window.
M.DEFAULT_BOUNDS = { 0.1, 0.1, 0.8, 0.8 }

local OPTIONS = { bounds = true, floats = true }
local FIELDS  = { name = true, title = true, key = true, command = true, cwd = true, bounds = true, hold = true }
local CWDS    = { pane = true, git = true }
local HOLDS   = { error = true, always = true, never = true }

-- Rex's rule for action names.
function M.valid_name(name)
  return type(name) == "string" and name:match("^[a-z0-9_]+$") ~= nil
end

-- A key as Rex reads it, so that "cmd+shift+t" and "SHIFT+cmd+t" compare
-- equal: lowercase, with each chord's modifiers sorted. A sequence's chords
-- keep their order.
function M.normalize_key(key)
  local mode, rest = key:lower():match("^([^/]*/)(.*)$")
  if mode == nil then mode, rest = "", key:lower() end
  local chords = {}
  for chord in (rest .. ">"):gmatch("(.-)>") do
    -- A trailing "++" is the + key itself.
    local last = chord:match("%+(%+)$") or chord:match("[^+]*$")
    if last == "" then last = "+" end
    local mods = {}
    for m in chord:sub(1, #chord - #last):gmatch("[^+]+") do mods[#mods + 1] = m end
    table.sort(mods)
    mods[#mods + 1] = last
    chords[#chords + 1] = table.concat(mods, "+")
  end
  return mode .. table.concat(chords, ">")
end

local function is_list(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

local function check_bounds(b, at)
  if type(b) ~= "table" or #b ~= 4 then return at .. ": expected { x, y, width, height }" end
  for i = 1, 4 do
    if type(b[i]) ~= "number" or b[i] < 0 or b[i] > 1 then
      return at .. "[" .. i .. "]: expected a fraction of the window, 0 to 1"
    end
  end
  if b[3] == 0 or b[4] == 0 then return at .. ": the width and height must be more than 0" end
  if b[1] + b[3] > 1 or b[2] + b[4] > 1 then return at .. ": the float must fit inside the window" end
end

local function check_command(c, at)
  if c == nil then return end
  if type(c) == "string" then
    if c:match("^%s*$") then return at .. ": expected a command, got an empty string" end
    return
  end
  if not is_list(c) or #c == 0 then return at .. ": expected a string or a list of strings" end
  for i, arg in ipairs(c) do
    if type(arg) ~= "string" then return at .. "[" .. i .. "]: expected a string" end
  end
end

local function check_float(f, at, names, keys)
  if type(f) ~= "table" then return at .. ": expected a table" end
  for k in pairs(f) do
    if not FIELDS[k] then return at .. ": unknown field " .. tostring(k) end
  end
  if not M.valid_name(f.name) then
    return at .. ".name: expected lowercase letters, digits and underscores, got " .. tostring(f.name)
  end
  if names[f.name] then return at .. ".name: " .. f.name .. " is also " .. names[f.name] end
  names[f.name] = at
  if f.title ~= nil and type(f.title) ~= "string" then return at .. ".title: expected a string" end
  if f.key ~= nil then
    if type(f.key) ~= "string" or f.key == "" then return at .. ".key: expected a key, such as \"cmd+shift+t\"" end
    local key = M.normalize_key(f.key)
    if keys[key] then return at .. ".key: " .. f.key .. " is also the key of " .. keys[key] end
    keys[key] = at
  end
  local err = check_command(f.command, at .. ".command")
  if err then return err end
  if f.cwd ~= nil and not CWDS[f.cwd] then
    return at .. '.cwd: expected "pane" or "git", got ' .. tostring(f.cwd)
  end
  if f.hold ~= nil and not HOLDS[f.hold] then
    return at .. '.hold: expected "error", "always" or "never", got ' .. tostring(f.hold)
  end
  if f.hold ~= nil and f.command == nil then
    return at .. ".hold: only applies to a command, and this float has none"
  end
  if f.bounds ~= nil then return check_bounds(f.bounds, at .. ".bounds") end
end

-- nil when the options are fine, else the first mistake, with its place.
function M.check(opts)
  if type(opts) ~= "table" then return "expected a table of options" end
  for k in pairs(opts) do
    if not OPTIONS[k] then return "unknown option " .. tostring(k) end
  end
  if opts.bounds ~= nil then
    local err = check_bounds(opts.bounds, "bounds")
    if err then return err end
  end
  if opts.floats == nil then return end
  if not is_list(opts.floats) then return "floats: expected a list of floats" end
  local names, keys = {}, {}
  for i, f in ipairs(opts.floats) do
    local err = check_float(f, "floats[" .. i .. "]", names, keys)
    if err then return err end
  end
end

-- The terminal options for a float that starts in cwd. runner is run.sh's
-- path. A string command runs with sh -c, a list as it is, each through
-- run.sh, which holds the float open when the command fails. No command
-- gives a plain shell.
function M.terminal(f, cwd, runner)
  local options = { cwd = cwd }
  local argv = f.command
  if type(argv) == "string" then argv = { "sh", "-c", argv } end
  if argv == nil then return options end

  local command = { "bash", runner, f.hold or "error", f.name }
  for _, arg in ipairs(argv) do command[#command + 1] = arg end
  options.command = command
  -- run.sh decides when to hold the float open. Rex would otherwise also hold
  -- it after a quick failure, whatever hold says.
  options.exit = { quick_exit_threshold_ms = 0 }
  return options
end

-- The label on a float's block. It is how a key press finds the float again,
-- so a float opened before a reload or a server restart is still found.
local LABEL = "floats:"

function M.label(name)
  return LABEL .. name
end

-- The floats in a session.view result: { name, layer_id, window_id } each.
local function floats_in(view)
  local found = {}
  for _, w in ipairs(view.windows or {}) do
    for _, l in ipairs(w.layers or {}) do
      if l.kind ~= "tiled" then
        for _, b in ipairs(l.blocks or {}) do
          local label = b.label or ""
          if label:sub(1, #LABEL) == LABEL then
            found[#found + 1] = { name = label:sub(#LABEL + 1), layer_id = l.layer_id, window_id = w.window_id }
            break
          end
        end
      end
    end
  end
  return found
end

-- What a press of float name's key does, given session.view: the layers to
-- close, and whether to open the float. The float's key closes it when it is
-- in the active window. Otherwise every float in the session closes, so a
-- session never shows more than one, and the float opens in the active window.
function M.plan(view, name)
  local close, toggled_off = {}, false
  for _, f in ipairs(floats_in(view)) do
    close[#close + 1] = f.layer_id
    if f.name == name and f.window_id == view.active_window_id then toggled_off = true end
  end
  return { close = close, open = not toggled_off }
end

-- The focused block of the active window, for an action run with no block,
-- such as from the CLI.
function M.focused_block(view)
  for _, w in ipairs(view.windows or {}) do
    if w.window_id == view.active_window_id then return w.focused_block_id end
  end
  return nil
end

-- A directory as the terminal's pwd reports it, as a path. A shell that uses
-- OSC 7 reports a file://host/path URL, with its path percent-encoded.
function M.path_of(pwd)
  if pwd == nil or pwd == "" then return nil end
  local path = pwd:match("^file://[^/]*(/.*)$")
  if path == nil then return pwd end
  return (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

return M
