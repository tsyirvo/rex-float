# Floats

Open a command in a floating terminal over your [Rex](https://www.superlogical.com/) window with one key, such as `lazygit` or [`tuicr`](https://github.com/agavra/tuicr), in the directory of the pane you were in. Press the key again, or quit the command, and the float closes.

- The float starts in the focused pane's directory, or at its git repository's root.
- Each float is a name, a key and a command, and also shows in the command palette.
- If the command fails, the float stays open with its output until you press a key.
- One float at a time: another float's key replaces the open one.

## Install

Requires the Rex Mac app, git and bash (the macOS bash 3.2 works). The commands your floats run must be on your shell's `PATH`.

```sh
git clone https://github.com/tsyirvo/rex-floats ~/.config/rex/floats
cp ~/.config/rex/floats/floats.example.lua ~/.config/rex/floats-config.lua
```

Don't name the copy `floats.lua`, or `require("floats")` loads it instead of Floats.

Add this to `~/.config/rex/init.lua`, then run `rex config reload`:

```lua
require("floats").setup{ floats = require("floats-config") }
```

With `XDG_CONFIG_HOME` set, use `$XDG_CONFIG_HOME/rex` instead of `~/.config/rex`.

## Configure

```lua
-- floats-config.lua
return {
  { name = "diff", key = "cmd+shift+t", command = "tuicr", cwd = "git" },
  { name = "lazygit", key = "cmd+shift+g", command = { "lazygit" }, cwd = "git", bounds = { 0.05, 0.05, 0.9, 0.9 } },
}
```

| Field     | Meaning                                                                                         |
| --------- | ----------------------------------------------------------------------------------------------- |
| `name`    | Required. Lowercase letters, digits and underscores. Defines the action `floats_<name>`.        |
| `title`   | Name in the command palette. Defaults to `name`.                                                |
| `key`     | Key that toggles the float, such as `"cmd+shift+t"`. Omit it to bind `floats_<name>` yourself.  |
| `command` | A string runs with `sh -c`; a list is the program and its arguments. Omit it for a plain shell. |
| `cwd`     | `"pane"` (default) or `"git"` (repository root; refuses to open outside a repository).          |
| `hold`    | Keep the float open after the command ends: `"error"` (default), `"always"` or `"never"`.       |
| `bounds`  | `{ x, y, width, height }` as fractions of the window. Defaults to `setup`'s `bounds`.           |

`setup` also takes `bounds`, the default for every float (`{ 0.1, 0.1, 0.8, 0.8 }`).

A float's key overrides what that key did before, including Rex's built-in shortcuts, but shortcuts set in the Rex app take precedence. Two floats can't share a key.

Mistakes in the options don't break the rest of your `init.lua`. Floats shows the error when you press a float's key:

```
floats: fix the setup in init.lua: floats[2].cwd: expected "pane" or "git", got repo
```

## How it works

```
key press → floats_<name>
  init.lua resolves the focused pane's directory (or its repo root)
  rex.session.new_layer opens a floating terminal there, running run.sh
    run.sh runs the command, and on failure waits for a key
  run.sh exits → the terminal closes → the layer closes
```

Floats keeps no state: it finds the open float by its block label, `floats:<name>`, so a float opened before `rex config reload` or a server restart still closes with its key. Each session shows at most one float, in the tab where it opened. From the CLI, `rex do floats_<name>` acts on the active tab's focused pane.

## Develop

```sh
mise install      # Lua 5.1.5, shellcheck, hk, gitleaks
hk install        # git hooks
mise run check    # lint and tests
```

Tests run against a fake `rex` under Lua 5.1, the version Rex uses. Commits follow [Conventional Commits](https://www.conventionalcommits.org); PRs are squash-merged and [release-please](https://github.com/googleapis/release-please) handles releases.

## License

[MIT](LICENSE)
