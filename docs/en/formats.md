[العربية](../ar/formats.md) | **English**

# Supax file formats

## `Supax.toml` dependencies

```toml
[dependencies]
mathx = "1.2"                                   # from the package index
color = { version = "~0.4" }                    # the same, as a table
json = { git = "https://github.com/someone/sn-json", tag = "v1.2.0" }
http = { git = "https://github.com/someone/sn-http", branch = "main" }
base = { git = "https://github.com/someone/sn-base", rev = "3f9c2e1" }
tool = { git = "https://github.com/someone/sn-tool" }
log  = { path = "../log" }
```

| Field | Meaning |
|---|---|
| `version` | A version requirement, resolved through the package index. Exactly one of `version`, `path` or `git` |
| `path` | A local package, relative to this manifest |
| `git` | `https://`, `http://`, `ssh://`, `file://` or `user@host:path` |
| `tag`, `branch`, `rev` | At most one. With none, the remote's default branch is used. `rev` is 7–64 hex characters. |

Rules:

- The dependency key must equal the package's `[package].name` or one of its `[package.names]` spellings. This applies to git dependencies.
- Every dependency must declare `[lib]`.
- One commit per repository in the whole graph. Two requests that reach different commits are a conflict.
- `[package].build` is refused, because Supax never runs package code.
- One version per compatible range of an index package (`1.x`, `0.3.x`, `0.0.4`), as in Cargo: `1.x` for one importer and `2.x` for another live side by side. Two requirements in the same range with no common version are a conflict.

### Version requirements

The same rules as Cargo:

| Requirement | Allows |
|---|---|
| `"1.2.3"` or `"^1.2.3"` | `>=1.2.3, <2.0.0` |
| `"^0.2.3"` | `>=0.2.3, <0.3.0` |
| `"^0.0.3"` | `>=0.0.3, <0.0.4` |
| `"1.2"` | `>=1.2.0, <2.0.0` |
| `"~1.2.3"` | `>=1.2.3, <1.3.0` |
| `"=1.2.3"` | `1.2.3` only |
| `">=1.2, <1.5"` | every comparator at once |
| `"*"`, `"1.*"`, `"1.2.*"` | wildcards |

A pre-release (`1.5.0-beta.1`) is picked only when the requirement itself names a pre-release with the same `major.minor.patch`. A yanked version is never picked for a new lock, but a lock that already has it keeps working.

## Package index

The index is a git repository with one file per package. The default is `https://github.com/sultan-language/index`; `SUPAX_INDEX` points Supax at another one (any git URL, including `file://`). The index does not host code: each version points to a git repository, a commit and a content checksum.

The repository root holds only `README.md`, `config.toml` (`version = 1`, the format version) and `packages/`. File path inside `packages/`, from the name after identity folding and ASCII lower-casing (the Cargo layout):

| Name | Path |
|---|---|
| 1 character | `packages/1/<name>.toml` |
| 2 characters | `packages/2/<name>.toml` |
| 3 characters | `packages/3/<first character>/<name>.toml` |
| 4 or more | `packages/<characters 1–2>/<characters 3–4>/<name>.toml` |
| not ASCII (Arabic and others) | `packages/hash/<first 2 of the hash>/<sha256 of the name>.toml` |

A newer `version` in `config.toml` makes Supax stop and ask to be updated.

Non-ASCII names use the hash so every file name in the index is ASCII: macOS stores some Arabic letters (أ, إ, آ) decomposed, which breaks git paths.

```toml
name = "mathx"

[[versions]]
version = "1.2.0"
git = "https://github.com/someone/mathx"
commit = "d5921a779bc910a23dad23714369f718edbb2540"
checksum = "sha256:ecfbacdd291dd749cdbd798543f204e8293c87bcfda58621aa22c78d1755d5f5"

[[versions]]
version = "1.4.0"
git = "https://github.com/someone/mathx"
commit = "…"
checksum = "sha256:…"
yanked = true
```

Supax checks the fetched content against `checksum`, and the `version` in that commit's `Supax.toml` against the index. The index is fetched once per command, and only when a requirement is not already met by `Supax.lock`.

### Adding a version

`supax package` (run in the package's repository) prints the file path and the `[[versions]]` entry for `HEAD`, with the checksum computed exactly as a fetch computes it. Push the commit, then add the entry to that file in the index repository.

## `Supax.lock`

Written by Supax only, and identical whatever message language is used. The root package comes first, then the others sorted by name and source.

```toml
# يكتب سوباكس هذا الملف تلقائيا؛ لا تعدّله يدويا. Written by Supax; do not edit by hand.
version = 1

[[package]]
name = "app"
version = "0.1.0"
source = "root"
dependencies = ["json", "log"]

[[package]]
name = "json"
version = "1.2.0"
source = "git"
git = "https://github.com/someone/sn-json"
tag = "v1.2.0"
commit = "2f3a589624b5a839fe13a27ad52323a4e5edabf4"
checksum = "sha256:80d03f48f971bf104d3f3e46eefaba7c54bfa846be17d257847ec7659fe90680"
dependencies = ["base"]

[[package]]
name = "log"
source = "path"
path = "../log"
```

| Field | Meaning |
|---|---|
| `source` | `root`, `path`, `git` or `registry` |
| `registry` | For `registry`: the index URL. The entry also keeps `git`, `commit` and `checksum`, so a pinned build never reads the index |
| `commit` | The full commit the reference resolved to |
| `checksum` | The content checksum of that commit's files (below) |
| `subdirectory` | Set for a path package inside a git repository |
| `dependencies` | Package names; `"name version"` when the graph has two versions of that package |

In a workspace there is one `Supax.lock`, at the workspace root, and every member is a `source = "root"` entry.

A pinned entry is reused as long as its repository and reference are unchanged; an index entry, as long as its version still meets the requirement and the index URL is the same. `supax update` ignores the pins, and `supax update NAME` ignores only that one.

## Content checksum

`sha256:` followed by the SHA-256 of one line per regular file, sorted bytewise:

```
<relative path with />\0<SHA-256 of the file content, hex>\n
```

`.git` at the root is ignored. Symbolic links and special files are refused.

## Cache

Under `$SUPAX_HOME/git` (default `~/.supax/git`):

| Path | Content |
|---|---|
| `db/<h16>` | A bare repository per git URL identity |
| `checkouts/<h16>/<commit>` | A checkout. Its files are read-only. |
| `checkouts/<h16>/<commit>.sha256` | The checksum of that checkout, verified before every use |

`<h16>` is the first 16 hex characters of the SHA-256 of the URL identity. The identity is the URL with scheme and host lower-cased and a trailing `/` or `.git` removed.

## Package graph

Written to `build/supax/package-graph.toml` by `check`, `build` and `run`, and passed as `sultanc --package-graph=<absolute path>`. `supax metadata` prints it; `--output=<file>` writes it, and `--relative` makes paths relative to that file's folder. The format and every field are described in [compiler-integration.md](../compiler-integration.md).

## Dependency map (older compilers)

Written to `build/supax/dependency-map.toml` when the graph has git dependencies, and passed to `sultanc --dependency-map`. See [compiler-integration.md](../compiler-integration.md).
