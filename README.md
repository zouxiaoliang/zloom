## zloom

A fast, manifest-driven plugin manager for Zsh — a descendant of
[zgen](https://github.com/tarjoilija/zgen) (see [History](#history)). Keep
your `.zshrc` clean and simple.

zloom clones your plugins once and weaves them into a static `init.zsh` that
is sourced on every start, so no plugin checking, cloning or update logic runs
at startup. Plugins can be declared the classic way in an `if ! zloom saved`
block in `.zshrc`, or — the recommended flow — managed through a fisher-style
manifest with `zloom add`, `zloom del`, `zloom snippet`, `zloom env` and
`zloom alias` (see [Plugin manifest](#plugin-manifest-fisher-style)).

### Highlights

- **Static init script** — plugins are resolved once at `zloom save` time;
  starting a shell is just `source init.zsh`.
- **Fisher-style manifest** — a plain-text `plugins.zsh` lists everything the
  shell should load; syncing that one folder (`~/.config/zloom`) to a new
  machine restores your whole setup.
- **Turbo mode** — `zloom defer` / `zloom add --defer` postpones heavy plugins
  until right after the first prompt appears.
- **Settings included** — `zloom env`, `zloom alias`, `zloom func` and
  `zloom eval` persist environment variables, aliases, functions and
  command-generated setup through the same manifest.
- **Byte-compiled everywhere** — the init script, every sourced plugin script
  and the `compinit` dump are cached as `.zwc` bytecode and invalidated
  automatically when their source changes.
- **Housekeeping** — `zloom sync` reconciles clones and `init.zsh` with the
  manifest after a hand edit; `zloom list --outdated` shows what is behind
  its remote; `zloom clean` removes what the manifest no longer references.
- **Version pins** — `owner/repo@tag`, `@branch`, `@commit` or `@HEAD`, which
  follows the remote's default branch even across a rename.
- **Diagnosable** — `zloom doctor` reports ignored manifest lines, stale
  init scripts, missing clones and a per-section startup breakdown.

The flip side of the static approach: updates are manual. Run `zloom update`
to pull new plugin versions (it resets the init script afterwards) or
`zloom sync --update` to pull and reconcile in one go, and `zloom reset`
whenever you change the plugin set in a `.zshrc`-managed setup.

## Installation

Clone the zloom repository

    git clone https://github.com/zouxiaoliang/zloom.git "${HOME}/.zloom"

Edit your .zshrc file to load zloom

    # load zloom
    source "${HOME}/.zloom/zloom.zsh"

Place the following code after the one above to load oh-my-zsh for example, see Usage for more details

    # if the init script doesn't exist
    if ! zloom saved; then

      # specify plugins here
      zloom oh-my-zsh

      # generate the init script from plugins above
      zloom save
    fi

## Usage

### oh-my-zsh

This is a handy shortcut for installing oh-my-zsh plugins. They can be loaded using `zloom load` too with a significantly longer format.
#### Load oh-my-zsh base
It's a good idea to load the base components before specifying any plugins.

    zloom oh-my-zsh

#### Load oh-my-zsh plugins

    zloom oh-my-zsh <location>

#### Example

    zloom oh-my-zsh
    zloom oh-my-zsh plugins/git
    zloom oh-my-zsh plugins/sudo
    zloom oh-my-zsh plugins/command-not-found
    zloom oh-my-zsh themes/arrow

### Prezto

#### Load Prezto

    zloom prezto

This clones prezto and loads its `init.zsh`. By default a sensible set of core
modules is loaded as well; set `ZLOOM_PREZTO_LOAD_DEFAULT=0` before it to pick
modules yourself.

#### Load prezto plugins

    zloom prezto <modulename>

This uses the Prezto method for loading modules.

#### Load a repo as Prezto plugins

    zloom pmodule <reponame> <branch>

Clones the repository if needed and loads it as a Prezto module via `pmodload`.

#### Set prezto options

    zloom prezto <modulename> <option> <value(s)>

This must be used before the module is loaded. Or if the default modules should be loaded (default) these settings must be done before the `zloom prezto` command. `module` is prepended if the name does not start with `module`, `prezto` or a `*`, `prezto` is prepended if it does not start with `prezto`.

### General zloom functions

#### Load plugins and completions

    zloom load <repo> [location] [branch]

Zloom tries to source any scripts from `location` using a "very smart matching logic". If it fails to find any, it will appends `location` to `$fpath`.

- `repo`
    - github `user/repository` or path to a repository
    - currently supported formats for a repository path:
        - any local repository
        - `git://*`
        - `https://*`
        - `http://*`
        - `ssh://*`
        - `git@*:*/*`
- `location`
    - relative path to a script/folder
    - useful for repositories that don't have proper plugin support like `zsh-users/zsh-completions`
- `branch`
    - specifies the git branch to use

#### Defer plugin loading (turbo)

    zloom defer <repo> [location] [branch]

Like `zloom load`, but the plugin's scripts are not sourced during shell
startup. They are sourced by a one-shot `zle` hook the instant the first
prompt appears on screen, so heavy plugins no longer block your shell from
becoming usable. Completion directories still join `$fpath` synchronously,
so completions keep working.

Notes:

- The shell that runs `zloom save` does not load deferred plugins; they
  become active in new shells (right after their first prompt).
- Non-interactive shells (scripts, `zsh -c`) load deferred plugins
  synchronously, so nothing is ever skipped. A one-shot `zsh -ic 'command'`
  shell is indistinguishable from a real interactive shell and exits
  before the line editor ever runs; set `ZLOOM_TURBO=0` for such
  invocations to load everything synchronously, e.g.
  `ZLOOM_TURBO=0 zsh -ic 'myplugin-fn'`.
- Prompt themes can be deferred; the prompt is redrawn after loading.

### Plugin manifest (fisher-style)

Instead of the `if ! zloom saved` block in `.zshrc`, plugins can be managed
through a plain-text manifest, inspired by
[fisher](https://github.com/jorgebucaran/fisher). The manifest lives at
`${XDG_CONFIG_HOME:-~/.config}/zloom/plugins.zsh` (override with
`$ZLOOM_PLUGINS`; a pre-existing `${ZLOOM_DIR}/plugins.zsh` keeps being used)
and holds one entry per line:

    load zsh-users/zsh-completions src
    defer zsh-users/zsh-autosuggestions
    snippet https://example.com/raw/config.zsh
    env EDITOR=vim
    alias ll 'ls -la'
    func hello 'echo Hello ${1:-zloom}'
    eval /opt/homebrew/bin/brew shellenv

Blank lines and `#` comments are ignored. Whenever the init script is
missing (fresh machine, `zloom reset`, `zloom update`), zloom rebuilds it from
the manifest automatically, so the manifest file is all you need to restore
your setup on a new machine.

Configuration and regenerable data live apart, fisher-style:

    ~/.config/zloom/            # sync this: your configuration
    ├── plugins.zsh             # the manifest
    ├── config.zsh              # main user config, sourced before the plugins
    ├── conf.d/                 # drop-in config fragments, no registration needed
    ├── functions/              # one .zsh file per custom function
    ├── completions/            # custom completion files, joined to $fpath
    └── themes/                 # theme configs, sourced after the plugins
    ~/.zloom/                   # the zloom program itself (a git clone)
    ~/.local/share/zloom/       # safe to delete: rebuilt on demand
    ├── init.zsh                # generated from the manifest
    ├── <encoded-location>/…    # cloned plugins
    └── snippets/               # remote snippet cache

(The data half honors `$XDG_DATA_HOME`; the whole tree regenerates from
`~/.config/zloom` on the next start after deletion.)

Upgrading from the single-directory layout — zloom storing data inside
`~/.zloom` — is a one-time move; the generated init script embeds absolute
paths, so delete it and let the next shell rebuild:

    d="${XDG_DATA_HOME:-$HOME/.local/share}/zloom"; mkdir -p "$d"
    mv ~/.zloom/init.zsh* ~/.zloom/completions.stamp "$d"/ 2>/dev/null
    for dir in ~/.zloom/*(N/); do [[ ${dir:t} == .git ]] || mv "$dir" "$d"/; done
    rm -f "$d"/init.zsh*

The layout mirrors fish's `~/.config/fish`. On each start zloom sources, in
order:

1. the manifest's `env` and `eval` entries (the manifest-managed environment)
2. `conf.d/*.zsh`, alphabetical, then `config.zsh` — your hand-written config
3. the manifest's `load`/`defer`/`snippet` plugins
4. the manifest's `alias` entries
5. `functions/*.zsh`, alphabetical
6. `themes/*.zsh`, alphabetical — prompt configs go here, so they can address
   the prompt framework the plugins just loaded
7. `completions/` joins `$fpath` and `compinit` runs

The `conf.d/`, `functions/`, `completions/` and `themes/` scans are baked
into the generated `init.zsh`: dropping a file into any of them (or removing
one) takes effect on the **next shell start without a rebuild**. For
`completions/` this works because the generated `init.zsh` keeps a stamp of
the directory's file list (`${ZLOOM_DIR}/completions.stamp`): an unchanged
list takes the fork-free `compinit -C` fast path, while adding or removing a
file triggers one full `compinit` rescan that picks it up and refreshes the
stamp.

#### Add a plugin

    zloom add <plugin>[@ref] [location] [branch]
    zloom add --defer <plugin>[@ref] [location] [branch]

Clones the plugin if needed, loads it right away, appends it to the manifest
and regenerates `init.zsh`; future shells pick it up automatically. With
`--defer` the entry is recorded for turbo mode instead: future shells source
it right after the first prompt.

`@ref` pins a tag, branch or commit fisher-style (`zsh-users/zsh-autosuggestions@v0.7.0`).
When no ref or branch is given, `zloom add` asks the remote for its default
branch (one `git ls-remote`) and records it as a pin unless it is `master` —
clone directories embed the branch, so the recorded pin keeps rebuilds
deterministic and offline-safe on repositories whose default is `main`.

`@HEAD` follows the remote's default branch without naming it. It is what
`zloom add` records when the remote cannot be reached, and the right choice
for a plugin whose default branch may be renamed: `zloom update` asks the
remote which commit its `HEAD` names and checks that out, so the clone
follows a rename, where a plain `git pull` would keep tracking the old name.

#### Remove a plugin

    zloom del <plugin>
    zloom del <snippet-url-or-path>
    zloom del <env-KEY | alias-NAME | func-NAME>

Removes the matching entry from the manifest and regenerates `init.zsh`. The
plugin files stay on disk (exactly like `zloom reset`); a plugin cannot be
unloaded from the running shell, but new shells stop sourcing it. Env, alias
and function entries, however, are also removed from the running shell
(`unset` / `unalias` / `unfunction`).

#### Sync the world with the manifest

    zloom sync
    zloom sync --clean
    zloom sync --update

`zloom sync` reconciles everything with the manifest in one command —
fisher's `update` model: hand-edit `plugins.zsh`, run `zloom sync`. It
clones every `load`/`defer` repository that is missing on disk
(concurrently), regenerates `init.zsh` from the manifest, and reports
clones that are no longer referenced (with `--clean` it deletes them, like
`zloom clean --force`). No `zloom reset` plus a new shell needed. With
`--update` it also pulls every existing clone first, so reconcile and fetch
are one command.

#### Lifecycle hooks

    _zloom_post_add <plugin>
    _zloom_post_del <name>
    _zloom_post_sync
    _zloom_post_update

Functions with these names are invoked (with the command's argument) after
`zloom add` / `del` / `sync` / `update` finish, when defined — zsh has no
event system, so zloom calls convention-named functions instead of fisher's
`fisher_*` events. `functions/` is the natural place to define them; a hook
file named after the hook (`functions/_zloom_post_sync.zsh`) is sourced on
demand, so it also runs in a shell that has not loaded `init.zsh` yet.

#### Set a persistent environment variable

    zloom env KEY=VALUE
    zloom env KEY VALUE

Exports KEY right away, appends the entry to the manifest and regenerates
`init.zsh`, so every future shell exports it as well. In the generated
`init.zsh` environment entries are exported before anything else, so plugins
can rely on them; the manifest position of the entry does not matter.
Re-running `zloom env` for the same KEY updates the entry in place. Values are
stored literally: no `~`, `$var` or command substitution is expanded.

#### Define a persistent alias

    zloom alias NAME=COMMAND
    zloom alias NAME COMMAND...

Defines the alias right away, appends the entry to the manifest and
regenerates `init.zsh`. In the generated `init.zsh` aliases are defined after
all plugins are sourced, so they win over aliases a plugin may define (again
regardless of where the entry sits in the manifest). Re-running `zloom alias`
for the same NAME updates the entry in place.

#### Define a persistent function

    zloom func NAME=BODY
    zloom func NAME BODY...

Defines the function right away (`NAME() { BODY }`), appends the entry to
the manifest and regenerates `init.zsh`. Like aliases, functions are defined
after all plugins are sourced, so they win over plugin-provided ones. The
body is stored as a single line — anything larger belongs in a snippet file.
Re-running `zloom func` for the same NAME updates the entry in place;
`zloom del NAME` also `unfunction`s it from the running shell.

#### Function files

    ~/.config/zloom/functions/
    ├── fixcmd.zsh
    └── hello.zsh

Besides the one-line `zloom func` entries, custom functions can live as one
`*.zsh` file each in the `functions/` directory next to the manifest — the
fish convention. Every file is sourced on each start, after plugins and
aliases, so the functions win over plugin-provided ones. Each file is
byte-compiled automatically on first use.

The scan loop lives in the generated `init.zsh` itself, so adding or
removing a file takes effect on the **next shell start without a rebuild** —
just drop the file in. A functions-only directory bootstraps the init script
even without a manifest, and nothing else in your setup is affected.

#### Evaluate a command's output at startup

    zloom eval <command...>

Runs `eval "$(command)"` right away and records the entry in the manifest.
In the generated `init.zsh` eval entries run after the `env` exports but
**before any plugin is sourced**, in manifest order, so plugins see the PATH
and functions they set up — the natural home for things like
`zloom eval /opt/homebrew/bin/brew shellenv` or
`zloom eval rbenv init - zsh`. Use absolute paths when the command only
becomes available through the eval itself. The command must succeed and its
output is evaluated as zsh code; unlike env values or aliases, an eval
cannot be undone in the running shell (`zloom del` only stops future shells
from running it).

#### Load a local or remote snippet

    zloom snippet <url-or-path>

Like `zinit snippet`: sources a single configuration file, either from a
local path or downloaded from a URL. Remote snippets are cached under
`${ZLOOM_DIR}/snippets` and refreshed by `zloom update`; the origin URL is
recorded in a `.url` sidecar file. The entry is added to the manifest so it
keeps loading in future shells.

Local snippet paths are stored relative to the manifest directory when the
file lives inside it (e.g. `snippet snippets/config.zsh` for
`~/.config/zloom/snippets/config.zsh`), so the whole config folder can be
synced to another machine as-is; relative entries resolve against the
manifest directory at load time.

For local config fragments that should load on every start, prefer dropping
a file into `conf.d/` instead — no manifest entry and no rebuild needed.

Note: once the manifest exists it is the source of truth for `init.zsh`.
Plugins that were only loaded inside the `.zshrc` `if ! zloom saved` block
should be added with `zloom add` as well, otherwise they stop loading after
the manifest is created.

#### Clean unreferenced plugins

    zloom clean
    zloom clean --force

`zloom clean` compares the cloned plugin directories under `${ZLOOM_DIR}` with
the manifest and reports every clone that is no longer referenced by a
`load`/`defer` entry (dry run). Stale remote-snippet caches go on the same
list: a cached file whose recorded origin URL is no longer a `snippet`
entry. `zloom clean --force` deletes them and the now-empty location
directories; snippet caches still listed, the zloom installation itself and
everything still referenced are never touched. If a stale `init.zsh` still
sources a removed plugin, it is reset automatically and rebuilt from the
manifest on the next start.

#### List plugins

    zloom list
    zloom list --plain
    zloom list --outdated

With a manifest present, prints the manifest grouped the way the generated
`init.zsh` executes it — Plugins (load), Turbo (defer), Snippets, Eval,
Environment, Aliases, Functions — each section with its entry count and a
`total` line at the end. Every entry carries its manifest line number in
brackets, so it can be found again in an editor:

    Plugins (3)
      robbyrussell/oh-my-zsh oh-my-zsh.sh  [7]
      ...

`--plain` forces the unadorned form (pipes and redirections get it
automatically). Lines zloom does not understand are reported on stderr and
make the command exit 1 — `zloom doctor` explains them. `--outdated` keeps
its one-line-per-plugin format. Legacy setups without a manifest keep the
old behaviour of dumping the generated `init.zsh`.

`--outdated` compares every clone with the remote ref it is pinned to and prints one
line per unique clone: `ok`, `outdated` (with the local and remote short SHAs),
`missing` (not cloned yet -- run `zloom sync`), `pinned` (a commit SHA, by definition
exact) or `?ref` (the ref no longer exists upstream). Entries that share one clone
(several oh-my-zsh plugin lines, one clone) are judged once and the line notes the
entry count -- `robbyrussell/oh-my-zsh  c014070 -> 6c31a91  (17 entries)`. It needs
the network and pulls nothing.

#### Bulk load plugins

    zloom loadall <plugins>

Please see example `.zshrc` for usage.

#### Generate init script
    zloom save

It is recommended to save the plugin sourcing part to a static init script so we don't have to go through the time consuming installing/updating part every time we start the shell (or source .zshrc)

#### Remove init script
    zloom reset

Removes the init script so it will be created next time you start the shell. You must run this every time you add or remove plugins to trigger the changes.

This will not remove the plugins physically from disk.

#### Check for an init script
    zloom saved
Returns 0 if an init script exists.

#### Diagnose the setup
    zloom doctor

Checks the setup and exits non-zero when something needs attention:

- manifest lines zloom would silently ignore — an unknown entry kind, an
  entry missing its argument, or extra words on an `env`/`snippet` line
  (those take exactly one value, so a second one is dropped);
- `init.zsh` missing, or older than the manifest (`zloom sync` rebuilds it);
- plugin clones the manifest lists but that are not on disk;
- completion commands declared in `completions/` that are not registered.

It also times one interactive shell start, and breaks the generated
`init.zsh` down by section, heaviest first. The timing runs against a
throwaway copy of `init.zsh`: the real file carries no timing code, so
`doctor` itself costs the steady-state startup nothing. Deferred plugins are
sourced after the first prompt and do not appear in the startup figures.

#### Update all plugins and reset
    zloom update

Updates every plugin repository concurrently and removes the init script.
Branch checkouts are pulled; `@tag` pins are re-fetched and checked out (so
a moved tag is followed) and `@HEAD` pins follow the remote's default branch;
`@commit` pins stay exactly where they are. Repositories that fail are
reported and make the command exit non-zero.

#### Update zloom
    zloom selfupdate
    zloom selfupdate --rollback

Pulls the zloom repository and removes the init script. The revision it
replaced is remembered, so `--rollback` restores it (once, until the next
update). `zloom version` prints the revision currently running.

#### Clone a repository without loading it
    zloom clone <repo> [branch]

Clones (or reuses) the repository under `${ZLOOM_DIR}` without sourcing
anything. Useful for inspecting a plugin or pre-seeding a setup.

#### Apply fpath and completions to the current shell
    zloom apply

Adds the recorded completion directories to `$fpath` and runs `compinit` in
the current shell. `zloom save` calls this automatically at the end.

#### Watch files for modifications
You can automate the process of running `zloom reset` by specifying a list of files to `ZLOOM_RESET_ON_CHANGE`. These files will be checked and if a change is detected zloom reset is called.

```zsh
ZLOOM_RESET_ON_CHANGE=(${HOME}/.zshrc ${HOME}/.zshrc.local)
```

## Configuration

All variables are read when `zloom.zsh` is sourced, so set them before the
`source` line in `.zshrc`.

| Variable | Default | Description |
|---|---|---|
| `ZLOOM_DIR` | `~/.local/share/zloom` | Data root: init script, plugin clones, snippet cache (a legacy `~/.zloom` holding `init.zsh` keeps being used) |
| `ZLOOM_INIT` | `$ZLOOM_DIR/init.zsh` | Path of the generated static init script |
| `ZLOOM_PLUGINS` | `~/.config/zloom/plugins.zsh` | Path of the plugin manifest (a pre-existing `$ZLOOM_DIR/plugins.zsh` wins) |
| `ZLOOM_AUTOLOAD_COMPINIT` | auto | Enabled automatically unless `compinit` already ran; set to `0` to handle `compinit` yourself |
| `ZLOOM_CUSTOM_COMPDUMP` | — | Custom `compinit` dump path |
| `ZLOOM_RESET_ON_CHANGE` | — | List of files; when one of them changes, the init script is reset automatically (see [Watch files for modifications](#watch-files-for-modifications)) |
| `ZLOOM_TURBO` | — | Set to `0` to load deferred plugins synchronously, e.g. `ZLOOM_TURBO=0 zsh -ic 'myplugin-fn'` |
| `ZLOOM_OH_MY_ZSH_REPO` / `ZLOOM_OH_MY_ZSH_BRANCH` | `robbyrussell/oh-my-zsh` / `master` | Where `zloom oh-my-zsh` clones from |
| `ZLOOM_PREZTO_REPO` / `ZLOOM_PREZTO_BRANCH` | `sorin-ionescu/prezto` / `master` | Where `zloom prezto` clones from |
| `ZLOOM_PREZTO_LOAD_DEFAULT` | `1` | `zloom prezto` also loads prezto's default module set |

## Notes
Be aware that `zloom` tries to handle [`compinit`][compinit] for you to allow for the fastest possible initialization times. However, this functionality will be disabled if you've already called `compinit` yourself before sourcing `zloom.zsh`. Alternatively, you can disable it yourself by disabling `$ZLOOM_AUTOLOAD_COMPINIT`.

To keep subsequent shells fast, `zloom save` byte-compiles the generated `init.zsh`, every sourced plugin script and the `compinit` dump with `zcompile`. Sourcing transparently prefers the newer `.zwc` bytecode and falls back to the plain file whenever it changes (e.g. after `zloom update`), so the caches never need manual maintenance. Like upstream zgen, `zloom reset` removes only the init script and the completion dump; the `.zwc` files left behind are overwritten by the next regeneration.

  [compinit]: <http://zsh.sourceforge.net/Doc/Release/Completion-System.html#Use-of-compinit> "Zsh manual 20.2.1: Use of compinit"

## Example .zshrc

```zsh
# load zloom
source "${HOME}/.zloom/zloom.zsh"

# if the init script doesn't exist
if ! zloom saved; then
    echo "Creating a zloom save"

    zloom oh-my-zsh

    # plugins
    zloom oh-my-zsh plugins/git
    zloom oh-my-zsh plugins/sudo
    zloom oh-my-zsh plugins/command-not-found
    zloom load zsh-users/zsh-syntax-highlighting
    zloom load /path/to/super-secret-private-plugin

    # bulk load
    zloom loadall <<EOPLUGINS
        zsh-users/zsh-history-substring-search
        /path/to/local/plugin
EOPLUGINS
    # ^ can't indent this EOPLUGINS

    # completions
    zloom load zsh-users/zsh-completions src

    # theme
    zloom oh-my-zsh themes/arrow

    # save all to init script
    zloom save
fi
```

### Example .zshrc for prezto use
Here is a partial example how to work with prezto

```zsh
...
    echo "Creating a zloom save"

    # prezto options
    zloom prezto editor key-bindings 'emacs'
    zloom prezto prompt theme 'sorin'

    # prezto and modules
    zloom prezto
    zloom prezto git
    zloom prezto command-not-found
    zloom prezto syntax-highlighting

    # plugins
    zloom load /path/to/super-secret-private-plugin
....

```

## Development

    zsh tests/run.zsh

Offline regression suite, 119 checks: every test runs in its own sandbox
(temp `HOME`/`XDG_CONFIG_HOME`/`ZLOOM_DIR`) and remote plugins are simulated
with local bare git repositories reached through `file://` URLs. The exit
status is 0 only when every check passes.

Among the checks is the one that keeps zloom fast: regenerating `init.zsh`
from the same manifest must be byte-identical, and the result must contain
no command-side code. `doctor`, `sync`, `outdated` and the hooks all live in
zloom's commands, never on the startup path — starting a shell is still just
sourcing a static, byte-compiled script and arming the one-shot turbo hook.

## History

zloom's story starts with [Antigen](https://github.com/zsh-users/antigen),
which made zsh plugins easy to manage but re-resolved the whole plugin set on
every shell start, costing hundreds of milliseconds of startup time. In
November 2014, [tarjoilija/zgen](https://github.com/tarjoilija/zgen) answered
with the opposite trade-off: resolve the plugins once, generate a static
`init.zsh`, and simply `source` it on every start. Upstream development slowed
after 2018, with the last commit landing in 2021.

This repository began as a zgen fork on a `perf/startup-optimizations` branch
and grew in two directions:

- **Startup performance.** Hot paths were made fork-free (no
  command-substitution subshells during startup), the init script, every
  sourced plugin script and the `compinit` dump became `zcompile`-cached
  `.zwc` bytecode, and **turbo mode** (`zloom defer`) was added: a one-shot
  `zle` hook sources heavy plugins the instant the first prompt is on screen,
  so they never block the shell from becoming usable.
- **A fisher-style manifest.** Inspired by
  [fisher](https://github.com/jorgebucaran/fisher), a plain-text
  `plugins.zsh` became the source of truth for the init script: `zloom add` /
  `zloom del` / `zloom snippet` manage plugins, `zloom env` / `zloom alias`
  persist shell settings, and `zloom list` / `zloom clean` keep the setup
  tidy. A new machine only needs zloom itself plus that one file.

By then the day-to-day workflow had diverged far enough from zgen's
`.zshrc`-block style that the project was renamed: **zloom** — a loom weaves
many threads into a single cloth, the way the manifest is woven into one
static init script. The original design and the MIT license carry over;
credit for the foundation belongs to the zgen authors and contributors.

## Migrating from zgen

zloom uses the same directory layout as zgen under a new name, so an existing
setup carries over in three steps:

    mv ~/.zgen ~/.zloom
    rm -f ~/.zloom/init.zsh ~/.zloom/init.zsh.zwc
    # .zshrc: change the source line to "${HOME}/.zloom/zloom.zsh"
    #         and rename any ZGEN_* variables to ZLOOM_*

The next shell rebuilds `init.zsh` from the manifest (`plugins.zsh`), which
moved along with the directory, so plugins, env entries and aliases carry over.
Setups without a manifest rebuild from the `if ! zloom saved` block in
`.zshrc` as before.

## Other resources

The [awesome-zsh-plugins](https://github.com/unixorn/awesome-zsh-plugins) list contains many zloom-compatible zsh plugins & themes that you may find useful.

## Alternatives

- [zgen](https://github.com/tarjoilija/zgen) - the ancestor of zloom, minimal and stable
- [antigen](https://github.com/zsh-users/antigen) - popular and mature
- [zplug](https://github.com/b4b4r07/zplug) - well performing and has a fancy UI
