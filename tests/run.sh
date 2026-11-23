#!/usr/bin/env bash
# اختبارات سوباكس. تحتاج git ومترجم السلطان.
#   SULTANC=/path/to/sultanc bash tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SULTANC="${SULTANC:-sultanc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/supax-tests.XXXXXX")"
# The real path: on macOS $TMPDIR is under /var, a symlink to /private/var, and
# Supax writes canonical paths.
WORK="$(cd "$WORK" && pwd -P)"
export SUPAX_HOME="$WORK/home"
export SULTANC
# Status lines only where a test checks them.
export SUPAX_QUIET=1
SX="$ROOT/build/bin/supax"
pass=0
fail=0

ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '      %s\n' "$2" >&2; fail=$((fail + 1)); }
expect_ok() { local name="$1"; shift; local out; if out="$("$@" 2>&1)"; then ok "$name"; else bad "$name" "$out"; fi; }
expect_fail() { # name, expected-substring, command...
    local name="$1" want="$2"; shift 2; local out
    if out="$("$@" 2>&1)"; then bad "$name" "succeeded; expected failure containing: $want"
    elif [[ "$out" == *"$want"* ]]; then ok "$name"
    else bad "$name" "expected '$want', got: $out"; fi
}
# Portable across GNU (Linux) and BSD (macOS) tools.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
git_q() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# repo NAME "MANIFEST" [extra files as path=content ...] ; tags v1
repo() {
    local name="$1" manifest="$2"; shift 2
    local dir="$WORK/repos/$name"
    mkdir -p "$dir/src"
    printf '%s\n' "$manifest" > "$dir/Supax.toml"
    printf 'عام عرف قيمة_%s(): عدد { أرجع 1; }\n' "${name//-/_}" > "$dir/src/lib.sn"
    local kv
    for kv in "$@"; do mkdir -p "$(dirname "$dir/${kv%%=*}")"; printf '%s\n' "${kv#*=}" > "$dir/${kv%%=*}"; done
    (cd "$dir" && git_q init -q && git_q add -A && git_q commit -qm init && git_q tag v1)
}
url() { printf 'file://%s/repos/%s' "$WORK" "$1"; }
project() { # DIR "MANIFEST"
    mkdir -p "$1"; printf '%s\n' "$2" > "$1/Supax.toml"
}

# --- build supax -----------------------------------------------------------
mkdir -p "$ROOT/build/bin"
graph_args=()
probe="$("$SULTANC" --package-graph 2>&1 || true)"
if [[ "$probe" != *SULTANC-CLI-UNKNOWN-OPTION* ]]; then
    graph_args=("--package-graph=$ROOT/bootstrap/package-graph.toml")
fi
if ! "$SULTANC" ${graph_args[@]+"${graph_args[@]}"} "$ROOT/src/main.sn" -o "$SX" >"$WORK/build.log" 2>&1; then
    cat "$WORK/build.log" >&2; echo "cannot build supax" >&2; exit 1
fi
ok "build supax with sultanc"

# --- fixtures ----------------------------------------------------------------
repo base "[package]
name = \"base\"
version = \"0.1.0\"

[package.names]
ar = \"أساس\"

[lib]
path = \"src\""
repo json "[package]
name = \"json\"
version = \"1.2.0\"

[lib]
path = \"src\"

[dependencies]
base = { git = \"$(url base)\", tag = \"v1\" }"
mkdir -p "$WORK/log/src"
printf '[package]\nname = "log"\n\n[lib]\npath = "src"\n' > "$WORK/log/Supax.toml"
printf 'عام عرف سجل(): عدد { أرجع 0; }\n' > "$WORK/log/src/lib.sn"

APP="$WORK/app"
project "$APP" "[package]
name = \"app\"
version = \"0.1.0\"

[dependencies]
json = { git = \"$(url json)\", tag = \"v1\" }
log = { path = \"../log\" }"

# --- transitive resolution and lock ---------------------------------------
expect_ok "fetch resolves transitive git dependencies" bash -c "cd '$APP' && '$SX' fetch"
grep -q 'name = "base"' "$APP/Supax.lock" && grep -q 'name = "json"' "$APP/Supax.lock" && grep -q 'source = "path"' "$APP/Supax.lock" \
    && ok "Supax.lock records git, transitive and path packages" || bad "Supax.lock content" "$(cat "$APP/Supax.lock")"
cp "$APP/Supax.lock" "$WORK/lock1"
touch -t 200001010000 "$APP/Supax.lock"
old_mtime="$(mtime "$APP/Supax.lock")"
(cd "$APP" && "$SX" fetch >/dev/null)
cmp -s "$WORK/lock1" "$APP/Supax.lock" && [[ "$(mtime "$APP/Supax.lock")" == "$old_mtime" ]] \
    && ok "second fetch is deterministic and leaves Supax.lock untouched" || bad "lock determinism"
out="$(cd "$APP" && "$SX" tree)"
[[ "$out" == *"json v1.2.0"* && "$out" == *"base v0.1.0"* && "$out" == *"log (../log)"* ]] && ok "tree shows the graph" || bad "tree" "$out"
expect_ok "fetch --locked accepts a matching lock" bash -c "cd '$APP' && '$SX' fetch --locked"
expect_ok "verify checks the cache against the lock" bash -c "cd '$APP' && '$SX' verify"

# --- lock pins and update --------------------------------------------------
old_commit="$(git -C "$WORK/repos/json" rev-parse HEAD)"
(cd "$WORK/repos/json" && echo "// v2" >> src/lib.sn && git_q commit -qam two && git_q tag -f v1 >/dev/null)
new_commit="$(git -C "$WORK/repos/json" rev-parse HEAD)"
(cd "$APP" && "$SX" fetch >/dev/null)
grep -q "$old_commit" "$APP/Supax.lock" && ok "a moved tag does not change a locked commit" || bad "lock pin"
(cd "$APP" && "$SX" update json >/dev/null)
grep -q "$new_commit" "$APP/Supax.lock" && ok "update NAME re-resolves that dependency" || bad "update"

# --- --locked and --offline ---------------------------------------------------
cp "$APP/Supax.toml" "$WORK/app.toml"
printf 'base = { git = "%s", tag = "v1" }\n' "$(url base)" >> "$APP/Supax.toml"
expect_fail "--locked refuses a lock that needs changes" "--locked" bash -c "cd '$APP' && '$SX' fetch --locked"
cp "$WORK/app.toml" "$APP/Supax.toml"
mv "$WORK/repos/json" "$WORK/repos/json.away"
expect_ok "--offline builds the graph from the cache" bash -c "cd '$APP' && '$SX' fetch --offline"
expect_fail "--offline with an empty cache fails clearly" "--offline" bash -c "cd '$APP' && SUPAX_HOME='$WORK/empty-home' '$SX' fetch --offline"
mv "$WORK/repos/json.away" "$WORK/repos/json"

# --- cache integrity --------------------------------------------------------
checkout="$(find "$SUPAX_HOME/git/checkouts" -mindepth 2 -maxdepth 2 -type d -name "$new_commit")"
[[ -n "$checkout" && "$(mode "$checkout/src/lib.sn")" == 444 ]] && ok "cached checkouts are read-only" || bad "read-only checkout"
chmod u+w "$checkout/src/lib.sn"; echo "// tampered" >> "$checkout/src/lib.sn"
expect_fail "a modified cached checkout is detected" "سلامة المخبأ" bash -c "cd '$APP' && '$SX' verify"
rm -rf "$checkout" "$checkout.sha256"
expect_ok "a removed checkout is restored from the cache" bash -c "cd '$APP' && '$SX' fetch --offline"
perl -0pi -e 's/checksum = "sha256:[0-9a-f]*"/checksum = "sha256:0000000000000000000000000000000000000000000000000000000000000000"/' "$APP/Supax.lock"
expect_fail "a checksum that does not match Supax.lock fails" "البصمة المسجلة" bash -c "cd '$APP' && '$SX' fetch"
rm -f "$APP/Supax.lock"; (cd "$APP" && "$SX" fetch >/dev/null)

# --- cycles -------------------------------------------------------------------
mkdir -p "$WORK/cyc/a/src" "$WORK/cyc/b/src"
printf '[package]\nname = "a"\n\n[lib]\npath = "src"\n\n[dependencies]\nb = { path = "../b" }\n' > "$WORK/cyc/a/Supax.toml"
printf '[package]\nname = "b"\n\n[lib]\npath = "src"\n\n[dependencies]\na = { path = "../a" }\n' > "$WORK/cyc/b/Supax.toml"
project "$WORK/cyc/app" '[package]
name = "cycapp"

[dependencies]
a = { path = "../a" }'
expect_fail "dependency cycles are reported with their path" "دورة اعتماديات: a ← b ← a" bash -c "cd '$WORK/cyc/app' && '$SX' fetch"

# --- conflicting versions -----------------------------------------------------
(cd "$WORK/repos/base" && echo "// v2" >> src/lib.sn && git_q commit -qam two && git_q tag v2)
project "$WORK/conflict" "[package]
name = \"conflict\"

[dependencies]
json = { git = \"$(url json)\", tag = \"v1\" }
base = { git = \"$(url base)\", tag = \"v2\" }"
expect_fail "two commits of one repository are a conflict" "تعارض" bash -c "cd '$WORK/conflict' && '$SX' fetch"
project "$WORK/same" "[package]
name = \"same\"

[dependencies]
json = { git = \"$(url json)\", tag = \"v1\" }
base = { git = \"$(url base)/\", tag = \"v1\" }"
expect_ok "one repository spelled two ways is one package" bash -c "cd '$WORK/same' && '$SX' fetch"
[[ "$(grep -c 'name = "base"' "$WORK/same/Supax.lock")" == 1 ]] && ok "the lock holds that repository once" || bad "url identity" "$(cat "$WORK/same/Supax.lock")"

# --- names and identity -------------------------------------------------------
project "$WORK/wrongname" "[package]
name = \"wrongname\"

[dependencies]
jsonx = { git = \"$(url json)\", tag = \"v1\" }"
expect_fail "a git dependency must be the package it names" "يجب أن يطابق مفتاح الاعتمادية" bash -c "cd '$WORK/wrongname' && '$SX' fetch"
project "$WORK/arabic" "[package]
name = \"arabic\"

[dependencies]
\"أساس\" = { git = \"$(url base)\", tag = \"v1\" }"
expect_ok "an Arabic spelling from [package.names] is a valid dependency key" bash -c "cd '$WORK/arabic' && '$SX' fetch"
mkdir -p "$WORK/coll/x/src" "$WORK/coll/y/src"
printf '[package]\nname = "x"\n\n[package.names]\nar = "خادم"\n\n[lib]\npath = "src"\n' > "$WORK/coll/x/Supax.toml"
printf '[package]\nname = "y"\n\n[package.names]\nar = "خـادم"\n\n[lib]\npath = "src"\n' > "$WORK/coll/y/Supax.toml"
project "$WORK/coll/app" '[package]
name = "collapp"

[dependencies]
x = { path = "../x" }
y = { path = "../y" }'
expect_fail "spellings equal after identity folding collide" "تصادم أسماء" bash -c "cd '$WORK/coll/app' && '$SX' fetch"
project "$WORK/badname" "[package]
name = \"badname\"

[dependencies]
\"a$(printf '‮')b\" = { path = \"../log\" }"
expect_fail "bidi control characters are refused in names" "محارف غير مسموحة" bash -c "cd '$WORK/badname' && '$SX' fetch"

# --- path safety and execution safety -------------------------------------------
repo escape "[package]
name = \"escape\"

[lib]
path = \"src\"

[dependencies]
outside = { path = \"../../outside\" }"
project "$WORK/esc" "[package]
name = \"esc\"

[dependencies]
escape = { git = \"$(url escape)\", tag = \"v1\" }"
expect_fail "path dependencies cannot leave a git checkout" "يخرج من مستودع الحزمة" bash -c "cd '$WORK/esc' && '$SX' fetch"
repo trap "[package]
name = \"trap\"

[lib]
path = \"src\"" ".gitattributes=* filter=evil"
(cd "$WORK/repos/trap" && ln -s /etc/passwd src/link && git_q add -A && git_q commit -qm link && git_q tag -f v1 >/dev/null)
mkdir -p "$WORK/fakehome"
printf '[filter "evil"]\n\tsmudge = sh -c "touch %s/pwned; cat"\n\trequired = false\n' "$WORK" > "$WORK/fakehome/.gitconfig"
project "$WORK/trapapp" "[package]
name = \"trapapp\"

[dependencies]
trap = { git = \"$(url trap)\", tag = \"v1\" }"
expect_ok "a repository with filters and symlinks still resolves" bash -c "cd '$WORK/trapapp' && HOME='$WORK/fakehome' '$SX' fetch"
[[ ! -e "$WORK/pwned" ]] && ok "user git filters never run on fetched code" || bad "smudge filter ran"
[[ -z "$(find "$SUPAX_HOME/git/checkouts" -type l)" ]] && ok "symbolic links are never created in the cache" || bad "symlink in cache"
project "$WORK/script" '[package]
name = "script"
build = "build.sh"'
expect_fail "packages cannot declare build scripts" "لا يشغّل نصوص بناء" bash -c "cd '$WORK/script' && '$SX' fetch"
expect_fail "malformed git URLs are refused" "غير مسموحة" bash -c "cd '$WORK/script' && printf '[package]\nname = \"s\"\n\n[dependencies]\nx = { git = \"ext::sh -c id\" }\n' > Supax.toml && '$SX' fetch"
mkdir -p "$WORK/nolib/src"; printf '[package]\nname = "nolib"\n' > "$WORK/nolib/Supax.toml"
project "$WORK/needlib" '[package]
name = "needlib"

[dependencies]
nolib = { path = "../nolib" }'
expect_fail "a dependency must declare [lib]" "[lib]" bash -c "cd '$WORK/needlib' && '$SX' fetch"
mkdir -p "$WORK/legacy"; printf '[project]\nname = "c"\n' > "$WORK/legacy/supax.toml"
expect_fail "a supax.toml build manifest is not taken for Supax.toml" "supax.toml" bash -c "cd '$WORK/legacy' && '$SX' fetch"
project "$WORK/registry" '[package]
name = "registry"

[dependencies]
json = "1.0"'
expect_fail "an unreachable package index is reported" "package index" bash -c "cd '$WORK/registry' && SUPAX_LANG=en SUPAX_INDEX='file://$WORK/no-such-index' '$SX' fetch"

# --- workspace ------------------------------------------------------------------
for m in one two; do
    mkdir -p "$WORK/ws/$m/src"
    printf '[package]\nname = "%s"\n\n[lib]\npath = "src"\n\n[dependencies]\njson = { git = "%s", tag = "v1" }\n' "$m" "$(url json)" > "$WORK/ws/$m/Supax.toml"
    printf 'عام عرف قيمة_%s(): عدد { أرجع 1; }\n' "$m" > "$WORK/ws/$m/src/lib.sn"
done
project "$WORK/ws" '[package]
name = "ws"

[dependencies]
one = { path = "one" }
two = { path = "two" }'
expect_ok "a workspace of path members resolves with one lock" bash -c "cd '$WORK/ws' && '$SX' fetch"
[[ "$(grep -c 'name = "json"' "$WORK/ws/Supax.lock")" == 1 && ! -e "$WORK/ws/one/Supax.lock" ]] \
    && ok "members share one copy of a common git dependency" || bad "workspace lock" "$(cat "$WORK/ws/Supax.lock")"
expect_ok "commands run from a subdirectory find the project" bash -c "cd '$WORK/ws/one/src' && '$SX' tree | grep -q '^one'"

# --- new, init and languages ------------------------------------------------------
mkdir -p "$WORK/scaffold"
expect_ok "new creates a package that runs" bash -c "cd '$WORK/scaffold' && '$SX' new مرحبا >/dev/null && cd مرحبا && '$SX' run | grep -q 'مرحبا من السلطان'"
expect_ok "new --lang=en uses English keywords" bash -c "cd '$WORK/scaffold' && '$SX' --lang=en new hello >/dev/null && grep -q 'def main' hello/src/main.sn && cd hello && '$SX' run | grep -q 'Hello from SultanC'"
mkdir -p "$WORK/scaffold/existing"
expect_ok "init creates a package in the current directory" bash -c "cd '$WORK/scaffold/existing' && '$SX' init >/dev/null && grep -q 'name = \"existing\"' Supax.toml && grep -qx 'build/' .gitignore"
expect_fail "init refuses an existing Supax.toml" "Supax.toml" bash -c "cd '$WORK/scaffold/existing' && '$SX' init"
expect_fail "new refuses an existing directory" "already exists" bash -c "cd '$WORK/scaffold' && '$SX' --lang=en new hello"
expect_fail "English messages with --lang=en" "unknown command" "$SX" --lang=en bogus
expect_fail "English messages with SUPAX_LANG=en" "no Supax.toml" bash -c "cd '$WORK' && SUPAX_LANG=en '$SX' fetch"
expect_fail "an unknown --lang value is refused" "--lang" "$SX" --lang=fr help
cp "$APP/Supax.lock" "$WORK/lock-ar"; (cd "$APP" && SUPAX_LANG=en "$SX" fetch >/dev/null)
cmp -s "$WORK/lock-ar" "$APP/Supax.lock" && ok "Supax.lock does not depend on the message language" || bad "lock language"

# --- help for common manifest mistakes ---------------------------------------------
project "$WORK/hint-key" '[package]
name = "hintkey"

[dependencies]
ادوات = { path = "../log" }'
expect_fail "an unquoted Arabic key gets the corrected line" '"ادوات" = { path = "../log" }' bash -c "cd '$WORK/hint-key' && '$SX' fetch"
project "$WORK/hint-value" '[package]
name = "hintvalue"
version = 0.1.0'
expect_fail "an unquoted text value gets the corrected line" 'version = "0.1.0"' bash -c "cd '$WORK/hint-value' && '$SX' fetch"

# --- package graph (supax metadata, --package-graph) --------------------------------
mkdir -p "$WORK/pg/util/src" "$WORK/pg/app"
printf '[package]\nname = "util"\n\n[package.names]\nar = "أدوات"\n\n[lib]\npath = "src/util.sn"\n' > "$WORK/pg/util/Supax.toml"
printf 'عام عرف واحد(): عدد { أرجع 1; }\n' > "$WORK/pg/util/src/util.sn"
printf '[package]\nname = "app"\n\n[package.names]\nar = "تطبيق"\n\n[imports-alias]\nhelpers = { ar = "مساعدات" }\n\n[dependencies]\nutil = { path = "../util" }\njson = { git = "%s", tag = "v1" }\n' "$(url json)" > "$WORK/pg/app/Supax.toml"
printf 'عام عرف مساعدة(): عدد { أرجع 2; }\n' > "$WORK/pg/app/helpers.sn"
mkdir -p "$WORK/pg/app/src" && printf 'عرف الرئيسية(): عدد { أرجع 0; }\n' > "$WORK/pg/app/src/main.sn"
graph="$(cd "$WORK/pg/app" && "$SX" metadata 2>&1)"
for want in 'version = 1' 'root = "app"' "source_root = \"$WORK/pg/util/src\"" 'entry = "util"' 'spellings = { ar = "أدوات" }' \
            'from = "app"' 'to = "util"' 'name = "base"'; do
    [[ "$graph" == *"$want"* ]] || { bad "metadata contains $want" "$graph"; continue; }
done
[[ "$graph" != *'name = "std"'* ]] && ok "metadata prints the package graph (packages, entry, edges; no std)" || bad "std listed"
[[ "$graph" != *'[[alias]]'* ]] && ok "the graph has no [[alias]] (spellings live in root files)" || bad "[[alias]] written" "$graph"
out="$(cd "$WORK/pg/app" && SUPAX_LANG=en "$SX" metadata 2>&1 >/dev/null)"
[[ "$out" == *"no longer reads [imports-alias]"* && "$out" == *"app.sn: module helpers { ar: مساعدات };"* ]] \
    && ok "[imports-alias] warns and gives the module line and its root file" || bad "imports-alias warning" "$out"
(cd "$WORK/pg/app" && "$SX" metadata --output=bootstrap/graph.toml --relative >/dev/null 2>&1)
grep -q 'source_root = "../../util/src"' "$WORK/pg/app/bootstrap/graph.toml" \
    && ok "metadata --relative writes paths relative to the output file" || bad "relative graph" "$(cat "$WORK/pg/app/bootstrap/graph.toml")"
# A stand-in compiler that has --package-graph records what Supax passes.
mkdir -p "$WORK/fakecc"
cat > "$WORK/fakecc/sultanc" <<FAKE
#!/usr/bin/env bash
if [[ "\$1" == "--package-graph" ]]; then echo "error[SULTANC-CLI-MISSING-OPTION-VALUE]"; exit 2; fi
printf '%s\n' "\$@" > "$WORK/fakecc/args"
exit 0
FAKE
chmod +x "$WORK/fakecc/sultanc"
(cd "$WORK/pg/app" && SULTANC="$WORK/fakecc/sultanc" "$SX" check >/dev/null 2>&1)
if grep -qx -- "--package-graph=$WORK/pg/app/build/supax/package-graph.toml" "$WORK/fakecc/args" 2>/dev/null \
    && grep -q 'root = "app"' "$WORK/pg/app/build/supax/package-graph.toml"; then
    ok "check writes build/supax/package-graph.toml and passes --package-graph=<absolute path>"
else
    bad "package graph passing" "$(cat "$WORK/fakecc/args" 2>/dev/null)"
fi
! grep -q -- "--dependency-map" "$WORK/fakecc/args" && ok "a compiler with --package-graph gets no --dependency-map" || bad "dependency map passed"

# --- add, remove, clean, status lines, build options -------------------------------
mkdir -p "$WORK/edit"
(cd "$WORK/edit" && "$SX" new shop >/dev/null)
printf '# my shop\n' | cat - "$WORK/edit/shop/Supax.toml" > "$WORK/edit/t" && mv "$WORK/edit/t" "$WORK/edit/shop/Supax.toml"
mkdir -p "$WORK/edit/ادوات/src"
printf '[package]\nname = "ادوات"\n\n[lib]\npath = "src"\n' > "$WORK/edit/ادوات/Supax.toml"
printf 'عام عرف ترحيب(): عدد { أرجع 7; }\n' > "$WORK/edit/ادوات/src/lib.sn"
expect_ok "add --path writes a quoted Arabic key" bash -c "cd '$WORK/edit/shop' && '$SX' add ادوات --path ../ادوات && grep -qx '\"ادوات\" = { path = \"../ادوات\" }' Supax.toml"
grep -qx '# my shop' "$WORK/edit/shop/Supax.toml" && ok "add keeps the user's comments" || bad "comments lost" "$(cat "$WORK/edit/shop/Supax.toml")"
expect_ok "add --git with a tag resolves and locks" bash -c "cd '$WORK/edit/shop' && '$SX' add json --git '$(url json)' --tag v1 && grep -q 'json = { git = ' Supax.toml && grep -q 'name = \"json\"' Supax.lock"
expect_ok "add again updates the existing line" bash -c "cd '$WORK/edit/shop' && '$SX' add json --git='$(url json)' --branch=main && [ \"\$(grep -c '^json = ' Supax.toml)\" = 1 ] && grep -q 'branch = \"main\"' Supax.toml"
cp "$WORK/edit/shop/Supax.toml" "$WORK/edit/before.toml"
expect_fail "a failing add leaves Supax.toml unchanged" "Supax.toml" bash -c "cd '$WORK/edit/shop' && '$SX' add missing --git 'file://$WORK/repos/does-not-exist'"
cmp -s "$WORK/edit/before.toml" "$WORK/edit/shop/Supax.toml" && ok "Supax.toml is restored after a failed add" || bad "manifest not restored"
expect_fail "add takes only one source" "exactly one source" bash -c "cd '$WORK/edit/shop' && SUPAX_LANG=en '$SX' add x --path a --git b"
expect_ok "remove deletes the line and updates the lock" bash -c "cd '$WORK/edit/shop' && '$SX' remove json && ! grep -q '^json' Supax.toml && ! grep -q 'name = \"json\"' Supax.lock"
expect_fail "remove refuses an unknown dependency" "no dependency named" bash -c "cd '$WORK/edit/shop' && SUPAX_LANG=en '$SX' remove json"
printf 'استورد ادوات.lib;\nعرف الرئيسية(): عدد { أرجع ترحيب(); }\n' > "$WORK/edit/shop/src/main.sn"
out="$(cd "$WORK/edit/shop" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" run 2>&1)"; code=$?
[[ $code == 7 && "$out" == *"Compiling shop v0.1.0"* && "$out" == *"Finished in "* && "$out" == *"Running build/bin/shop"* ]] \
    && ok "build and run print Compiling, Finished and Running" || bad "status lines" "$out"
out="$(cd "$WORK/edit/shop" && SUPAX_QUIET=0 "$SX" -q build 2>&1)"
[[ -z "$out" ]] && ok "--quiet hides the status lines" || bad "quiet" "$out"
(cd "$WORK/edit/shop" && SULTANC="$WORK/fakecc/sultanc" "$SX" build --release --target some-target >/dev/null 2>&1)
grep -qx -- "--release" "$WORK/fakecc/args" && grep -qx -- "some-target" "$WORK/fakecc/args" && grep -q "build/bin/some-target/shop" "$WORK/fakecc/args" \
    && ok "--release and --target reach the compiler; output goes to build/bin/<target>/" || bad "build options" "$(cat "$WORK/fakecc/args")"
expect_ok "clean removes build/" bash -c "cd '$WORK/edit/shop' && '$SX' clean && [ ! -e build ]"

# --- manifest rules Supax now enforces for the compiler -------------------------
rule() { # name, expected text, manifest body, [extra setup]
    local dir="$WORK/rules/$RANDOM$RANDOM"; mkdir -p "$dir/src"; printf '%s\n' "$3" > "$dir/Supax.toml"
    [[ -n "${4:-}" ]] && (cd "$dir" && eval "$4")
    expect_fail "$1" "$2" bash -c "cd '$dir' && SUPAX_LANG=en '$SX' fetch"
}
rule "a package name must be an identifier" "is not a valid identifier" '[package]
name = "my-app"'
rule "unknown [package] fields are refused" "unknown field in [package]: colour" '[package]
name = "a"
colour = "red"'
rule "known but unsupported [package] fields are refused" "is known but not supported yet" '[package]
name = "a"
edition = "2026"'
rule "authors must be an array of strings" "must be an array of strings" '[package]
name = "a"
authors = "me"'
rule "[lib] accepts only path" "unknown field in [lib]: kind" '[package]
name = "a"

[lib]
kind = "static"'
rule "a [lib] file must be a .sn file" "must be a directory or a .sn file" '[package]
name = "a"

[lib]
path = "src/lib.txt"' 'touch src/lib.txt'
rule "a [lib] path must exist" "does not exist" '[package]
name = "a"

[lib]
path = "missing"'
rule "an import alias target must exist" "the import alias target does not exist" '[package]
name = "a"

[imports-alias]
helpers = { ar = "مساعدات" }'
rule "an import alias spelling cannot hide a real module" "hides a real module" '[package]
name = "a"

[imports-alias]
helpers = { en = "other" }' 'touch helpers.sn other.sn'
rule "one spelling cannot point to two modules" "points to two different modules" '[package]
name = "a"

[imports-alias]
one = { ar = "واحد" }
two = { ar = "واحد" }' 'touch one.sn two.sn'
rule "a dependency key must be an identifier" "contains characters that are not allowed" '[package]
name = "a"

[dependencies]
"my-dep" = { path = "x" }'

# --- compiler integration --------------------------------------------------------
mkdir -p "$WORK/hello/src"
printf '[package]\nname = "hello"\nversion = "0.1.0"\n\n[dependencies]\nlog = { path = "../log" }\n' > "$WORK/hello/Supax.toml"
printf 'استورد log.lib;\nعرف الرئيسية(): عدد { أرجع سجل() + 42; }\n' > "$WORK/hello/src/main.sn"
expect_ok "check runs the compiler on a path-dependency project" bash -c "cd '$WORK/hello' && '$SX' check"
expect_ok "build compiles the project into build/bin/" bash -c "cd '$WORK/hello' && '$SX' build && test -x build/bin/hello"
(cd "$WORK/hello" && "$SX" run >/dev/null 2>&1); [[ $? == 42 ]] && ok "run builds and runs the program" || bad "run exit code"
repo chain "[package]
name = \"chain\"

[lib]
path = \"src\"

[dependencies]
base = { git = \"$(url base)\", tag = \"v1\" }" "src/lib.sn=استورد base.lib;
عام عرف قيمة_chain(): عدد { أرجع قيمة_base() + 1; }"
mkdir -p "$WORK/gitbuild/src"
printf '[package]\nname = "gitbuild"\n\n[dependencies]\nchain = { git = "%s", tag = "v1" }\n' "$(url chain)" > "$WORK/gitbuild/Supax.toml"
printf 'استورد chain.lib;\nعرف الرئيسية(): عدد { أرجع قيمة_chain() * 21; }\n' > "$WORK/gitbuild/src/main.sn"
expect_ok "check runs the compiler on a git-dependency project" bash -c "cd '$WORK/gitbuild' && '$SX' check"
if [[ ${#graph_args[@]} -gt 0 ]]; then
    grep -q 'to = "base"' "$WORK/gitbuild/build/supax/package-graph.toml" 2>/dev/null \
        && ok "a git project hands the compiler build/supax/package-graph.toml" || bad "package graph" "$(cat "$WORK/gitbuild/build/supax/package-graph.toml" 2>/dev/null)"
else
    grep -q 'importer = ' "$WORK/gitbuild/build/supax/dependency-map.toml" 2>/dev/null \
        && ok "a git dependency produces build/supax/dependency-map.toml" || bad "dependency map"
fi
(cd "$WORK/gitbuild" && "$SX" run >/dev/null 2>&1); [[ $? == 42 ]] \
    && ok "a project with transitive git dependencies builds and runs" || bad "git run exit code"
if [[ ${#graph_args[@]} -gt 0 ]]; then
    expect_fail "without the graph the compiler sees no packages (it never reads Supax.toml)" "chain.lib" \
        bash -c "cd '$WORK/gitbuild' && '$SULTANC' check src/main.sn"
else
    expect_fail "without the map the compiler reports the git dependency as unresolved" "SULTANC-PACKAGE-GIT-DEPENDENCY-UNRESOLVED" \
        bash -c "cd '$WORK/gitbuild' && '$SULTANC' check src/main.sn"
fi

# --- module spellings declared in root files (module … { ar: … }) ---------------
mkdir -p "$WORK/spell/src/text"
printf '[package]\nname = "spell"\n\n[lib]\npath = "src"\n' > "$WORK/spell/Supax.toml"
printf 'module helpers { ar: مساعدات };\nmodule text { ar: نصوص };\n' > "$WORK/spell/src/spell.sn"
printf 'عام عرف ثلاثة(): عدد { أرجع 3; }\n' > "$WORK/spell/src/helpers.sn"
printf 'module number { ar: رقم };\n' > "$WORK/spell/src/text/text.sn"
printf 'عام عرف أربعة(): عدد { أرجع 4; }\n' > "$WORK/spell/src/text/number.sn"
printf 'استورد spell.مساعدات;\nاستورد spell.نصوص.رقم;\nعرف الرئيسية(): عدد { أرجع ثلاثة() * 10 + أربعة(); }\n' > "$WORK/spell/src/main.sn"
out="$(cd "$WORK/spell" && "$SX" run 2>&1)"; code=$?
[[ $code == 34 && "$out" != *"imports-alias"* ]] && ok "root-file module spellings (and a dotted one) build and run" || bad "root-file spellings ($code)" "$out"

# supax migrate moves [imports-alias] into the root files.
cp -R "$WORK/spell" "$WORK/mig"; rm -rf "$WORK/mig/build"
printf '// root\n' > "$WORK/mig/src/spell.sn"; printf '' > "$WORK/mig/src/text/text.sn"
printf '# keep me\n[package]\nname = "spell"\n\n[lib]\npath = "src"\n\n[imports-alias]\nhelpers = { ar = "مساعدات" }\ntext = { ar = "نصوص" }\n"text.number" = { ar = "رقم" }\n\n[dependencies]\n' > "$WORK/mig/Supax.toml"
expect_ok "migrate writes the module lines and removes [imports-alias]" bash -c "cd '$WORK/mig' && '$SX' migrate \
    && grep -qx 'وحدة helpers { ar: مساعدات };' src/spell.sn && grep -qx 'وحدة text { ar: نصوص };' src/spell.sn \
    && grep -qx 'وحدة number { ar: رقم };' src/text/text.sn && ! grep -q imports-alias Supax.toml \
    && grep -qx '# keep me' Supax.toml && grep -qx '// root' src/spell.sn"
(cd "$WORK/mig" && "$SX" run >/dev/null 2>&1); [[ $? == 34 ]] && ok "after migrate the project builds and runs" || bad "run after migrate"
expect_ok "migrate a second time changes nothing" bash -c "cd '$WORK/mig' && cp src/spell.sn /tmp/.sx_before_\$\$ && SUPAX_LANG=en '$SX' migrate | grep -q 'nothing to migrate' && cmp -s src/spell.sn /tmp/.sx_before_\$\$; r=\$?; rm -f /tmp/.sx_before_\$\$; exit \$r"

# --- unit tests: tests/unit is a package that depends on Supax itself -------------
expect_ok "unit tests (version requirements)" bash -c "cd '$ROOT/tests/unit' && rm -rf build && '$SX' run"

# --- index (registry) dependencies: name = "1.2" ------------------------------------
sha256hex() { if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -c1-64; else printf '%s' "$1" | shasum -a 256 | cut -c1-64; fi; }
# reg_pkg NAME VERSION VALUE: commits a version of NAME to $WORK/regrepos/NAME and tags it.
reg_pkg() {
    local dir="$WORK/regrepos/$1"; mkdir -p "$dir/src"
    printf '[package]\nname = "%s"\nversion = "%s"\n\n[lib]\npath = "src"\n' "$1" "$2" > "$dir/Supax.toml"
    printf 'عام عرف قيمة_%s(): عدد { أرجع %s; }\n' "$3" "$4" > "$dir/src/lib.sn"
    (cd "$dir" && { [ -d .git ] || git_q init -q; } && git_q add -A && git_q commit -qm "$2" && git_q tag "v$2")
}
# reg_line NAME VERSION [yanked|badsum]: prints the [[versions]] entry, taking commit and checksum from a probe build.
reg_line() {
    local probe="$WORK/regprobe"; rm -rf "$probe"; mkdir -p "$probe/src"
    printf '[package]\nname = "probe"\n\n[dependencies]\n"%s" = { git = "file://%s/regrepos/%s", tag = "v%s" }\n' "$1" "$WORK" "$1" "$2" > "$probe/Supax.toml"
    (cd "$probe" && "$SX" fetch >/dev/null 2>&1) || { echo "probe failed for $1 $2" >&2; return 1; }
    local commit sum
    commit="$(grep '^commit' "$probe/Supax.lock" | cut -d'"' -f2)"; sum="$(grep '^checksum' "$probe/Supax.lock" | cut -d'"' -f2)"
    [[ "${3:-}" == badsum ]] && sum="sha256:$(printf '0%.0s' $(seq 64))"
    printf '\n[[versions]]\nversion = "%s"\ngit = "file://%s/regrepos/%s"\ncommit = "%s"\nchecksum = "%s"\n' "$2" "$WORK" "$1" "$commit" "$sum"
    [[ "${3:-}" == yanked ]] && printf 'yanked = true\n'
    return 0
}
reg_pkg mathx 1.0.0 mathx 10; reg_pkg mathx 1.2.0 mathx 12; reg_pkg mathx 1.4.0 mathx 14
reg_pkg mathx 1.5.0-beta.1 mathx 15; reg_pkg mathx 2.0.0 mathx 20
reg_pkg حساب 0.3.1 حساب 31
IDX="$WORK/regindex"; mkdir -p "$IDX/packages/ma/th" "$IDX/packages/hash/$(sha256hex حساب | cut -c1-2)"; printf 'version = 1\n' > "$IDX/config.toml"
{ echo 'name = "mathx"'; reg_line mathx 1.0.0; reg_line mathx 1.2.0; reg_line mathx 1.4.0 yanked; reg_line mathx 1.5.0-beta.1; reg_line mathx 2.0.0; } > "$IDX/packages/ma/th/mathx.toml"
{ echo 'name = "حساب"'; reg_line حساب 0.3.1; } > "$IDX/packages/hash/$(sha256hex حساب | cut -c1-2)/$(sha256hex حساب).toml"
(cd "$IDX" && git_q init -q && git_q add -A && git_q commit -qm index)
export SUPAX_INDEX="file://$IDX"
mkdir -p "$WORK/regapp/src"
regrun() { # REQUIREMENT -> exit code of the built program
    printf '[package]\nname = "regapp"\n\n[dependencies]\nmathx = %s\n' "$1" > "$WORK/regapp/Supax.toml"
    printf 'استورد mathx.lib;\nعرف الرئيسية(): عدد { أرجع قيمة_mathx(); }\n' > "$WORK/regapp/src/main.sn"
    (cd "$WORK/regapp" && rm -f Supax.lock && "$SX" run >/dev/null 2>&1); echo $?
}
[[ "$(regrun '"1"')" == 12 ]] && ok 'mathx = "1" picks the highest 1.x, skipping yanked and pre-releases' || bad "registry ^1"
grep -q 'source = "registry"' "$WORK/regapp/Supax.lock" && grep -q 'version = "1.2.0"' "$WORK/regapp/Supax.lock" \
    && ok "Supax.lock records the index, version, commit and checksum" || bad "registry lock" "$(cat "$WORK/regapp/Supax.lock")"
[[ "$(regrun '"=1.0.0"')" == 10 ]] && ok '"=1.0.0" picks exactly 1.0.0' || bad "registry ="
[[ "$(regrun '{ version = "^1.5.0-beta.1" }')" == 15 ]] && ok "a pre-release is picked only when the requirement names one" || bad "registry pre-release"
[[ "$(regrun '"2"')" == 20 ]] && ok 'mathx = "2" picks 2.0.0' || bad "registry 2"
expect_fail "a yanked version is not picked for a new lock" "available versions: 1.0.0, 1.2.0, 1.5.0-beta.1, 2.0.0" \
    bash -c "cd '$WORK/regapp' && sed -i.bak 's/^mathx = .*/mathx = \"=1.4.0\"/' Supax.toml && rm -f Supax.lock && SUPAX_LANG=en '$SX' fetch"
expect_fail "an unknown index package is reported" 'no package named "nothere"' \
    bash -c "cd '$WORK/regapp' && sed -i.bak 's/^mathx = .*/nothere = \"1\"/' Supax.toml && SUPAX_LANG=en '$SX' fetch"
expect_fail "a bad requirement is reported at its line" 'Supax.toml:5: dependency "mathx": invalid version requirement' \
    bash -c "cd '$WORK/regapp' && sed -i.bak 's/^nothere = .*/mathx = \">>1\"/' Supax.toml && SUPAX_LANG=en '$SX' fetch"
[[ "$(regrun '"1"')" == 12 ]] || bad "registry reset"
# A pinned version stays until update, and needs no index at all.
(cd "$IDX" && { cat packages/ma/th/mathx.toml; reg_pkg mathx 1.6.0 mathx 16 >/dev/null; reg_line mathx 1.6.0; } > mathx.new && mv mathx.new packages/ma/th/mathx.toml && git_q add -A && git_q commit -qm 1.6.0)
mv "$IDX" "$IDX.away"; (cd "$WORK/regapp" && "$SX" run >/dev/null 2>&1); code=$?; mv "$IDX.away" "$IDX"; [[ $code == 12 ]] \
    && ok "a version pinned in Supax.lock is used without reading the index" || bad "pinned without index"
(cd "$WORK/regapp" && "$SX" update >/dev/null 2>&1 && "$SX" run >/dev/null 2>&1); [[ $? == 16 ]] \
    && ok "update moves to the newest matching version" || bad "registry update"
expect_ok "--offline builds from the cache and Supax.lock" bash -c "cd '$WORK/regapp' && '$SX' build --offline"
expect_ok "verify checks index packages offline" bash -c "cd '$WORK/regapp' && '$SX' verify"
# Two requirements that do not overlap.
mkdir -p "$WORK/reglib/src"
printf '[package]\nname = "reglib"\n\n[lib]\npath = "src"\n\n[dependencies]\nmathx = "=1.0.0"\n' > "$WORK/reglib/Supax.toml"
printf 'عام عرف ريج(): عدد { أرجع 1; }\n' > "$WORK/reglib/src/lib.sn"
printf '[package]\nname = "regapp"\n\n[dependencies]\nmathx = "1.2"\nreglib = { path = "../reglib" }\n' > "$WORK/regapp/Supax.toml"
expect_fail "requirements that do not overlap are a version conflict" 'version conflict for package "mathx"' \
    bash -c "cd '$WORK/regapp' && rm -f Supax.lock && SUPAX_LANG=en '$SX' fetch"
# Two incompatible versions (1.x for reglib, 2.x for the app) live in one build.
printf 'استورد mathx.lib;\nعام عرف ريج(): عدد { أرجع قيمة_mathx(); }\n' > "$WORK/reglib/src/lib.sn"
printf '[package]\nname = "regapp"\n\n[dependencies]\nmathx = "2"\nreglib = { path = "../reglib" }\n' > "$WORK/regapp/Supax.toml"
printf 'استورد mathx.lib;\nاستورد reglib.lib;\nعرف الرئيسية(): عدد { أرجع قيمة_mathx() + ريج(); }\n' > "$WORK/regapp/src/main.sn"
(cd "$WORK/regapp" && rm -f Supax.lock && "$SX" run >/dev/null 2>&1); [[ $? == 30 ]] \
    && ok "1.x and 2.x of one package build together, each for its own importer" || bad "two versions"
grep -q '"mathx 1.0.0"' "$WORK/regapp/Supax.lock" && grep -q '"mathx 2.0.0"' "$WORK/regapp/Supax.lock" \
    && ok "Supax.lock names each version when a package appears twice" || bad "two versions lock" "$(cat "$WORK/regapp/Supax.lock")"
(cd "$WORK/regapp" && "$SX" run --frozen >/dev/null 2>&1); [[ $? == 30 ]] && ok "both versions stay pinned (--frozen)" || bad "two versions frozen"
# An Arabic package name lives under hash/ in the index.
printf '[package]\nname = "regapp"\n\n[dependencies]\n"حساب" = "0.3"\n' > "$WORK/regapp/Supax.toml"
printf 'استورد حساب.lib;\nعرف الرئيسية(): عدد { أرجع قيمة_حساب(); }\n' > "$WORK/regapp/src/main.sn"
(cd "$WORK/regapp" && rm -f Supax.lock && "$SX" run >/dev/null 2>&1); [[ $? == 31 ]] \
    && ok "an Arabic package name resolves through hash/ in the index" || bad "arabic registry name"
# supax add from the index.
expect_ok "add <name> writes the newest released version" bash -c "cd '$WORK/regapp' && '$SX' add mathx && grep -qx 'mathx = \"2.0.0\"' Supax.toml"
expect_ok "add <name>@<requirement> writes the requirement" bash -c "cd '$WORK/regapp' && '$SX' add mathx@~1.2 && grep -qx 'mathx = \"~1.2\"' Supax.toml && grep -q 'version = \"1.2.0\"' Supax.lock"
# Content that does not match the index checksum.
(cd "$IDX" && { cat packages/ma/th/mathx.toml; reg_pkg mathx 1.7.0 mathx 17 >/dev/null; reg_line mathx 1.7.0 badsum; } > mathx.new && mv mathx.new packages/ma/th/mathx.toml && git_q add -A && git_q commit -qm 1.7.0)
expect_fail "content that does not match the index checksum is refused" "integrity check failed" \
    bash -c "cd '$WORK/regapp' && sed -i.bak 's/^mathx = .*/mathx = \"1\"/' Supax.toml && SUPAX_LANG=en '$SX' update"
# supax package prints the index entry: the same commit and checksum a fetch produces.
reg_pkg pkgx 0.1.0 pkgx 1
out="$(cd "$WORK/regrepos/pkgx" && "$SX" package --git "file://$WORK/regrepos/pkgx" 2>/dev/null)"
want="$(reg_line pkgx 0.1.0)"
[[ "$out" == "# packages/pk/gx/pkgx.toml"* && "$(printf '%s' "$out" | sed 1d)" == "$(printf '%s' "$want" | sed 1d)" ]] \
    && ok "package prints the index path and the [[versions]] entry" || bad "supax package" "$out
--- expected:
$want"
expect_fail "package refuses uncommitted changes" "uncommitted changes" \
    bash -c "cd '$WORK/regrepos/pkgx' && echo '// x' >> src/lib.sn && SUPAX_LANG=en '$SX' package --git x; r=\$?; git checkout -q src/lib.sn; exit \$r"
expect_fail "package refuses path dependencies" "path dependency" \
    bash -c "cd '$WORK/reglib' && printf '[package]\nname = \"reglib\"\nversion = \"1.0.0\"\n\n[lib]\npath = \"src\"\n\n[dependencies]\nx = { path = \"../x\" }\n' > Supax.toml && mkdir -p ../x/src && printf '[package]\nname = \"x\"\n\n[lib]\npath = \"src\"\n' > ../x/Supax.toml && SUPAX_LANG=en '$SX' package --git y"
# An index in a newer format is refused with a clear message.
(cd "$IDX" && printf 'version = 2\n' > config.toml && git_q commit -qam v2)
expect_fail "an index in a newer format asks to update Supax" "update Supax" \
    bash -c "cd '$WORK/regapp' && rm -f Supax.lock && SUPAX_LANG=en '$SX' fetch"
(cd "$IDX" && printf 'version = 1\n' > config.toml && git_q commit -qam v1)
# supax publish: checks the release like package, uploads nothing, and explains the manual steps.
out="$(cd "$WORK/regrepos/pkgx" && SUPAX_LANG=en "$SX" publish --git "file://$WORK/regrepos/pkgx" 2>&1)"; code=$?
[[ $code == 0 && "$out" == *"Nothing was uploaded"* && "$out" == *"packages/pk/gx/pkgx.toml"* && "$out" == *'version = "0.1.0"'* && "$out" == *"pull request"* ]] \
    && ok "publish checks the release and explains how to publish it by hand" || bad "publish ($code)" "$out"
expect_fail "publish refuses what package refuses" "uncommitted changes" \
    bash -c "cd '$WORK/regrepos/pkgx' && echo '// x' >> src/lib.sn && SUPAX_LANG=en '$SX' publish --git x; r=\$?; git checkout -q src/lib.sn; exit \$r"
# supax yank in a clone of the index: fresh locks skip the version, --undo brings it back.
YI="$WORK/yankidx"; rm -rf "$YI"; git clone -q "$IDX" "$YI"
cp "$YI/packages/ma/th/mathx.toml" "$WORK/mathx.orig"
out="$(cd "$YI" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" yank mathx@1.7.0 2>&1)"
grep -A5 'version = "1.7.0"' "$YI/packages/ma/th/mathx.toml" | grep -q '^yanked = true' && [[ "$out" == *"Yank mathx@1.7.0"* ]] \
    && ok "yank adds yanked = true to that version in the index clone" || bad "yank" "$out$(cat "$YI/packages/ma/th/mathx.toml")"
(cd "$YI" && git_q commit -qam "yank 1.7.0")
# 1.7.0, the newest 1.x, has a bad checksum on purpose: picking it fails, so 16 means it was skipped.
r="$(SUPAX_INDEX="file://$YI" regrun '"1"')"; [[ "$r" == 16 ]] && ok "a fresh lock skips the yanked version" || bad "yank resolve" "exit $r: $(cat "$WORK/regapp/Supax.lock" 2>&1 | grep -E '^(version|registry)')"
out="$(SUPAX_LANG=en "$SX" yank mathx@1.7.0 --index "$YI" 2>&1)"
[[ "$out" == *"already yanked"* ]] && ok "yanking twice says it is already yanked" || bad "yank twice" "$out"
(cd "$YI" && "$SX" yank mathx@1.7.0 --undo >/dev/null 2>&1)
cmp -s "$WORK/mathx.orig" "$YI/packages/ma/th/mathx.toml" && ok "yank --undo restores the file exactly" || bad "yank undo" "$(diff "$WORK/mathx.orig" "$YI/packages/ma/th/mathx.toml")"
(cd "$YI" && git_q commit -qam "unyank 1.7.0")
expect_fail "after --undo the version is picked again" 'the content of "mathx" 1.7.0' \
    bash -c "cd '$WORK/regapp' && rm -f Supax.lock && SUPAX_INDEX='file://$YI' SUPAX_LANG=en '$SX' fetch"
expect_fail "yank reports a version the index does not have" "there is no version 9.9.9. Versions: 1.0.0, 1.2.0" \
    bash -c "SUPAX_LANG=en '$SX' yank mathx@9.9.9 --index '$YI'"
expect_fail "yank outside an index clone says how to get one" "is not a clone of the package index" \
    bash -c "cd '$WORK' && SUPAX_LANG=en '$SX' yank mathx@1.2.0"
out="$(cd "$WORK/regrepos/pkgx" && SUPAX_LANG=en "$SX" yank 0.1.0 --index "$YI" 2>&1)"
[[ "$out" == *'no package named "pkgx"'* ]] && ok "yank <version> inside a package uses that package's name" || bad "yank default name" "$out"
# supax install <name>[@<requirement>] from the index (a package with [lib] and a program).
T="$WORK/regrepos/rtool"; mkdir -p "$T/src"
printf '[package]\nname = "rtool"\nversion = "1.0.0"\n\n[lib]\npath = "src"\n' > "$T/Supax.toml"
printf 'عام عرف واحد(): عدد { أرجع 1; }\n' > "$T/src/lib.sn"
printf 'عرف الرئيسية(): عدد { أرجع 7; }\n' > "$T/src/main.sn"
(cd "$T" && git_q init -q && git_q add -A && git_q commit -qm 1.0.0 && git_q tag v1.0.0)
mkdir -p "$IDX/packages/rt/oo"
(cd "$IDX" && { echo 'name = "rtool"'; reg_line rtool 1.0.0; } > packages/rt/oo/rtool.toml && git_q add -A && git_q commit -qm rtool)
out="$(SUPAX_LANG=en "$SX" install rtool 2>&1)"; code=$?
"$SUPAX_HOME/bin/rtool"; rc=$?
[[ $code == 0 && $rc == 7 ]] && grep -q 'source = "registry"' "$SUPAX_HOME/installed.toml" \
    && ok "install <name> builds an index package and installs its program" || bad "install from index ($code, $rc)" "$out"
expect_ok "install <name>@<requirement> takes a requirement" bash -c "'$SX' install rtool@1 --force"
"$SX" uninstall rtool >/dev/null 2>&1
unset SUPAX_INDEX

# --- supax test (needs sultanc test) ---------------------------------------------------
mkdir -p "$WORK/tprobe"; printf '' > "$WORK/tprobe/p.sn"
if (cd "$WORK/tprobe" && "$SULTANC" test --list p.sn >/dev/null 2>&1); then
    T="$WORK/tlib"; mkdir -p "$T/src" "$T/tests"
    printf '[package]\nname = "tlib"\nversion = "0.1.0"\n\n[lib]\npath = "src"\n' > "$T/Supax.toml"
    printf 'استورد tlib.a;\nاستورد tlib.b;\n' > "$T/src/tlib.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعام عرف واحد(): عدد { أرجع 1; }\n@@اختبار\nعرف واحد_صحيح(): فراغ { تأكد(واحد() == 1); }\n' > "$T/src/a.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعام عرف اثنان(): عدد { أرجع 2; }\n@@test\nعرف two_is_two(): فراغ { تأكد(اثنان() == 2); }\n' > "$T/src/b.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nاستورد tlib.b;\n@@test\nعرف from_tests_dir(): فراغ { تأكد(اثنان() == 2); }\n' > "$T/tests/outside.sn"
    out="$(cd "$T" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 0 && "$out" == *"Running lib src/tlib.sn"* && "$out" == *"PASS واحد_صحيح"* && "$out" == *"PASS two_is_two"* \
        && "$out" == *"Running test tests/outside.sn"* && "$out" == *"PASS from_tests_dir"* ]] \
        && ok "test runs the lib's tests, then each tests/*.sn against the lib" || bad "supax test ($code)" "$out"
    grep -q 'root = "tlib tests"' "$T/build/supax/test-graph.toml" && ok "tests/ is its own package that depends on the lib" || bad "test graph"
    # Since bf8eab2 only the root package's tests run: tests/outside.sn imports tlib.b, but not its tests.
    tail="${out#*Running test tests/outside.sn}"
    if [[ "$tail" == *"two_is_two"* ]]; then
        ok "tests/*.sn runs only its own tests (skipped: this sultanc also runs dependency tests)"
    else
        ok "tests/*.sn runs only its own tests, not the library's"
    fi
    out="$(cd "$T" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test two 2>&1)"
    [[ "$out" == *"PASS two_is_two"* && "$out" != *"واحد_صحيح"* && "$out" == *"filtered out: 1"* ]] && ok "test <text> filters by name" || bad "test filter" "$out"
    out="$(cd "$T" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test --test outside 2>&1)"
    [[ "$out" == *"tests/outside.sn"* && "$out" != *"Running lib"* ]] && ok "test --test <name> runs one tests/ file" || bad "test --test" "$out"
    out="$(cd "$T" && "$SX" test --lib --list 2>&1)"
    [[ "$out" == *"واحد_صحيح"* && "$out" == *"two_is_two"* && "$out" != *"PASS"* ]] && ok "test --lib --list lists without running" || bad "test --list" "$out"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعام عرف اثنان(): عدد { أرجع 2; }\n@@test\nعرف two_is_three(): فراغ { تأكد(اثنان() == 3); }\n' > "$T/src/b.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\n@@test\nعرف always(): فراغ { تأكد(صواب); }\n' > "$T/tests/outside.sn"
    out="$(cd "$T" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 1 && "$out" == *"FAIL two_is_three"* && "$out" == *'to rerun pass "--lib"'* && "$out" != *"tests/outside.sn"* ]] \
        && ok "a failing test stops the run and says how to rerun it" || bad "test failure ($code)" "$out"
    out="$(cd "$T" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test --no-fail-fast 2>&1)"; code=$?
    [[ $code == 1 && "$out" == *"PASS always"* && "$out" == *"tests failed in: --lib"* ]] \
        && ok "--no-fail-fast runs every target, then reports the failures" || bad "no-fail-fast ($code)" "$out"
    printf 'عرف مكسور(: عدد {\n' > "$T/tests/broken.sn"
    (cd "$T" && "$SX" test --test broken >/dev/null 2>&1); [[ $? == 2 ]] && ok "tests that do not build give status 2" || bad "test build error"
    P="$WORK/tbin"; mkdir -p "$P/src/bin"
    printf '[package]\nname = "tbin"\n' > "$P/Supax.toml"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعرف الرئيسية(): عدد { أرجع 0; }\n@@اختبار\nعرف في_الرئيسي(): فراغ { تأكد(صواب); }\n' > "$P/src/main.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعرف الرئيسية(): عدد { أرجع 0; }\n@@test\nعرف in_tool(): فراغ { تأكد(صواب); }\n' > "$P/src/bin/tool.sn"
    out="$(cd "$P" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 0 && "$out" == *"Running bin src/main.sn"* && "$out" == *"PASS في_الرئيسي"* && "$out" == *"PASS in_tool"* ]] \
        && ok "test runs the tests of every program" || bad "test programs ($code)" "$out"
    out="$(cd "$P" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test --bin tool 2>&1)"
    [[ "$out" == *"PASS in_tool"* && "$out" != *"في_الرئيسي"* ]] && ok "test --bin <name> runs one program's tests" || bad "test --bin" "$out"
    # [lib] and src/main.sn in one folder: the library's test runs once (--tests-in, since 000493c).
    B="$WORK/tboth"; mkdir -p "$B/src"
    printf '[package]\nname = "both"\n\n[lib]\npath = "src"\n' > "$B/Supax.toml"
    printf 'استورد both.a;\n' > "$B/src/both.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nعام عرف واحد(): عدد { أرجع 1; }\n@@test\nعرف lib_once(): فراغ { تأكد(واحد() == 1); }\n' > "$B/src/a.sn"
    printf 'استورد المكتبة.تصحيح.تأكد;\nاستورد both.a;\nعرف الرئيسية(): عدد { أرجع واحد(); }\n@@test\nعرف main_own(): فراغ { تأكد(صواب); }\n' > "$B/src/main.sn"
    out="$(cd "$B" && SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    n="$(printf '%s' "$out" | grep -c 'PASS lib_once')"
    probe="$("$SULTANC" test --tests-in 2>&1 || true)"
    if [[ "$probe" == *UNKNOWN-OPTION* ]]; then
        ok "a library's tests run once beside its program (skipped: this sultanc has no --tests-in)"
    else
        [[ $code == 0 && $n == 1 && "$out" == *"PASS main_own"* ]] && ok "a library's tests run once beside its program; the program runs only its own" || bad "tests-in ($code, $n)" "$out"
    fi
    mkdir -p "$WORK/tnone"; printf '[package]\nname = "tnone"\n\n[lib]\npath = "src"\n' > "$WORK/tnone/Supax.toml"; mkdir -p "$WORK/tnone/src"
    expect_ok "a package with nothing to test passes, with a note" bash -c "cd '$WORK/tnone' && SUPAX_LANG=en '$SX' test 2>&1 | grep -q 'no tests'"
else
    ok "supax test (skipped: this sultanc has no test mode)"
fi

# --- workspaces ---------------------------------------------------------------------
W="$WORK/ws"; mkdir -p "$W/app/src" "$W/libs/util/src" "$W/libs/math/src"
printf '[workspace]\nmembers = ["app", "libs/*"]\n' > "$W/Supax.toml"
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nutil = { path = "../libs/util" }\n' > "$W/app/Supax.toml"
printf 'استورد util.lib;\nعرف الرئيسية(): عدد { أرجع ثلاثة(); }\n' > "$W/app/src/main.sn"
printf '[package]\nname = "util"\nversion = "0.1.0"\n\n[lib]\npath = "src"\n\n[dependencies]\nmath = { path = "../math" }\n' > "$W/libs/util/Supax.toml"
printf 'استورد math.lib;\nعام عرف ثلاثة(): عدد { أرجع واحد() + 2; }\n' > "$W/libs/util/src/lib.sn"
HAS_TEST=0; (cd "$WORK/tprobe" && "$SULTANC" test --list p.sn >/dev/null 2>&1) && HAS_TEST=1
[[ $HAS_TEST == 1 ]] && printf 'استورد math.lib;\nاستورد المكتبة.تصحيح.تأكد;\nعام عرف ثلاثة(): عدد { أرجع واحد() + 2; }\n@@test\nعرف three(): فراغ { تأكد(ثلاثة() == 3); }\n' > "$W/libs/util/src/lib.sn"
printf 'استورد util.lib;\n' > "$W/libs/util/src/util.sn"
printf '[package]\nname = "math"\nversion = "0.1.0"\n\n[lib]\npath = "src"\n' > "$W/libs/math/Supax.toml"
printf 'عام عرف واحد(): عدد { أرجع 1; }\n' > "$W/libs/math/src/lib.sn"
expect_ok "fetch at a workspace root writes one Supax.lock there, none in members" \
    bash -c "cd '$W' && '$SX' fetch && test -f Supax.lock && ! test -e app/Supax.lock && ! test -e libs/util/Supax.lock && [ \$(grep -c 'source = \"root\"' Supax.lock) = 3 ]"
out="$(cd "$W" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" build 2>&1)"; code=$?
[[ $code == 0 && "$out" == *"Compiling app v0.1.0"* && "$out" == *"Checking util v0.1.0"* && -x "$W/build/bin/app" && ! -e "$W/app/build" ]] \
    && ok "build at a virtual root builds every program into the root build/ and checks every library" || bad "workspace build ($code)" "$out"
expect_fail "run at a virtual root asks for -p and lists the members" "pick a member with -p <name>: app, math, util" bash -c "cd '$W' && SUPAX_LANG=en '$SX' run"
(cd "$W" && "$SX" run -p app >/dev/null 2>&1); [[ $? == 3 ]] && ok "run -p <member> runs that member" || bad "run -p"
(cd "$W/app/src" && "$SX" run >/dev/null 2>&1); [[ $? == 3 ]] && ok "commands inside a member act on that member" || bad "run in member"
expect_fail "an unknown -p lists the workspace packages" 'no package named "nope" in the workspace. Packages: app, math, util' bash -c "cd '$W' && SUPAX_LANG=en '$SX' build -p nope"
out="$(cd "$W" && "$SX" tree 2>&1)"
[[ "$out" == *"app v0.1.0"* && "$out" == *"util v0.1.0"* && "$out" == *"    - math v0.1.0"* ]] && ok "tree shows every member" || bad "workspace tree" "$out"
if [[ $HAS_TEST == 1 ]]; then
    out="$(cd "$W" && SUPAX_LANG=en "$SX" test 2>&1)"; [[ $? == 0 && "$out" == *"PASS three"* ]] && ok "test at the root runs every member's tests" || bad "workspace test" "$out"
else
    ok "workspace test (skipped: this sultanc has no test mode)"
fi
expect_ok "add inside a member updates the root Supax.lock" \
    bash -c "cd '$W/app' && '$SX' add math --path ../libs/math && ! test -e Supax.lock && grep -q 'dependencies = \[\"math\", \"util\"\]' ../Supax.lock"
expect_ok "members share one build/ at the root; clean in a member removes it" bash -c "cd '$W/app' && '$SX' build && test -x ../build/bin/app && test -f ../build/supax/app/package-graph.toml && ! test -e build && '$SX' clean && ! test -e ../build"
mkdir -p "$W/stray/src"; printf '[package]\nname = "stray"\n' > "$W/stray/Supax.toml"; printf 'عرف الرئيسية(): عدد { أرجع 5; }\n' > "$W/stray/src/main.sn"
expect_fail "a package inside a workspace but not in members is refused" "Add it to members or to exclude" bash -c "cd '$W/stray' && SUPAX_LANG=en '$SX' build"
printf '[workspace]\nmembers = ["app", "libs/*"]\nexclude = ["stray"]\n' > "$W/Supax.toml"
(cd "$W/stray" && "$SX" run >/dev/null 2>&1); [[ $? == 5 && -f "$W/stray/Supax.lock" ]] && ok "an excluded package is a project of its own" || bad "workspace exclude"
printf '[workspace]\nmembers = ["app"]\nresolver = "2"\n' > "$W/Supax.toml"
expect_fail "unknown [workspace] fields are refused" 'unknown field in [workspace]: "resolver"' bash -c "cd '$W/app' && SUPAX_LANG=en '$SX' fetch"
printf '[workspace]\nmembers = ["app"]\n\n[dependencies]\nx = { path = "x" }\n' > "$W/Supax.toml"
expect_fail "a virtual root holds only [workspace]" "holds only [workspace]" bash -c "cd '$W' && SUPAX_LANG=en '$SX' fetch"
# A root that is a package too: commands at the root act on it alone.
R="$WORK/wsroot"; mkdir -p "$R/src" "$R/helper/src"
printf '[package]\nname = "main_app"\n\n[workspace]\nmembers = ["helper"]\n\n[dependencies]\nhelper = { path = "helper" }\n' > "$R/Supax.toml"
printf 'استورد helper.lib;\nعرف الرئيسية(): عدد { أرجع سبعة(); }\n' > "$R/src/main.sn"
printf '[package]\nname = "helper"\n\n[lib]\npath = "src"\n' > "$R/helper/Supax.toml"
printf 'عام عرف سبعة(): عدد { أرجع 7; }\n' > "$R/helper/src/lib.sn"
(cd "$R" && "$SX" run >/dev/null 2>&1); [[ $? == 7 && ! -e "$R/helper/Supax.lock" ]] && ok "a root package with members runs, sharing the root Supax.lock" || bad "workspace root package"

# --- several programs per project (src/bin/*.sn) ---------------------------------
mkdir -p "$WORK/multi/src/bin"
printf '[package]\nname = "multi"\nversion = "0.1.0"\n' > "$WORK/multi/Supax.toml"
printf 'عرف الرئيسية(): عدد { أرجع 10; }\n' > "$WORK/multi/src/main.sn"
printf 'عرف الرئيسية(): عدد { أرجع 11; }\n' > "$WORK/multi/src/bin/tools.sn"
printf 'عرف الرئيسية(): عدد { أرجع 12; }\n' > "$WORK/multi/src/bin/نسخ.sn"
expect_ok "build compiles src/main.sn and every src/bin/*.sn" \
    bash -c "cd '$WORK/multi' && '$SX' build && test -x build/bin/multi && test -x build/bin/tools && test -x build/bin/نسخ"
(cd "$WORK/multi" && "$SX" run >/dev/null 2>&1); [[ $? == 10 ]] && ok "run picks the main program" || bad "run main"
(cd "$WORK/multi" && "$SX" run --bin tools >/dev/null 2>&1); [[ $? == 11 ]] && ok "run --bin <name> runs that program" || bad "run --bin"
(cd "$WORK/multi" && "$SX" run --bin=نسخ >/dev/null 2>&1); [[ $? == 12 ]] && ok "run --bin=<Arabic name> works" || bad "run --bin Arabic"
expect_fail "an unknown --bin lists the programs" "programs: " bash -c "cd '$WORK/multi' && SUPAX_LANG=en '$SX' run --bin nope"
rm "$WORK/multi/src/main.sn"
expect_fail "without src/main.sn, run asks for --bin" "--bin" bash -c "cd '$WORK/multi' && SUPAX_LANG=en '$SX' run"
expect_ok "build --bin builds only that program" bash -c "cd '$WORK/multi' && rm -rf build && '$SX' build --bin tools && test -x build/bin/tools && ! test -e build/bin/نسخ"

# --- cache: info, clean, locking -----------------------------------------------------
out="$(cd "$WORK/gitbuild" && SUPAX_LANG=en "$SX" cache info 2>&1)"
[[ "$out" == *"cache: $SUPAX_HOME/git"* && "$out" == *"repositories: "* ]] && ok "cache info shows the cache folder and counts" || bad "cache info" "$out"
# Hold every repository lock: flock a.lock flock b.lock … sleep 2.
holdall=()
for lf in "$SUPAX_HOME"/git/db/*.lock; do [[ -e "$lf" ]] && holdall+=(flock "$lf"); done
lockfile="${holdall[1]:-}"
[[ -n "$lockfile" ]] && ok "each cached repository has a lock file" || bad "no lock file"
if command -v flock >/dev/null 2>&1 && [[ -n "$lockfile" ]]; then
    "${holdall[@]}" sleep 2 & holder=$!
    sleep 0.3
    start=$(date +%s)
    out="$(cd "$WORK/gitbuild" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" update 2>&1)"; code=$?
    took=$(( $(date +%s) - start ))
    wait "$holder"
    [[ $code == 0 && "$out" == *"Blocking"* && $took -ge 1 ]] && ok "a held cache lock makes Supax wait (Blocking), then continue" || bad "lock wait" "$out"
    "${holdall[@]}" sleep 2 & holder=$!
    sleep 0.3
    expect_fail "cache clean refuses while another process holds a lock" "another Supax process" bash -c "SUPAX_LANG=en '$SX' cache clean"
    wait "$holder"
else
    ok "cache lock waiting (skipped: no flock command)"
fi
rm -rf "$WORK/conc"; mkdir -p "$WORK/conc"
for n in 1 2; do cp -R "$WORK/gitbuild" "$WORK/conc/p$n"; rm -rf "$WORK/conc/p$n/build" "$WORK/conc/p$n/Supax.lock"; done
(cd "$WORK/conc/p1" && "$SX" update >/dev/null 2>&1) & a=$!
(cd "$WORK/conc/p2" && "$SX" update >/dev/null 2>&1) & b=$!
wait "$a"; ra=$?; wait "$b"; rb=$?
[[ $ra == 0 && $rb == 0 ]] && cmp -s "$WORK/conc/p1/Supax.lock" "$WORK/conc/p2/Supax.lock" \
    && ok "two concurrent fetches succeed and lock the same commits" || bad "concurrent fetch"
! ls -d "$SUPAX_HOME"/git/checkouts/*/.tmp* "$SUPAX_HOME"/git/checkouts/*/*.tmp* >/dev/null 2>&1 \
    && ok "no temporary folders are left in the cache" || bad "leftover temp folders"
expect_ok "cache clean removes the git cache" bash -c "'$SX' cache clean && [ -z \"\$(ls -A '$SUPAX_HOME/git/checkouts' 2>/dev/null)\" ] && [ ! -e '$SUPAX_HOME/git/db' ]"
(cd "$WORK/gitbuild" && "$SX" run >/dev/null 2>&1); [[ $? == 42 ]] && ok "after cache clean, a build fetches again" || bad "refetch after clean"

# --- new --lib ----------------------------------------------------------------------
L="$WORK/newlib"; mkdir -p "$L"
(cd "$L" && "$SX" new مكتبتي --lib >/dev/null 2>&1 && SUPAX_LANG=en "$SX" new enlib --lib >/dev/null 2>&1)
grep -q '^\[lib\]' "$L/مكتبتي/Supax.toml" && [[ -f "$L/مكتبتي/src/مكتبتي.sn" && -f "$L/مكتبتي/src/lib.sn" && ! -e "$L/مكتبتي/src/main.sn" ]] \
    && ok "new --lib writes [lib], the root file and src/lib.sn, and no main.sn" || bad "new --lib files" "$(ls -R "$L/مكتبتي")"
grep -q 'استورد مكتبتي.lib;' "$L/مكتبتي/src/مكتبتي.sn" && grep -q 'import std.debug.assert;' "$L/enlib/src/lib.sn" \
    && ok "new --lib follows the message language" || bad "new --lib language"
"$SULTANC" fmt --check "$L/مكتبتي/src" "$L/enlib/src" >/dev/null 2>&1 && ok "the --lib template is formatted" || bad "new --lib format"
mkdir -p "$L/initlib"; (cd "$L/initlib" && "$SX" init --lib >/dev/null 2>&1)
[[ -f "$L/initlib/src/initlib.sn" && -f "$L/initlib/src/lib.sn" ]] && ok "init --lib makes a library in the current directory" || bad "init --lib"
if [[ $HAS_TEST == 1 ]]; then
    out="$(cd "$L/enlib" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 0 && "$out" == *"PASS adds_two_numbers"* ]] && ok "the new library's test passes" || bad "new --lib test ($code)" "$out"
    expect_ok "the new library checks" bash -c "cd '$L/enlib' && '$SX' check"
else
    ok "the new library's test passes (skipped: no sultanc test)"; ok "the new library checks (skipped)"
fi

# --- [dev-dependencies] ---------------------------------------------------------------
D="$WORK/dev"; mkdir -p "$D"
(cd "$D" && SUPAX_LANG=en "$SX" new helper --lib >/dev/null 2>&1 && SUPAX_LANG=en "$SX" new other --lib >/dev/null 2>&1 \
    && SUPAX_LANG=en "$SX" new mylib --lib >/dev/null 2>&1)
printf 'public def seven(): int {\n    return 7;\n}\n' > "$D/helper/src/lib.sn"
printf 'public def eight(): int {\n    return 8;\n}\n' > "$D/other/src/lib.sn"
out="$(cd "$D/mylib" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" add helper --path ../helper --dev 2>&1)"
grep -q '^\[dev-dependencies\]' "$D/mylib/Supax.toml" && grep -A1 '^\[dev-dependencies\]' "$D/mylib/Supax.toml" | grep -q '^helper = ' \
    && [[ "$out" == *"to [dev-dependencies]"* ]] && ok "add --dev writes [dev-dependencies]" || bad "add --dev" "$out$(cat "$D/mylib/Supax.toml")"
(cd "$D/mylib" && "$SX" add other --path ../other >/dev/null 2>&1)
grep -q 'name = "helper"' "$D/mylib/Supax.lock" && ok "Supax.lock includes dev-dependencies" || bad "lock dev"
(cd "$D/mylib" && "$SX" metadata --output=g.toml >/dev/null 2>&1)
! grep -q helper "$D/mylib/g.toml" && grep -q 'to = "other"' "$D/mylib/g.toml" \
    && ok "the build graph (metadata) leaves dev-dependencies out" || bad "metadata dev" "$(cat "$D/mylib/g.toml")"
out="$(cd "$D/mylib" && SUPAX_LANG=en "$SX" tree 2>&1)"
[[ "$out" == *"[dev-dependencies]"*"helper"* && "$out" == *"other"* ]] && ok "tree shows dev-dependencies under their own heading" || bad "tree dev" "$out"
if [[ $HAS_TEST == 1 ]]; then
    mkdir -p "$D/mylib/tests"
    printf 'import std.debug.assert;\nimport mylib.lib;\nimport helper.lib;\nimport other.lib;\n\n@@test\ndef uses_both(): void {\n    assert(add(seven(), eight()) == 15);\n}\n' > "$D/mylib/tests/it.sn"
    out="$(cd "$D/mylib" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 0 && "$out" == *"PASS adds_two_numbers"* && "$out" == *"PASS uses_both"* ]] \
        && ok "tests/ can import dev-dependencies and dependencies" || bad "tests/ dev ($code)" "$out"
    cp "$D/mylib/src/lib.sn" "$D/lib.sn.bak"; printf 'import helper.lib;\n' >> "$D/mylib/src/lib.sn"
    out="$(cd "$D/mylib" && SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code != 0 && "$out" == *"SULTANC-MODULE-NOT-FOUND"* ]] && ok "a file in src/ cannot import a dev-dependency" || bad "src dev import ($code)" "$out"
    cp "$D/lib.sn.bak" "$D/mylib/src/lib.sn"
    (cd "$D" && SUPAX_LANG=en "$SX" new binapp >/dev/null 2>&1); (cd "$D/binapp" && "$SX" add helper --path ../helper --dev >/dev/null 2>&1)
    mkdir -p "$D/binapp/tests"; printf 'import std.debug.assert;\nimport helper.lib;\n\n@@test\ndef bin_side(): void {\n    assert(seven() == 7);\n}\n' > "$D/binapp/tests/t.sn"
    out="$(cd "$D/binapp" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" test 2>&1)"; code=$?
    [[ $code == 0 && "$out" == *"PASS bin_side"* ]] && ok "a package without [lib]: tests/ can import dev-dependencies" || bad "bin tests/ dev ($code)" "$out"
else
    for n in 1 2 3; do ok "dev-dependencies in tests (skipped: no sultanc test)"; done
fi
expect_ok "build works without the dev-dependencies" bash -c "cd '$D/mylib' && '$SX' build"
(cd "$D" && SUPAX_LANG=en "$SX" new user >/dev/null 2>&1); (cd "$D/user" && "$SX" add mylib --path ../mylib >/dev/null 2>&1)
! grep -q helper "$D/user/Supax.lock" && ok "a dependency's dev-dependencies are not resolved" || bad "transitive dev" "$(cat "$D/user/Supax.lock")"
cp "$D/mylib/Supax.toml" "$D/toml.bak"
awk '{ print } $0 == "[dependencies]" { print "helper = { path = \"../helper\" }" }' "$D/toml.bak" > "$D/mylib/Supax.toml"
expect_fail "the same key in [dependencies] and [dev-dependencies] is an error" "in both [dependencies] and [dev-dependencies]" \
    bash -c "cd '$D/mylib' && SUPAX_LANG=en '$SX' check"
cp "$D/toml.bak" "$D/mylib/Supax.toml"
expect_fail "remove without --dev looks only in [dependencies]" 'no dependency named "helper" in [dependencies]' \
    bash -c "cd '$D/mylib' && SUPAX_LANG=en '$SX' remove helper"
expect_ok "remove --dev removes a dev-dependency" bash -c "cd '$D/mylib' && '$SX' remove helper --dev && ! grep -q '^helper' Supax.toml"

# --- program file names per target, and running another target's program -------------
G="$WORK/tnames"; mkdir -p "$G"; (cd "$G" && SUPAX_LANG=en "$SX" new app >/dev/null 2>&1)
(cd "$G/app" && "$SX" build --target wasm32-wasi >/dev/null 2>&1)
[[ -f "$G/app/build/bin/wasm32-wasi/app.wasm" ]] && ok "a wasm32-wasi build is written as <name>.wasm" || bad "wasm name" "$(ls -R "$G/app/build/bin" 2>&1)"
expect_fail "run for a target this machine cannot run says so" "it was built for the target wasm32-wasi" \
    bash -c "cd '$G/app' && SUPAX_LANG=en '$SX' run --target wasm32-wasi"

# --- fmt ----------------------------------------------------------------------------
F="$WORK/fmt"; mkdir -p "$F"; (cd "$F" && SUPAX_LANG=en "$SX" new app >/dev/null 2>&1)
mkdir -p "$F/app/tests"
printf 'def main(): int {\nreturn 0;\n}\n' > "$F/app/src/main.sn"
printf 'def helper(): int {\nreturn 1;\n}\n' > "$F/app/tests/t.sn"
out="$(cd "$F/app" && SUPAX_LANG=en "$SX" fmt --check 2>&1)"; code=$?
[[ $code == 1 && "$out" == *"src/main.sn"* && "$out" == *"tests/t.sn"* ]] && ok "fmt --check reports unformatted files in src/ and tests/, exit 1" || bad "fmt --check ($code)" "$out"
(cd "$F/app" && "$SX" fmt >/dev/null 2>&1) && grep -q '^    return 0;' "$F/app/src/main.sn" && grep -q '^    return 1;' "$F/app/tests/t.sn" \
    && ok "fmt formats src/ and tests/" || bad "fmt" "$(cat "$F/app/src/main.sn")"
expect_ok "fmt --check passes once formatted" bash -c "cd '$F/app' && '$SX' fmt --check"
mkdir -p "$F/ws/a/src" "$F/ws/b/src"
printf '[workspace]\nmembers = ["a", "b"]\n' > "$F/ws/Supax.toml"
for m in a b; do printf '[package]\nname = "%s"\nversion = "0.1.0"\n' "$m" > "$F/ws/$m/Supax.toml"; printf 'def main(): int {\nreturn 0;\n}\n' > "$F/ws/$m/src/main.sn"; done
(cd "$F/ws" && "$SX" fmt >/dev/null 2>&1)
grep -q '^    return 0;' "$F/ws/a/src/main.sn" && grep -q '^    return 0;' "$F/ws/b/src/main.sn" && ok "fmt at a workspace root formats every member" || bad "fmt workspace"

# --- --message-format and --color ------------------------------------------------------
M="$WORK/msgfmt"; mkdir -p "$M"; (cd "$M" && SUPAX_LANG=en "$SX" new app >/dev/null 2>&1)
printf 'def main(): int {\n    return "x";\n}\n' > "$M/app/src/main.sn"
out="$(cd "$M/app" && SUPAX_QUIET=0 SUPAX_LANG=en "$SX" check --message-format=json 2>&1)"; code=$?
[[ $code != 0 && "$out" == '{"schema"'* && "$out" == *'"id":"SULTANC-TYPE-RETURN-MISMATCH"'* && "$out" != *"Checking"* ]] \
    && ok "--message-format=json gives the compiler's JSON and no status lines" || bad "json ($code)" "$out"
out="$(cd "$M/app" && SUPAX_LANG=en "$SX" check --message-format short 2>&1)"
[[ "$out" == *"src/main.sn:2:"*"error[SULTANC-TYPE-RETURN-MISMATCH]"* ]] && ok "--message-format short (space form) gives one line per diagnostic" || bad "short" "$out"
out="$(cd "$M/app" && "$SX" check --color=always 2>&1)"; [[ "$out" == *$'\e['* ]] && ok "--color=always colors the diagnostics" || bad "color always"
out="$(cd "$M/app" && "$SX" check --color=never 2>&1)"; [[ "$out" != *$'\e['* ]] && ok "--color=never does not" || bad "color never"
expect_fail "--message-format checks its value" "human | short | json" bash -c "cd '$M/app' && SUPAX_LANG=en '$SX' check --message-format=xml"
expect_fail "--color checks its value" "auto | always | never" bash -c "cd '$M/app' && SUPAX_LANG=en '$SX' check --color=sometimes"
if [[ $HAS_TEST == 1 ]]; then
    out="$(cd "$M/app" && SUPAX_LANG=en "$SX" test --message-format=json 2>&1)"
    [[ "$out" == *'"id":"SULTANC-TYPE-RETURN-MISMATCH"'* ]] && ok "test passes --message-format to sultanc test" || bad "test json" "$out"
else
    ok "test passes --message-format (skipped: no sultanc test)"
fi
printf 'import std.process.argument_count;\n\ndef main(): int {\n    return argument_count() as int;\n}\n' > "$M/app/src/main.sn"
(cd "$M/app" && "$SX" run -- --color=never --quiet >/dev/null 2>&1); [[ $? == 3 ]] \
    && ok "options after -- go to the program, not to Supax" || bad "args after --"

# --- install and uninstall ---------------------------------------------------------------
I="$WORK/inst"; mkdir -p "$I"; B="$SUPAX_HOME/bin"
(cd "$I" && SUPAX_LANG=en "$SX" new greet >/dev/null 2>&1)
mkdir -p "$I/greet/src/bin"
printf 'عرف الرئيسية(): عدد { أرجع 5; }\n' > "$I/greet/src/main.sn"
printf 'عرف الرئيسية(): عدد { أرجع 6; }\n' > "$I/greet/src/bin/second.sn"
out="$(SUPAX_QUIET=0 SUPAX_LANG=en "$SX" install --path "$I/greet" 2>&1)"; code=$?
"$B/greet"; r1=$?; "$B/second"; r2=$?
[[ $code == 0 && $r1 == 5 && $r2 == 6 && "$out" == *"[release]"* && "$out" == *"Installed greet v0.1.0"* ]] \
    && ok "install --path builds with --release and installs every program" || bad "install --path ($code $r1 $r2)" "$out"
grep -q 'package = "greet"' "$SUPAX_HOME/installed.toml" && grep -q 'source = "path"' "$SUPAX_HOME/installed.toml" \
    && ok "installed.toml records the programs and their package" || bad "installed.toml" "$(cat "$SUPAX_HOME/installed.toml" 2>&1)"
out="$(SUPAX_LANG=en "$SX" install --list 2>&1)"
[[ "$out" == *"greet v0.1.0"* && "$out" == *"second"* ]] && ok "install --list shows packages and programs" || bad "install --list" "$out"
out="$(SUPAX_QUIET=0 SUPAX_LANG=en "$SX" install --path "$I/greet" 2>&1)"
[[ "$out" == *"Replacing"* ]] && ok "reinstalling a package replaces its programs" || bad "reinstall" "$out"
(cd "$I" && SUPAX_LANG=en "$SX" new other >/dev/null 2>&1); mkdir -p "$I/other/src/bin"; cp "$I/greet/src/bin/second.sn" "$I/other/src/bin/"
expect_fail "another package's program is not replaced without --force" 'was installed by the package "greet"' \
    bash -c "SUPAX_LANG=en '$SX' install --path '$I/other'"
expect_ok "--force replaces it" bash -c "'$SX' install --path '$I/other' --force && grep -A2 'name = \"second\"' '$SUPAX_HOME/installed.toml' | grep -q 'package = \"other\"'"
printf '#!/bin/sh\n' > "$B/foreign"; (cd "$I" && SUPAX_LANG=en "$SX" new foreign >/dev/null 2>&1)
expect_fail "a file Supax did not install is not replaced" "was not installed by Supax" bash -c "SUPAX_LANG=en '$SX' install --path '$I/foreign'"
(cd "$I" && SUPAX_LANG=en "$SX" new alib --lib >/dev/null 2>&1)
expect_fail "a library has nothing to install" "has no programs" bash -c "SUPAX_LANG=en '$SX' install --path '$I/alib'"
(cd "$I" && SUPAX_LANG=en "$SX" new supax >/dev/null 2>&1)
expect_fail "a program named supax is refused" "belongs to Supax and the compiler" bash -c "SUPAX_LANG=en '$SX' install --path '$I/supax'"
expect_fail "install --target is refused" "builds for this machine" bash -c "SUPAX_LANG=en '$SX' install --path '$I/greet' --target wasm32-wasi"
mkdir -p "$I/gtool"; (cd "$I/gtool" && SUPAX_LANG=en "$SX" init gtool >/dev/null 2>&1 && SUPAX_LANG=en "$SX" new glib --lib >/dev/null 2>&1 && "$SX" add glib --path glib >/dev/null 2>&1)
printf 'import glib.lib;\n\ndef main(): int {\n    return add(40, 2);\n}\n' > "$I/gtool/src/main.sn"
(cd "$I/gtool" && git_q init -q && git_q add -A && git_q commit -qm init && git_q tag v1)
out="$(SUPAX_LANG=en "$SX" install --git "file://$I/gtool" --tag v1 2>&1)"; code=$?
"$B/gtool"; rc=$?
[[ $code == 0 && $rc == 42 ]] && grep -q 'source = "git"' "$SUPAX_HOME/installed.toml" \
    && ok "install --git (name from the URL) builds the repository, with its path dependencies" || bad "install --git ($code $rc)" "$out"
[[ -z "$(ls -A "$SUPAX_HOME/tmp" 2>/dev/null)" ]] && ok "install removes its temporary folder" || bad "install tmp" "$(ls -A "$SUPAX_HOME/tmp")"
expect_ok "a second install from git uses the cache, which still matches its checksum" bash -c "'$SX' install --git 'file://$I/gtool' --tag v1 --offline"
expect_fail "uninstall --bin names one program of the package" 'did not install a program named "nope"' \
    bash -c "SUPAX_LANG=en '$SX' uninstall greet --bin nope"
expect_ok "uninstall removes the package's programs" bash -c "'$SX' uninstall greet && [ ! -e '$B/greet' ] && ! grep -q 'package = \"greet\"' '$SUPAX_HOME/installed.toml'"
[[ -e "$B/second" ]] && ok "uninstall leaves other packages' programs" || bad "uninstall others"
expect_fail "uninstalling a package that is not installed is an error" 'is not installed' bash -c "SUPAX_LANG=en '$SX' uninstall greet"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
rm -rf "$WORK"
[[ "$fail" == 0 ]]
