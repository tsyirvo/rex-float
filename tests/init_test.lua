-- Tests for init.lua, against a fake rex that keeps one session in memory. Run
-- from the repo root with Lua 5.1:
--
--   lua tests/init_test.lua

package.path = "./?.lua;" .. package.path
package.preload["floats.config"] = function() return require("config") end

-- init.lua finds run.sh from its own path, which must be absolute.
local INIT = assert(os.getenv("PWD"), "PWD is not set") .. "/init.lua"

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
  if text == nil or not tostring(text):find(part, 1, true) then
    error("expected a message with " .. part .. ", got " .. tostring(text), 2)
  end
end

-- The fake Rex. Each window has a tiled layer with one shell in it. The fake
-- terminal's directories and git roots come from the tables below.
local state

local function fresh()
  state = {
    actions = {}, binds = {}, logs = {}, next_id = 0,
    active = "w1",
    windows = {
      { window_id = "w1", focused_block_id = "pane1", layers = { { layer_id = "t1", kind = "tiled", blocks = { { block_id = "pane1", label = "shell" } } } } },
      { window_id = "w2", focused_block_id = "pane2", layers = { { layer_id = "t2", kind = "tiled", blocks = { { block_id = "pane2", label = "shell" } } } } },
    },
    cwd = { pane1 = "/repo/sub", pane2 = "/other" },
    pwd = {},
    git = { ["/repo/sub"] = "/repo" },
    on_exec = nil,
  }

  rex = {
    action = function(a) state.actions[a.name] = a end,
    bind = function(key, action) state.binds[key] = action end,
    log = function(level, message) state.logs[#state.logs + 1] = level .. ": " .. message end,
    exec = function(argv)
      if state.on_exec then state.on_exec() end
      local root = state.git[argv[3]]
      if root then return { ok = true, stdout = root .. "\n" } end
      return { ok = false, stdout = "" }
    end,
    block = {
      call = function(_, method, args)
        if method == "process" then
          local cwd = state.cwd[args.block_id]
          return cwd and { child = { cwd = cwd } } or {}
        end
        return { pwd = state.pwd[args.block_id] }
      end,
    },
    session = {
      view = function()
        return { active_window_id = state.active, windows = state.windows }
      end,
      new_layer = function(args)
        state.next_id = state.next_id + 1
        local id = "float" .. state.next_id
        for _, w in ipairs(state.windows) do
          if w.window_id == state.active then
            w.layers[#w.layers + 1] = {
              layer_id = id, kind = "floating", options = args.layout.block.options,
              blocks = { { block_id = id .. "-block", label = args.layout.block.label } },
            }
          end
        end
        return { layer_id = id }
      end,
      close_layer = function(args)
        for _, w in ipairs(state.windows) do
          for i, l in ipairs(w.layers) do
            if l.layer_id == args.layer_id then table.remove(w.layers, i) return { revision = 1 } end
          end
        end
        return nil, "not_found"
      end,
    },
  }

  -- A fresh copy of init.lua for each test, as after a reload.
  return dofile(INIT)
end

-- The floats open in the session: "window/label@cwd" each.
local function shown()
  local out = {}
  for _, w in ipairs(state.windows) do
    for _, l in ipairs(w.layers) do
      if l.kind == "floating" then
        out[#out + 1] = w.window_id .. "/" .. l.blocks[1].label .. "@" .. l.options.cwd
      end
    end
  end
  return table.concat(out, ",")
end

local function press(name, ctx)
  ctx = ctx or { session_id = "s1", block_id = "pane1" }
  return pcall(state.actions["floats_" .. name].run, ctx, {})
end

local FLOATS = {
  { name = "diff", key = "cmd+shift+t", command = "tuicr", cwd = "git" },
  { name = "shell", key = "cmd+shift+s" },
}

test("setup defines an action and binds a key for each float", function()
  fresh().setup{ floats = FLOATS }
  eq(state.binds["cmd+shift+t"], "floats_diff")
  eq(state.binds["cmd+shift+s"], "floats_shell")
end)

test("a key opens its float, and the same key closes it", function()
  fresh().setup{ floats = FLOATS }
  assert(press("diff"))
  eq(shown(), "w1/floats:diff@/repo")
  assert(press("diff", { session_id = "s1", block_id = "float1-block" }))
  eq(shown(), "")
end)

test("another float's key replaces the float", function()
  fresh().setup{ floats = FLOATS }
  assert(press("diff"))
  assert(press("shell"))
  eq(shown(), "w1/floats:shell@/repo/sub")
end)

test("a float in another window moves to the active one", function()
  fresh().setup{ floats = FLOATS }
  assert(press("diff"))
  state.active = "w2"
  state.git["/other"] = "/other"
  assert(press("diff", { session_id = "s1", block_id = "pane2" }))
  eq(shown(), "w2/floats:diff@/other")
end)

test("a float opened before a reload still closes with its key", function()
  fresh().setup{ floats = FLOATS }
  assert(press("diff"))
  -- Reload: a new copy of init.lua, with the old float still in the session.
  dofile(INIT).setup{ floats = FLOATS }
  assert(press("diff"))
  eq(shown(), "")
end)

test("a second press while one runs is dropped", function()
  fresh().setup{ floats = FLOATS }
  local inner
  state.on_exec = function()
    state.on_exec = nil
    inner = { press("diff") }
  end
  assert(press("diff"))
  eq(inner[1], true, "the second press doesn't fail")
  eq(shown(), "w1/floats:diff@/repo")
end)

test("a failed press doesn't block the next one", function()
  fresh().setup{ floats = FLOATS }
  state.git = {}
  local ok, err = press("diff")
  eq(ok, false)
  has(err, "floats: not a git repository: /repo/sub")
  state.git = { ["/repo/sub"] = "/repo" }
  assert(press("diff"))
  eq(shown(), "w1/floats:diff@/repo")
end)

test("with no block, the active window's focused pane is used", function()
  fresh().setup{ floats = FLOATS }
  assert(press("shell", { session_id = "s1" }))
  eq(shown(), "w1/floats:shell@/repo/sub")
end)

test("an OSC 7 pwd is read as a path", function()
  fresh().setup{ floats = FLOATS }
  state.cwd.pane1 = nil
  state.pwd.pane1 = "file://mac.local/tmp/my%20dir"
  assert(press("shell"))
  eq(shown(), "w1/floats:shell@/tmp/my dir")
end)

test("a setup mistake is reported by the float's key", function()
  fresh().setup{ floats = { { name = "diff", key = "cmd+shift+t", cwd = "repo" } } }
  local ok, err = press("diff")
  eq(ok, false)
  has(err, 'floats: fix the setup in init.lua: floats[1].cwd: expected "pane" or "git"')
  eq(shown(), "")
end)

test("a float with a bad name still reports the mistake from its key", function()
  fresh().setup{ floats = { { name = "Lazy-Git", key = "cmd+shift+g" } } }
  eq(state.binds["cmd+shift+g"], "floats_setup_error")
  local ok, err = pcall(state.actions.floats_setup_error.run, { session_id = "s1" }, {})
  eq(ok, false)
  has(err, "floats[1].name: expected lowercase")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
