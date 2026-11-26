# Supax ↔ sultanc integration (phase 1)

## Current contract: the package graph

The compiler no longer reads `Supax.toml`. Supax validates every manifest rule (see `src/manifest/manifest.sn`), resolves the graph, and hands the compiler `build/supax/package-graph.toml` through `--package-graph=<absolute path>`. `supax metadata [--output=<file>] [--relative]` prints or writes the same file.

```toml
version = 1
root = "app"

[[package]]
id = "app"
source_root = "/abs/app"            # the [lib] folder, or the manifest folder without [lib]
name = "app"
spellings = { ar = "تطبيق" }        # [package.names]
entry = "util"                      # only when [lib] path names a file: its module name

[[edge]]
from = "app"
to = "util"
name = "util"                       # the dependency key
```

Decisions Supax made where the request left a detail open. Tell the Supax owner if the compiler expects otherwise:

| Detail | Supax writes (accepted by the compiler) |
|---|---|
| `id` | The package name; on a clash, `name@<commit12>` for git or `name@<relative path>` for a path package; then `#<n>` if still equal |
| `spellings` | `[package.names]` only. The `name` field and each edge's `name` (the dependency key) are separate. |
| Relative paths (`--relative`) | Relative to the folder holding the graph file |
| Order | Root package first, then by name and source; edges by `from` then `name` |
| std | Never listed |

Supax checks identifiers with the compiler's character rules (`identifiers.sn`) but not the reserved-word list; the compiler rejects a reserved word when it reads the graph (`كلمة_محجوزة_في_رسم_حزم`), at the field's line.

### Module spellings: root files, not the graph

Since `e1d4bca` the graph has no `[[alias]]` (the compiler rejects it). A package declares its module spellings in its own source: the root file `<source_root>/<package name>.sn` names its direct children, and a folder's root file `FOLDER/FOLDER.sn` names its own:

```
module helpers { ar: مساعدات };      // src/app.sn
module number { ar: رقم };           // src/text/text.sn, for text.number
```

`[imports-alias]` in `Supax.toml` is deprecated. Supax still validates it, but no longer passes it on; when the root package has one, every command prints a warning with the exact `module` line and the file it belongs in. A `supax migrate` that writes those lines is possible later. `tests/run.sh` builds and runs a project that uses root-file spellings, including a dotted one.

Supax's own build uses the checked-in `bootstrap/package-graph.toml` (relative paths):

```sh
sultanc --package-graph=bootstrap/package-graph.toml src/main.sn -o build/supax
```

Supax detects the contract by running `sultanc --package-graph` with no value: an older compiler answers `SULTANC-CLI-UNKNOWN-OPTION` (the code is the same in every language), and then Supax falls back to the previous contract below, where the compiler reads `Supax.toml` and git dependencies go through `--dependency-map`.

### SultanC 2026-11-16: the standard library in three layers

The snapshot `SultanC_20261116_static_env_core_moves` splits the standard library into `core`, `alloc` and `std` (`docs/en/reference/std-layers.md` in the compiler). std re-exports the moved modules, so every path Supax imported still resolved; nothing in the package graph changed.

Supax follows the compiler's own convention from this snapshot: Arabic sources import the standard library with its Arabic spellings throughout (`المكتبة.نصوص.من_بايتات`, not `المكتبة.نصوص.from_bytes`). The spellings come from the library's root files, so older compilers, which lack some of them, can no longer build Supax: this snapshot is the minimum. The template of `supax new` imports `المكتبة.دخ.اطبع_سطر` in Arabic and `std.io.println` in English.

Both installers copy the whole `library/` folder, so `core` and `alloc` are installed beside `std` with no change.

Verified on this snapshot (built with `./build.sh --bootstrap=wasm`; the previous compiler cannot build it):

- `tests/run.sh`: 156/156.
- Supax builds itself (`build/bin/supax build`).
- `tools/install.sh` into an empty home, then `supax new` and `supax run` in Arabic and in English.
- `supax add nahr@0.1.0-dev` from the index, then building Nahr's Arabic example and serving a request from it.

### The Arabic comma (SultanC `SultanC_main_20261125_patterns`)

`sultanc fmt` now writes `،` (U+060C) between list items in an Arabic source and `,` in an English one; both compile. Supax's sources were reformatted with it, and the Arabic `supax new --lib` template writes `اجمع(الأول: عدد، الثاني: عدد)`, so a new library is formatted from the start. `final8` and older compilers reject `،` (`SULTANC-LEX-INVALID-TOKEN`), so Supax now needs this checkpoint or newer. `tests/run.sh` passes 218/218 on it.

The compiler no longer has `--release`, and without `-O` it optimizes nothing ("a package manager's build profile chooses a level and passes it as `-O`"). `supax build|run|test|install --release` now pass `-O3`, as Cargo's release profile (`opt-level = 3`); a normal build passes no `-O` (`-O0`), as Cargo's dev profile.

The checkpoint also adds a compilation cache (`compiler/driver/compile_cache.sn`): `sultanc` stores each compilation's output under the identity of the compiler, the request (the package graph by content included) and every source it read, in `SULTANC_CACHE` or the user cache directory; `--no-cache` skips it. Supax passes nothing for it and needs no change: a changed dependency changes the sources or the graph, so a stale output cannot be reused.

### `ليكن` replaces `دع` (SultanC `SultanC_main_20261123_final8`)

Since this checkpoint the binding keyword is `ليكن`, and `دع` has no deprecated alias: the compiler rejects it. Supax's Arabic sources and docs were rewritten with the compiler's lexer-based tool, `tools/rename/rename_tokens.py --wave 8` (`دع` → `ليكن`): 1269 keyword tokens; strings, comments and longer identifiers were left alone. The tool skips folders named `build`, so `src/build/*.sn` was passed by file. Supax therefore needs `final8` or newer; on `final2` it stops with `SULTANC-PARSE-SYNTAX` at the first `ليكن`. Apart from the rename, the compiler's command line, package graph and std location are unchanged. The D1 row below keeps `دع`, as it was reported.

### SultanC 2026-11-19 (`SultanC_main_20261119_interp1_ci`)

Nothing in the contract changed: the package graph, `sultanc test` and its options, and the std paths Supax imports are the same. `tests/run.sh` passes 217/217. Supax changes in this round, all on its own side:

| Change | Compiler side |
|---|---|
| `[dev-dependencies]` | None. They are resolved and locked like other dependencies; their edges are left out of `package-graph.toml` and written only to the graphs `supax test` passes: `test-graph.toml` (a package with `[lib]`; the `tests` package also gets an edge to each of the root's dependencies) and `dev-graph.toml` (a package without `[lib]`). Programs and the library are tested with the build graph, so a file in `src/` cannot import a dev-dependency |
| `supax new --lib` | None |
| `<name>.wasm` for WebAssembly targets | None: Supax passes the name with `-o` |
| `supax fmt [--check]` | `sultanc fmt [--check] <paths>`: `src/`, `tests/`, a root `main.sn`, the `[lib]` folder if outside `src/`. Status 1 from `--check` is passed on |
| `--message-format`, `--color` | Passed as `--diagnostic-format=<human\|short\|json>` and `--color=<auto\|always\|never>` to `check`, builds, `test` and `fmt`. The compiler writes JSON to standard error, where Supax's status lines also go, so `json` turns those lines off |
| `supax publish`, `yank` | None: both work on the git index. `publish` uploads nothing until the registry website exists |
| `supax install`, `uninstall` | None: a normal `--release` build, then Supax copies the programs. A git or index package is resolved with the `[lib]` requirement lifted for that one package |

The compiler now names the missing module in `SULTANC-MODULE-NOT-FOUND`, for example: The missing source module is `helper.lib`.

### Verified with SultanC `7b00d69`

- Supax builds from `bootstrap/package-graph.toml`, then rebuilds itself through `--package-graph`.
- `tests/run.sh` passes 69/69, including a project whose git dependency has its own git dependency. It also passes on `e8d68f0`, through the fallback.
- `tools/install.sh` installs and runs a new project with either compiler.

### Verified with SultanC `e1d4bca`

- std is found by its layout (`library/std/`), with no description file; `tools/install.sh` installs it to `~/.supax/lib/sultanc/library/std` and the installed compiler finds it.
- `tests/run.sh` passes 69/69; a fresh install creates, builds and runs a new project.

### `supax test` on SultanC `3b441bc`

Supax runs `sultanc test --lang=<ar|en> --package-graph=<graph> [--filter=<text>] [--list] [--target …] [--release] <file>` once per target: the library's root file, each program, and each `tests/*.sn`. For a package with `[lib]`, `tests/` is outside the library's `source_root`, so Supax writes `build/supax/test-graph.toml`: the same graph with an extra root package (`id = "<root> tests"`, `source_root = <project>/tests`, `name = "tests"`) and an edge from it to the library under the package's name. Status 1 from the compiler is a failed test; 2 and above stop Supax with that status. `tests/run.sh` passes 135/135 on `3b441bc` and 125/125 on `e1d4bca` (the test section is skipped there).

**Fixed in `bf8eab2`:** only the root package's tests run, so a `tests/*.sn` file that imports the library no longer runs the library's tests. `tests/run.sh` checks this and passes 136/136 on `bf8eab2`.

**Done in `000493c`:** `--tests-in=<file>`. For a package with `[lib]`, Supax passes each program's own file for bin targets, so the library's tests run once, in the lib target, as in Cargo. Supax checks for the option first (`sultanc test --tests-in` answers `SULTANC-CLI-MISSING-OPTION-VALUE` when it exists), so older compilers still work and only repeat those tests. `tests/run.sh` passes 156/156 on `000493c` and on `bf8eab2`.

### Answers from the compiler (note received 2026-11-12)

| Note | Status |
|---|---|
| Reserved words in the graph | Rejected by the compiler at the field's line |
| `--package-graph` in `sultanc --help` | Fixed on branch supax-round (`02867f8`) |
| `std.time` Arabic spelling | Fixed in `02867f8` (`المكتبة.وقت`); Supax uses it since the 2026-11-16 snapshot |
| D2 keyword as a record field name | Fixed on master |
| D5 byte offsets | Fixed on master: `file:line:column` |
| `sultanc test` | Done in `3b441bc`; `supax test` uses it (below) |
| `..` in `source_root` | Normalized by the compiler (`0eaea16`); two packages in the same folder are an error |

Verified with `e1d4bca` after removing `[[alias]]`: `tests/run.sh` passes 100/100.

Programs are written to `build/bin/<name>`, so a package named `supax` does not clash with `build/supax/package-graph.toml`.

## Status (SultanC `694867b`)

| Item | Status |
|---|---|
| R1 git dependency entries | Done |
| R2 `--dependency-map` | Done |
| R3 diagnostics (`SULTANC-PACKAGE-GIT-DEPENDENCY-UNRESOLVED`, `SULTANC-PACKAGE-DEPENDENCY-MAP-INVALID`, git field checks) | Done, Arabic and English |
| D1 `&` on a top-level `نص` constant | Fixed |
| D2 keyword (`من`, `إلى`) as a record field name | Fixed: now `SULTANC-PARSE-SYNTAX` at the field, with its location (checked on the 2026-11-19 snapshot). A keyword is still not a field name |
| D3 compiling from inside `src/` | Fixed |
| D4 Arabic names for `process`, `env`, `crypto`, `toml`, `collections`, `version` | Done; Supax now imports `المكتبة.عمليات`, `المكتبة.بيئة` and the others |
| D5 manifest and map diagnostics report a byte offset (`byte 117`) | **Open, minor**: a line and column would be easier to read |

Supax needs SultanC `694867b` or newer: it uses the D4 module names, and git dependencies need R1 and R2. `tests/run.sh` builds and runs a project whose git dependency has its own git dependency.

The sections below are the original requests, kept for reference.

Supax resolves, fetches, verifies and locks dependencies. sultanc keeps ownership of package roots, spellings, import aliases, `[lib]` rules and module loading. Supax never rewrites manifests and never generates a substitute manifest. This document lists what the compiler must add, based on the code as of SultanC `6d75c1c`.

## What the compiler does today

| Where | Behavior |
|---|---|
| `compiler/driver/package_manifest.sn` `اقرأ_الاعتمادات` | A dependency value must be a table with exactly one key, `path` (otherwise `حقل_اعتمادية_غير_المسار`). The path must be relative and is joined to the manifest directory. |
| `compiler/driver/package_manifest.sn` `تحقق_جذر_البيان` | `[dev-dependencies]` must be empty. |
| `compiler/driver/package_environment.sn` `سجل_حزمة_اعتماد` | Reads `<path>/Supax.toml`, requires `[lib]` (`اعتماد_مسار_بلا_هدف_مكتبة`), deduplicates packages by manifest path, reports cycles (`دورة_اعتماديات_الحزمة`), and registers the dependency key, the package name and every `[package.names]` spelling under the importer. |
| `compiler/driver/cli.sn` | `--module-source=<module>=<file>` maps one module to one file. Nothing maps a dependency name to a directory. |

Result: a manifest with `json = { git = "...", tag = "..." }` is rejected before Supax can help, and there is no way to tell the compiler where Supax put the checkout.

## R1 — accept git dependency entries

In `اقرأ_الاعتمادات`, accept a dependency table of one of these shapes:

- `{ path = "<relative>" }`, unchanged;
- `{ git = "<url>" }`, optionally with exactly one of `tag`, `branch` or `rev`, all strings.

The compiler only checks the shape. It never fetches, never reads `Supax.lock`, and never touches the network. `اعتماد_مسار_حزمة` gains a source kind (path or git) so the environment step can tell them apart.

## R2 — `--dependency-map=<file>`

Add a CLI option, accepted in both the `--dependency-map=<file>` and `--dependency-map <file>` forms, for build, `check` and `run`. Supax writes the file to `build/supax/dependency-map.toml`:

```toml
version = 1

[[dependency]]
importer = "/abs/dir/of/the/importing/Supax.toml"
name = "json"
directory = "/home/u/.supax/git/checkouts/697c0c181908b203/2f3a5896…"
```

Semantics, in `سجل_حزمة_اعتماد` and `جهز_بيئة_حزم_لبيان_مشروع`:

1. A git dependency `name` declared in the manifest whose directory is `importer` resolves to `directory`. Compare directories after `مسار_قانوني`.
2. From there, the existing logic runs unchanged: read `<directory>/Supax.toml`, require `[lib]`, deduplicate, detect cycles, register spellings.
3. Path dependencies ignore the map.
4. A git dependency with no map entry is a new diagnostic (see R3). It must not fall back to anything.
5. `version` other than `1` is a diagnostic.

**Why a file and not one flag per dependency:** sultanc compiles the whole graph in one run, so entries are keyed by (importer, name), not by name alone. The paths can also contain `=` and `:`.

## R3 — diagnostics through iSpeak

New keys in `compiler/ispeak/keys/surface` with `ar` and `en` surfaces, for example:

| Key (suggested) | When |
|---|---|
| `اعتمادية_جت_غير_محلولة` | A git dependency has no entry in the map, or no map was given. Help text: run `supax fetch` or build through `supax build`. |
| `خريطة_اعتماديات_غير_صالحة` | The map file is unreadable, has bad TOML, the wrong `version`, or a missing field. |
| `حقل_اعتمادية_جت_غير_صالح` | A git dependency has an unknown key, a non-string value, or more than one of `tag`, `branch` or `rev`. |

## Verified before the change

With the `6d75c1c` compiler, `supax check` on a project with a git dependency writes the map and then stops at:

```
خطأ[SULTANC-CLI-UNKNOWN-OPTION]: خيار غير معروف `--dependency-map=…/build/supax/dependency-map.toml`
```

Projects with only path dependencies build, check and run through Supax today.

## Compiler defects found while writing Supax

| # | Reproduction | Result |
|---|---|---|
| D1 | `دع الاسم: نص = «x»;` at top level, then `انسخ_نص(&الاسم)` inside a function | `SULTANC-ICE-LOWERING-UNSUPPORTED-EXPRESSION` |
| D2 | `نوع حافة = { من: عدد, إلى: عدد };` | `SULTANC-ICE-PARSER-NO-RESULT` with no location. A parameter named `من` correctly reports `SULTANC-PARSE-SYNTAX`. |
| D3 | `cd src && sultanc check main.sn`, where `src/` is `[lib] path` | `SULTANC-MODULE-NOT-FOUND` for the project's own modules. `sultanc check src/main.sn` from the project root works. |
| D4 | `library/Supax.toml` `[imports-alias]` | No Arabic spelling for `process`, `env`, `crypto`, `toml`, `collections` or `version`, so Arabic code must write `المكتبة.process.command`. |
