<div align="center">
<img src="https://raw.githubusercontent.com/sultan-language/sultanc-vscode/main/icons/sultanc-logo.svg" alt="SultanC" width="100">

[العربية](../../README.md) | **English**

# Supax

**The package manager for SultanC, written in SultanC.**

<p>
<img src="https://img.shields.io/badge/written%20in-SultanC-1a7f37?style=for-the-badge&labelColor=0d1117" alt="Written in SultanC">
<img src="https://img.shields.io/badge/messages-Arabic%20%2B%20English-8957e5?style=for-the-badge&labelColor=0d1117" alt="Messages">
<img src="https://img.shields.io/badge/macOS%20%7C%20Linux-yes-1a7f37?style=for-the-badge&labelColor=0d1117" alt="Platforms">
<img src="https://img.shields.io/badge/license-MIT-8b949e?style=for-the-badge&labelColor=0d1117" alt="License">
</p>

[Install](#install) &nbsp;·&nbsp; [Get started](#get-started) &nbsp;·&nbsp; [What it does](#what-it-does) &nbsp;·&nbsp; [Guide](guide.md) &nbsp;·&nbsp; [Package index](https://github.com/sultan-language/index)

</div>

<br>

Supax is what you type after `sultanc`. It creates the project, fetches its dependencies from the package index or from git, pins them in `Supax.lock` so the project builds tomorrow exactly as it built today, then builds, runs and tests it. It is itself a SultanC program that builds itself, and it speaks Arabic first.

<br>

<table>
<tr><th width="55%"><code>Supax.toml</code></th><th width="45%"><code>src/main.sn</code></th></tr>
<tr>
<td valign="top">

```toml
[package]
name = "my_store"
version = "0.1.0"

[dependencies]
nahr  = "0.1"
json  = { git = "https://github.com/x/json" }
utils = { path = "../utils" }
```

</td>
<td valign="top">

```
import std.io.println;

def main(): int {
    println("Hello from SultanC");
    return 0;
}
```

</td>
</tr>
</table>

## Install

After building the compiler ([sultanc](https://github.com/sultan-language/sultanc)) in a sibling folder:

```sh
git clone https://github.com/sultan-language/supax.git && cd supax
tools/install.sh ../sultanc
```

The script puts `supax`, `sultanc` and the standard library in `~/.supax` and adds it to your `PATH`; open a new terminal and you are set. On Windows: `tools\install.ps1`.

## Get started

```console
$ supax new my_store && cd my_store
$ supax add nahr
    Fetching https://github.com/sultan-language/index
       Added nahr = "0.1.0"
$ supax run --lang=en
   Compiling my_store v0.1.0
    Finished in 2.74s → build/bin/my_store
     Running build/bin/my_store
```

## What it does

| Feature | What it means |
|---|---|
| **A package index** | `nahr = "0.1"` is enough. Versions resolve through the [index](https://github.com/sultan-language/index) with the same semantic-versioning rules Cargo uses |
| **Reproducible builds** | `Supax.lock` pins every commit and checksum; after the first fetch, builds work offline (`--offline`) |
| **Verified content** | Every package has a SHA-256 checksum checked before each use, and Supax never runs code from a fetched package |
| **Workspaces** | Several packages in one repository, one lock, one `build/` |
| **Tests** | `supax test` runs the `@@test` functions in the library, the programs and `tests/`; `tests/` files get their own `[dev-dependencies]` |
| **Arabic names** | Packages, programs and modules can have Arabic names, with protection against look-alike names and hidden characters |

## Everyday commands

| Command | What it does |
|---|---|
| `supax new <name>` | A new project |
| `supax add <name>` | Add a dependency from the index, or with `--git` or `--path` |
| `supax build` / `run` / `test` | Build, run, test |
| `supax fmt` | Format the sources (`--check` for CI) |
| `supax install` / `uninstall` | Install a package's programs into `~/.supax/bin`, or remove them |
| `supax update` | Move dependencies to the newest compatible versions |
| `supax tree` | The dependency tree |
| `supax package` | Prepare a release for the index |

Every command also has an Arabic name (`supax ابن`, `supax شغل`, …). The full list, with every option, is in the [guide](guide.md).

## Documentation

| Page | What it covers |
|---|---|
| [Guide](guide.md) | Every command and option, programs, workspaces, tests, the cache, safety |
| [File formats](formats.md) | `Supax.toml`, `Supax.lock` and the package index |
| [Compiler integration](../compiler-integration.md) | The package graph Supax hands to `sultanc` |

## Contributing

```sh
# first build
sultanc --package-graph=bootstrap/package-graph.toml src/main.sn -o build/bin/supax

# from then on, Supax builds itself
build/bin/supax build

SULTANC=sultanc bash tests/run.sh
```

Supax needs `git` and SultanC from 2026-11-16 or newer: the snapshot that splits the standard library into `core`, `alloc` and `std`.

<br>

<div align="center">

[License: MIT](../../LICENSE)

</div>
