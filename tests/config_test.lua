-- Tests for config.lua and run.sh. Run from the repo root with Lua 5.1:
--
--   lua tests/config_test.lua

package.path = "./?.lua;" .. package.path
local C = require("config")

local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function has(text, part)
  if text == nil or not text:find(part, 1, true) then
    error("expected a message with " .. part .. ", got " .. tostring(text), 2)
  end
end

local function mistake(opts)
  local err = C.check(opts)
  if err == nil then error("expected a mistake", 2) end
  return err
end

local function one(f) return { floats = { f } } end

-- check

test("the example floats pass", function()
  eq(C.check({ floats = dofile("floats.example.lua") }), nil)
  eq(C.check({}), nil)
  eq(C.check({ floats = {} }), nil)
  eq(C.check({ bounds = { 0, 0, 1, 1 } }), nil)
end)

test("an unknown option or field is a mistake", function()
  has(mistake({ float = {} }), "unknown option float")
  has(mistake(one({ name = "x", comand = "ls" })), "floats[1]: unknown field comand")
end)

test("floats must be a list of tables", function()
  has(mistake({ floats = "x" }), "floats: expected a list")
  has(mistake({ floats = { diff = { name = "diff" } } }), "floats: expected a list")
  has(mistake({ floats = { "diff" } }), "floats[1]: expected a table")
end)

test("a name is required and must suit an action name", function()
  has(mistake(one({ command = "ls" })), "floats[1].name: expected lowercase")
  has(mistake(one({ name = "Lazy-Git" })), "floats[1].name: expected lowercase")
  eq(C.valid_name("lazy_git2"), true)
end)

test("names and keys are unique", function()
  has(mistake({ floats = { { name = "a" }, { name = "a" } } }), "floats[2].name: a is also floats[1]")
  has(mistake({ floats = { { name = "a", key = "cmd+g" }, { name = "b", key = "CMD+G" } } }),
    "floats[2].key: CMD+G is also the key of floats[1]")
  has(mistake({ floats = { { name = "a", key = "cmd+shift+t" }, { name = "b", key = "shift+cmd+t" } } }),
    "floats[2].key: shift+cmd+t is also the key of floats[1]")
end)

test("keys compare with their modifiers in any order", function()
  eq(C.normalize_key("Shift+Cmd+T"), "cmd+shift+t")
  eq(C.normalize_key("ctrl+b>shift+c"), "ctrl+b>shift+c")
  eq(C.normalize_key("resize/shift+left"), "resize/shift+left")
  eq(C.normalize_key("cmd++"), "cmd++")
  eq(C.normalize_key("+"), "+")
end)

test("command is a string or a list of strings", function()
  has(mistake(one({ name = "x", command = "  " })), "floats[1].command: expected a command")
  has(mistake(one({ name = "x", command = {} })), "floats[1].command: expected a string or a list")
  has(mistake(one({ name = "x", command = { "a", 2 } })), "floats[1].command[2]: expected a string")
  has(mistake(one({ name = "x", command = 3 })), "floats[1].command: expected a string or a list")
end)

test("cwd and hold take their known values", function()
  has(mistake(one({ name = "x", cwd = "repo" })), 'floats[1].cwd: expected "pane" or "git", got repo')
  has(mistake(one({ name = "x", command = "ls", hold = true })), 'floats[1].hold: expected "error", "always" or "never"')
end)

test("hold needs a command", function()
  has(mistake(one({ name = "x", hold = "always" })), "floats[1].hold: only applies to a command")
  eq(C.check(one({ name = "x", command = "ls", hold = "always" })), nil)
end)

test("bounds are four fractions that fit the window", function()
  has(mistake({ bounds = { 0.1, 0.1, 0.8 } }), "bounds: expected { x, y, width, height }")
  has(mistake({ bounds = { 0.1, 0.1, 1.5, 0.5 } }), "bounds[3]: expected a fraction")
  has(mistake({ bounds = { 0.1, 0.1, 0, 0.5 } }), "bounds: the width and height must be more than 0")
  has(mistake(one({ name = "x", bounds = { 0.5, 0.1, 0.6, 0.5 } })), "floats[1].bounds: the float must fit")
end)

-- terminal

test("a string command runs with sh -c through run.sh", function()
  local o = C.terminal({ name = "diff", command = "tuicr -w" }, "/repo", "/f/run.sh")
  eq(o.cwd, "/repo")
  eq(table.concat(o.command, "|"), "bash|/f/run.sh|error|diff|sh|-c|tuicr -w")
  eq(o.exit.quick_exit_threshold_ms, 0, "run.sh, not Rex, holds the float")
end)

test("a list command keeps its arguments, and hold is passed", function()
  local o = C.terminal({ name = "lg", command = { "lazygit", "-p", "a b" }, hold = "always" }, "/r", "/f/run.sh")
  eq(table.concat(o.command, "|"), "bash|/f/run.sh|always|lg|lazygit|-p|a b")
end)

test("no command gives a plain shell", function()
  local o = C.terminal({ name = "sh" }, "/r", "/f/run.sh")
  eq(o.command, nil)
  eq(o.exit, nil)
  eq(o.cwd, "/r")
end)

-- plan

local function view(active, windows)
  local v = { active_window_id = active, windows = {} }
  for id, floats in pairs(windows) do
    local layers = { { layer_id = id .. "-tiled", kind = "tiled", blocks = { { block_id = "b", label = "shell" } } } }
    for _, name in ipairs(floats) do
      local label = name:find(":") and name or C.label(name)
      layers[#layers + 1] = { layer_id = id .. "-" .. name, kind = "floating", blocks = { { block_id = "f", label = label } } }
    end
    v.windows[#v.windows + 1] = { window_id = id, focused_block_id = id .. "-focus", layers = layers }
  end
  return v
end

test("plan opens a float when none is shown", function()
  local p = C.plan(view("w1", { w1 = {} }), "diff")
  eq(p.open, true)
  eq(#p.close, 0)
end)

test("plan closes the float when its key is pressed in its window", function()
  local p = C.plan(view("w1", { w1 = { "diff" } }), "diff")
  eq(p.open, false)
  eq(table.concat(p.close, ","), "w1-diff")
end)

test("plan replaces another float", function()
  local p = C.plan(view("w1", { w1 = { "lazygit" } }), "diff")
  eq(p.open, true)
  eq(table.concat(p.close, ","), "w1-lazygit")
end)

test("plan moves a float from another window to the active one", function()
  local p = C.plan(view("w2", { w1 = { "diff" }, w2 = {} }), "diff")
  eq(p.open, true)
  eq(table.concat(p.close, ","), "w1-diff")
end)

test("plan closes every float, so a session keeps one", function()
  local p = C.plan(view("w1", { w1 = { "diff", "lazygit" } }), "diff")
  eq(p.open, false)
  eq(#p.close, 2)
end)

test("plan leaves floating layers that aren't floats", function()
  local p = C.plan(view("w1", { w1 = { "other:thing" } }), "diff")
  eq(p.open, true)
  eq(#p.close, 0)
end)

test("focused_block reads the active window", function()
  eq(C.focused_block(view("w1", { w1 = {} })), "w1-focus")
  eq(C.focused_block({ windows = {} }), nil)
end)

-- path_of

test("path_of turns an OSC 7 URL into a path", function()
  eq(C.path_of("file://Mac.local/Users/me/my%20repo"), "/Users/me/my repo")
  eq(C.path_of("file:///tmp"), "/tmp")
  eq(C.path_of("/plain/path"), "/plain/path")
  eq(C.path_of(""), nil)
  eq(C.path_of(nil), nil)
end)

-- run.sh. A key is piped in for the cases that wait for one.

local function run(args)
  local cmd = "echo x | bash run.sh " .. args .. " >/dev/null 2>&1"
  local status = os.execute(cmd)
  -- Lua 5.1 returns the raw wait status.
  return status > 255 and status / 256 or status
end

test("run.sh passes the command's status through", function()
  eq(run("error t true"), 0)
  eq(run("error t sh -c 'exit 3'"), 3)
  eq(run("always t true"), 0)
  eq(run("never t false"), 1)
  eq(run("error t no-such-command-floats"), 127)
end)

test("run.sh without a command is a usage error", function()
  eq(run("error t"), 2)
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
