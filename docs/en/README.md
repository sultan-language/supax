[العربية](../../README.md) | **English**

# Supax

The SultanC package manager, written in SultanC.

Supax reads `Supax.toml`, resolves and fetches dependencies into an immutable cache, verifies their content, writes `Supax.lock`, and hands the compiler one resolved directory per dependency. Language and module semantics stay with the compiler.

## Getting started

```sh
supax new my_app
cd my_app
supax run
```

## Commands

| Command | Arabic | What it does |
|---|---|---|
| `supax new <name>` | `supax جديد` | Create a package in a new directory |
| `supax init [name]` | `supax هيئ` | Create a package in the current directory |
| `supax add <name>[@<version>]`, or `<name> --path <path>`, or `<name> --git <url> [--tag <tag>]` | `supax أضف` | Add a dependency to `Supax.toml` and update `Supax.lock`; nothing changes if it fails. Without `@<version>`, the newest release in the index |
| `supax remove <name>` | `supax احذف` | Remove a dependency and update `Supax.lock` |
| `supax fetch` | `supax جلب` | Resolve and fetch dependencies, write `Supax.lock` |
| `supax update [name...]` | `supax حدث` | Re-resolve, ignoring pins (all, or the named ones) |
| `supax tree` | `supax شجرة` | Show the dependency graph |
| `supax metadata [--output=<file>] [--relative]` | `supax بيانات` | Write the package graph the compiler reads |
| `supax verify` | `supax تحقق` | Check the cache against `Supax.lock`, offline |
| `supax check` | `supax افحص` | Check the project with the compiler |
| `supax build` | `supax ابن` | Build the project into `build/bin/` |
| `supax run [--bin <name>] [-- args]` | `supax شغل` | Build the project, then run one program |
| `supax test [text]` | `supax اختبر` | Run the tests (`@@test` functions) through `sultanc test`: the lib, each program, then each `tests/*.sn`. `text` keeps only tests whose name contains it |
| `supax clean` | `supax نظف` | Remove the `build/` directory |
| `supax package [--git <url>]` | `supax حزّم` | Check this release (clean tree, `[lib]`, semantic version, no path dependencies) and print its `[[versions]]` entry and file path for the package index |
| `supax migrate` | `supax رحّل` | Move `[imports-alias]` into `وحدة` lines in the root files (the compiler no longer reads it) |
| `supax cache [info \| clean]` | `supax مخبأ` | Show the git cache (folder, repositories, checkouts, size), or delete it |

| Option | What it does |
|---|---|
| `--locked` | Fail if `Supax.lock` would change |
| `--offline` | Never use the network; use only the cache |
| `--frozen` | `--locked` and `--offline` together |
| `--release` | Optimized build, passed to the compiler |
| `--bin <name>` | Build or run only this program |
| `--package <name>`, `-p` | One member of the workspace |
| `--target <target>`, `-t` | Target platform; output in `build/bin/<target>/` |
| `--quiet`, `-q` | No status lines (Compiling, Finished, Running) |
| `--lang=ar\|en` | Message language (default Arabic); also `SUPAX_LANG` |

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

## Programs

A project can hold more than one program:

| File | Program | Output |
|---|---|---|
| `src/main.sn` | the package name | `build/bin/<package>` |
| `src/bin/<name>.sn` | `<name>` | `build/bin/<name>` |

`supax build` builds all of them; `--bin <name>` builds one. `supax run` runs `src/main.sn`; if there is no `src/main.sn` and more than one program, pass `--bin`. On Windows the output ends in `.exe`.

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
| test | each `tests/<name>.sn`, a separate program that imports the library by its name | `--test <name>` |

The compiler finds tests in the file and everything it imports, so a library's root file should import its modules. In a package with `[lib]`, a program runs only the tests in its own file, so the library's tests run once (SultanC `000493c` or newer). A failing target stops the run and prints the option that reruns it; `--no-fail-fast` runs every target first. `--list` lists the tests without running them, and anything after `--` goes to `sultanc test` as it is. Needs SultanC `3b441bc` or newer.

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

Supax needs `git` in `PATH` and SultanC `694867b` or newer, from `SULTANC` or from `PATH`.

## Status

Phase 1 is complete: git dependencies, `Supax.lock`, and building and running through the compiler, including git dependencies that have git dependencies of their own. Phase 2 has started: version requirements resolved through a git package index. To publish, run `supax package`, push the commit, and add the printed entry to the index repository; there is no upload step yet. Supax needs SultanC `694867b` or newer; the integration is described in [compiler-integration.md](../compiler-integration.md).
