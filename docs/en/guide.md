[Supax](README.md) / **Guide** | [العربية](../ar/guide.md)

# Supax guide

The full reference: every command and option, dependencies, programs, workspaces, tests, the cache and safety. File formats are described in [File formats](formats.md).

## Commands

| Command | Arabic | What it does |
|---|---|---|
| `supax new <name> [--lib]` | `supax جديد` | Create a package in a new directory; with `--lib`, a library (below) |
| `supax init [name] [--lib]` | `supax هيئ` | Create a package in the current directory; `--lib` as with `new` |
| `supax add <name>[@<version>]`, or `<name> --path <path>`, or `<name> --git <url> [--tag <tag>]`, each with `[--dev]` | `supax أضف` | Add a dependency to `Supax.toml` (`[dev-dependencies]` with `--dev`) and update `Supax.lock`; nothing changes if it fails. Without `@<version>`, the newest release in the index |
| `supax remove <name> [--dev]` | `supax احذف` | Remove a dependency (from `[dev-dependencies]` with `--dev`) and update `Supax.lock` |
| `supax fetch` | `supax جلب` | Resolve and fetch dependencies, write `Supax.lock` |
| `supax update [name...]` | `supax حدث` | Re-resolve, ignoring pins (all, or the named ones) |
| `supax tree` | `supax شجرة` | Show the dependency graph |
| `supax metadata [--output=<file>] [--relative]` | `supax بيانات` | Write the package graph the compiler reads |
| `supax verify` | `supax تحقق` | Check the cache against `Supax.lock`, offline |
| `supax check` | `supax افحص` | Check the project with the compiler |
| `supax build` | `supax ابن` | Build the project into `build/bin/` |
| `supax run [--bin <name>] [-- args]` | `supax شغل` | Build the project, then run one program |
| `supax test [text]` | `supax اختبر` | Run the tests (`@@test` functions) through `sultanc test`: the lib, each program, then each `tests/*.sn`. `text` keeps only tests whose name contains it |
| `supax fmt [--check]` | `supax نسق` | Format the package's sources with `sultanc fmt` (below) |
| `supax install <name>[@<req>]`, or `--path <dir>`, or `--git <url> [<name>]` | `supax ثبت` | Build a package's programs with `--release` and copy them into `~/.supax/bin` (below) |
| `supax uninstall <package> [--bin <name>]` | `supax أزل` | Remove the programs `supax install` installed for a package |
| `supax clean` | `supax نظف` | Remove the `build/` directory |
| `supax package [--git <url>]` | `supax حزّم` | Check this release (clean tree, `[lib]`, semantic version, no path dependencies) and print its `[[versions]]` entry and file path for the package index |
| `supax publish [--git <url>]` | `supax انشر` | Run the `package` checks, then explain how to publish by hand: the registry website is not available yet, so nothing is uploaded ([File formats](formats.md#adding-a-version)) |
| `supax yank [<name>@]<version> [--undo] [--index <dir>]` | `supax اسحب` | Yank a version (or undo it) in a local clone of the index; without a name, the package in the current directory ([File formats](formats.md#yanking-a-version)) |
| `supax migrate` | `supax رحّل` | Move `[imports-alias]` into `وحدة` lines in the root files (the compiler no longer reads it) |
| `supax cache [info \| clean]` | `supax مخبأ` | Show the git cache (folder, repositories, checkouts, size), or delete it |

| Option | What it does |
|---|---|
| `--dev` | With `add` and `remove`: the `[dev-dependencies]` table |
| `--locked` | Fail if `Supax.lock` would change |
| `--offline` | Never use the network; use only the cache |
| `--frozen` | `--locked` and `--offline` together |
| `--release` | Optimized build: the compiler gets `-O3`, as Cargo's release profile (`opt-level = 3`). Without it nothing is passed, which the compiler treats as `-O0`: fast to compile, every variable readable by a debugger |
| `--bin <name>` | Build or run only this program |
| `--package <name>`, `-p` | One member of the workspace |
| `--target <target>`, `-t` | Target platform (the list: `sultanc targets`); output in `build/bin/<target>/` |
| `--quiet`, `-q` | No status lines (Compiling, Finished, Running) |
| `--message-format=human\|short\|json` | Format of the compiler's diagnostics, passed to it as `--diagnostic-format` in `check`, `build`, `run`, `test` and `fmt`. With `json`, Supax prints no status lines, so the error stream holds only the compiler's JSON and Supax's own errors |
| `--color=auto\|always\|never` | Color in the compiler's diagnostics |
| `--lang=ar\|en` | Message language (default Arabic); also `SUPAX_LANG` |

Supax reads these options anywhere before `--`; everything after `--` goes to the program (`run`) or to `sultanc test` (`test`) unchanged.

## Dependencies

```toml
[package]
name = "app"
version = "0.1.0"

[dependencies]
mathx = "1.2"                                                   # from the package index
json  = { git = "https://github.com/someone/sn-json", tag = "v1.2.0" }
log   = { path = "../log" }
```

Version requirements follow Cargo's rules (`"1.2"` means `>=1.2.0, <2.0.0`). The package index is a git repository, `https://github.com/sultan-language/index` by default (`SUPAX_INDEX` changes it); each version in it points to a git commit and a content checksum.

The dependency syntax, the lock file and the cache are described in [File formats](formats.md).

### Dev-dependencies

`[dev-dependencies]` lists packages that only the tests need. It takes the same entries as `[dependencies]`:

```toml
[dev-dependencies]
fixtures = { path = "../fixtures" }
```

- Only the files in `tests/` can import them. A file in `src/` cannot, even inside a `@@test` function, because its imports are part of every build.
- `build`, `check`, `run` and `metadata` leave them out; `supax test` adds them.
- They are resolved and locked in `Supax.lock` like any other dependency. A dependency's own `[dev-dependencies]` are ignored.
- The same key cannot be in both tables. A package in `[dependencies]` is already available to the tests.

## Programs

A project can hold more than one program:

| File | Program | Output |
|---|---|---|
| `src/main.sn` | the package name | `build/bin/<package>` |
| `src/bin/<name>.sn` | `<name>` | `build/bin/<name>` |

`supax build` builds all of them; `--bin <name>` builds one. `supax run` runs `src/main.sn`; if there is no `src/main.sn` and more than one program, pass `--bin`. On Windows the output ends in `.exe`, and for a WebAssembly target (`wasm32-wasi` and the others) in `.wasm`. With `--target`, `supax run` builds the program, but runs it only if this machine can; otherwise it says which target the file was built for.

### Libraries

`supax new <name> --lib` creates a library instead of a program:

| File | Contents |
|---|---|
| `Supax.toml` | `[lib] path = "src"` |
| `src/<name>.sn` | The root file. It imports the library's modules, so `supax test` finds their tests |
| `src/lib.sn` | A public function and a test for it |

Another package imports it as `<name>.lib`.

## Formatting

`supax fmt` runs `sultanc fmt` on `src/`, `tests/`, a `main.sn` next to `Supax.toml`, and the `[lib]` folder if it is outside `src/`. With `--check` it changes nothing: it lists the unformatted files and exits with status 1, for CI. At a workspace root without `[package]` it formats every member. It needs no dependencies, so it works offline and without `Supax.lock`.

## Installing programs

`supax install` builds a package with `--release` and copies its programs (`src/main.sn` and `src/bin/*.sn`) into `~/.supax/bin` (`$SUPAX_HOME/bin`), which the installer already put on `PATH`:

| Source | Command |
|---|---|
| A local package | `supax install --path <dir>` |
| A git repository | `supax install --git <url> [<name>] [--tag <tag> \| --branch <branch> \| --rev <commit>]`. Without a name, the last part of the URL (`…/tool.git` → `tool`) |
| The package index | `supax install <name>[@<requirement>]`; without a requirement, the newest release |

- A git or index package is fetched and checked like any dependency (the same cache and checksum), copied into a temporary folder, built there, and the folder is deleted. Unlike a dependency, it does not need `[lib]`. A `--path` package is built in place, in its own `build/`.
- `~/.supax/installed.toml` records each installed program with its package, version and source. `supax install --list` prints it.
- Installing a package again replaces its programs. Supax does not overwrite a file another package installed, or one it did not install, unless you pass `--force`. It never installs a program named `supax` or `sultanc`.
- `supax uninstall <package>` deletes that package's programs; `--bin <name>` deletes one.
- Programs are built for this machine; `--target` is refused.

## Workspaces

Several packages in one repository share one `Supax.lock` at the root, as with Cargo:

```toml
# Supax.toml at the root
[workspace]
members = ["app", "libs/*"]    # "x/*" = every folder under x with a Supax.toml
exclude = ["libs/old"]         # optional
```

| Where you run | `build`, `check`, `test` act on | `run`, `add`, `remove`, `metadata` |
|---|---|---|
| Inside a member | That member | That member |
| A root without `[package]` | Every member (libraries are checked) | Need `-p <name>` |
| A root with `[package]` | The root package | The root package |
| Anywhere, with `-p <name>` | That member | That member |

`fetch`, `update`, `verify` and `tree` always cover the whole workspace. Path dependencies between members work as usual, and every member gets the same version of a shared dependency. A package inside the workspace folder that is not in `members` is an error unless it is in `exclude`. All members share one `build/` at the workspace root: programs go to `build/bin/`, and `supax clean` anywhere in the workspace removes it.

## Tests

A test is a function marked `@@test` (`@@اختبار`), with no parameters, returning nothing or `result int, Error`. `supax test` runs, in order:

| Target | File | Select with |
|---|---|---|
| lib | the library's root file: `[lib] path` if it is a file, else `<source root>/<package name>.sn` | `--lib` |
| bin | `src/main.sn` and each `src/bin/<name>.sn` | `--bin <name>` |
| test | each `tests/<name>.sn`, a separate program that imports the library by its name, and can also import the package's `[dependencies]` and `[dev-dependencies]` | `--test <name>` |

The compiler finds tests in the file and everything it imports, so a library's root file should import its modules. In a package with `[lib]`, a program runs only the tests in its own file, so the library's tests run once. A failing target stops the run and prints the option that reruns it; `--no-fail-fast` runs every target first. `--list` lists the tests without running them, and anything after `--` goes to `sultanc test` as it is.

## Cache

Fetched repositories live in `~/.supax/git` (or `$SUPAX_HOME/git`). Each repository has a lock file, so two Supax processes never write the same repository at once: the second one prints `Blocking` and waits. `supax cache clean` deletes the cache, but refuses while another Supax process is using it; anything needed is fetched again on the next build.

## Safety

- Supax never runs anything that comes from a fetched package: no build scripts, git hooks, filters, fsmonitor or `ext::` transport.
- Checkouts ignore system and user git configuration and never create symbolic links.
- Every cached checkout is read-only and has a SHA-256 checksum. It is verified before every use and compared with the checksum recorded in `Supax.lock`.
- A path dependency inside a git package cannot leave its repository.
- Names with hidden direction or zero-width characters are refused. So are names that become one name after identity folding (tatweel removed; آ أ إ folded to ا) while pointing to different packages.

## Source layout

| Folder | Contents |
|---|---|
| `src/main.sn` | Entry point |
| `src/cli/` | Argument parsing, help, command dispatch, project discovery |
| `src/project/` | `new`, `init`, manifest edits, `migrate` |
| `src/manifest/` | `Supax.toml`, `[workspace]` and TOML reading |
| `src/resolve/` | Graph model, resolution, checks, `Supax.lock`, dependency map, tree |
| `src/registry/` | Version requirements and the package index |
| `src/source/` | Git sources |
| `src/cache/` | Cache and checksums |
| `src/build/` | Running the compiler, the project's programs |
| `src/support/` | Text, name and message helpers |
| `tests/run.sh` | Tests |
| `tests/unit/` | Unit tests: a package that depends on Supax itself |
| `tools/` | Installers (`install.sh`, `install.ps1`) |

## Install

```sh
tools/install.sh ../sultanc      # after building the compiler in ../sultanc
```

On Windows (PowerShell; not yet tested on a Windows machine):

```powershell
powershell -ExecutionPolicy Bypass -File tools\install.ps1 -Checkout ..\sultanc
```

It installs into `%USERPROFILE%\.supax` and adds `.supax\bin` to the user `PATH` (`-NoModifyPath` skips that).

The script installs `sultanc` and `supax` into `~/.supax/bin` and the standard library into `~/.supax/lib/sultanc/library`, and adds `~/.supax/bin` to `PATH` in your shell profiles (`~/.zshenv`, `~/.profile`, `~/.bashrc`), so a new terminal is all you need. Pass `--no-modify-path` to skip that. Supax looks for the compiler in this order: `SULTANC`, next to Supax itself, `~/.supax/bin`, then `PATH`.

## Build and test

```sh
mkdir -p build/bin
sultanc --package-graph=bootstrap/package-graph.toml src/main.sn -o build/bin/supax   # first build (older compilers: drop --package-graph)
build/bin/supax build                      # from then on, Supax builds itself
SULTANC=sultanc bash tests/run.sh
```

Supax needs `git` in `PATH` and SultanC from 2026-11-16 or newer, from `SULTANC` or from `PATH`.
