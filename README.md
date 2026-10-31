# Floats

Floats opens a command in a floating terminal over your [Rex](https://www.superlogical.com/rex) window, with one key.

Press a key and the command starts over the window, in the directory of the pane you were in: `tuicr` to read the diff of the repo you are working in, `lazygit` to stage and commit, anything else you run often. Quit the command, or press the key again, and the float closes.

- **Where you are.** The float starts in the focused pane's directory, or at the root of its git repository.
- **One file of floats.** Give each float a name, a key and a command. Each one is also an action in the command palette.
- **Errors stay readable.** When a command fails, the float stays open with its output until you press a key.
- **One float at a time.** A float's key closes it. Another float's key replaces it.

## Requirements

| Tool                                    | Tested with                    | Notes                                 |
| --------------------------------------- | ------------------------------ | ------------------------------------- |
| [Rex](https://www.superlogical.com/rex) | Mac app, October 2026 previews |                                       |
| git, bash                               | bash 3.2                       | Works with the bash that macOS ships. |

The commands your floats run, such as [tuicr](https://github.com/agavra/tuicr) or [lazygit](https://github.com/jesseduffield/lazygit), must be on the `PATH` of your shell.

## Install

1. Clone Floats into your Rex configuration folder:

   ```sh
   git clone https://github.com/tsyirvo/rex-floats ~/.config/rex/floats
   ```

2. Copy the example floats beside it:

   ```sh
   cp ~/.config/rex/floats/floats.example.lua ~/.config/rex/floats-config.lua
   ```

   Don't name it `floats.lua`: `require("floats")` would load it in place of Floats.

3. Add Floats to `~/.config/rex/init.lua`:

   ```lua
   require("floats").setup{ floats = require("floats-config") }
   ```

4. Reload the configuration:

   ```sh
   rex config reload
   ```

If you keep your configuration somewhere else with `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/rex` in place of `~/.config/rex`.

## Use

Focus a pane and press a float's key, or pick "Floats: …" in the command palette. From the CLI, `rex do floats_<name>` uses the focused pane of the active tab.

- The command opens in a float, in the pane's directory or its repository's root.
- Quit the command and the float closes. If the command failed, the float first shows its output and waits for a key.
- Press the same key again to close the float. Press another float's key to replace it.

Each session shows at most one float. A float stays in the tab it opened in. Pressing its key from another tab closes it there and opens a new one in that tab.

## Configure

`setup` takes two options:

```lua
require("floats").setup{
  -- The floats' x, y, width and height, as fractions of the window.
  bounds = { 0.1, 0.1, 0.8, 0.8 },

  -- The floats, each with its key and command.
  floats = require("floats-config"),
}
```

A float looks like this:

```lua
return {
  { name = "diff", key = "cmd+shift+t", command = "tuicr", cwd = "git" },
  { name = "lazygit", key = "cmd+shift+g", command = { "lazygit" }, cwd = "git", bounds = { 0.05, 0.05, 0.9, 0.9 } },
}
```

| Field     | Meaning                                                                                                                                       |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`    | Required. Lowercase letters, digits and underscores. The float's action is `floats_<name>`.                                                   |
| `title`   | The name in the command palette. Defaults to `name`.                                                                                          |
| `key`     | The key that opens and closes the float, such as `"cmd+shift+t"`. Leave it out to bind `floats_<name>` yourself.                              |
| `command` | A string runs with `sh -c`. A list is the program and its arguments. Leave it out for a plain shell.                                          |
| `cwd`     | `"pane"` (the default): the focused pane's directory. `"git"`: the root of its git repository. Outside a repository, Floats refuses.          |
| `hold`    | When the float stays open after the command ends, until you press a key: `"error"` (the default), `"always"` or `"never"`. Needs a `command`. |
| `bounds`  | `{ x, y, width, height }` as fractions of the window. Defaults to `bounds` from `setup`.                                                      |

A key set here replaces what the key did before, including a shortcut Rex ships with. A shortcut set in the app itself wins over the configuration file. Two floats can't share a key, in any order of modifiers: `cmd+shift+t` and `shift+cmd+t` are the same key.

Floats checks the options when Rex loads them. A mistake, such as an unknown field or two floats with the same key, does not stop the rest of your `init.lua`. Floats reports it when you press a float's key, even the key of a float whose name is wrong:

```
floats: fix the setup in init.lua: floats[2].cwd: expected "pane" or "git", got repo
```

## How it works

```
key press → floats_<name>
  init.lua finds the focused pane's directory (or its repo's root)
  rex.session.new_layer opens a floating terminal there, running run.sh
    run.sh runs the command, and on failure waits for a key
  run.sh exits → the terminal closes → the layer closes
```

Floats keeps no state between key presses. Each float's block has the label `floats:<name>`, and a key press finds the open float in `session.view` by that label. A float opened before `rex config reload` or a server restart still closes with its key. While one key press runs, Floats ignores another press in the same session, so a fast double press opens one float.

## Develop

```sh
mise install      # Lua 5.1.5, shellcheck, hk and gitleaks
hk install        # git hooks: secret scan, checks and tests on commit, commit message format
mise run check    # shellcheck, a bash 3.2 syntax check, and the tests
```

`tests/config_test.lua` covers `config.lua`, which holds the option checks, builds the terminal for each float, and decides what a key press does. It also covers `run.sh`. `tests/init_test.lua` runs `init.lua` against a fake `rex` that keeps one session in memory. Rex runs Lua 5.1, so the tests do too. To try a change in Rex without touching your loaded configuration, run `rex config check` on an `init.lua` that requires your working copy.

### Commits and releases

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org). The `commit-msg` hook checks each message. PRs are squash-merged, so the PR title becomes the commit on `main`, and CI checks the title too.

[release-please](https://github.com/googleapis/release-please) reads those commits. It keeps a release PR open with the next version and the new `CHANGELOG.md` entries. Merge that PR to release.

## License

[MIT](LICENSE)
