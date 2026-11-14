#!/usr/bin/env bash
# يثبت sultanc والمكتبة القياسية وسوباكس في بيت سوباكس (~/.supax):
#   ~/.supax/bin/sultanc
#   ~/.supax/bin/supax
#   ~/.supax/lib/sultanc/library
#
# Installs sultanc, its standard library and Supax into the Supax home (~/.supax).
#
#   tools/install.sh [path/to/sultanc-checkout] [--no-modify-path]   (default: ../sultanc)
#
# The SultanC checkout must already be built (./build.sh), so that
# <checkout>/build/sultanc exists. Set SUPAX_HOME to install elsewhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKOUT_ARG="$ROOT/../sultanc"
for arg in "$@"; do [[ "$arg" != --* ]] && CHECKOUT_ARG="$arg"; done
CHECKOUT="$(cd "$CHECKOUT_ARG" && pwd)"
HOME_DIR="${SUPAX_HOME:-$HOME/.supax}"
BIN="$HOME_DIR/bin"
LIB="$HOME_DIR/lib/sultanc"

if [[ ! -x "$CHECKOUT/build/sultanc" ]]; then
    echo "لم يُعثر على $CHECKOUT/build/sultanc؛ ابنِ المترجم أولا: (cd $CHECKOUT && ./build.sh)" >&2
    echo "not found: $CHECKOUT/build/sultanc; build the compiler first: (cd $CHECKOUT && ./build.sh)" >&2
    exit 1
fi
if [[ ! -d "$CHECKOUT/library/std" ]]; then
    echo "not found: $CHECKOUT/library/std" >&2
    exit 1
fi

mkdir -p "$BIN" "$LIB"

# Replace each file through a temporary name so a running copy is never overwritten in place.
install_file() {
    cp "$1" "$2.tmp.$$"
    chmod 755 "$2.tmp.$$"
    mv -f "$2.tmp.$$" "$2"
}

install_file "$CHECKOUT/build/sultanc" "$BIN/sultanc"
rm -rf "$LIB/library.tmp.$$"
cp -R "$CHECKOUT/library" "$LIB/library.tmp.$$"
rm -rf "$LIB/library"
mv "$LIB/library.tmp.$$" "$LIB/library"

# Build Supax with the installed compiler: this also proves that the installed
# sultanc finds its standard library on its own.
mkdir -p "$ROOT/build"
# A compiler with --package-graph no longer reads Supax.toml: give it Supax's
# checked-in graph (paths relative to bootstrap/).
graph_args=()
probe="$("$BIN/sultanc" --package-graph 2>&1 || true)"
if [[ "$probe" != *SULTANC-CLI-UNKNOWN-OPTION* ]]; then
    graph_args=("--package-graph=$ROOT/bootstrap/package-graph.toml")
fi
(cd "$ROOT" && env -u SULTANC_STD "$BIN/sultanc" ${graph_args[@]+"${graph_args[@]}"} src/main.sn -o build/supax.install)
install_file "$ROOT/build/supax.install" "$BIN/supax"
rm -f "$ROOT/build/supax.install"

echo "sultanc: $("$BIN/sultanc" --version | head -1)"
echo "supax:   $("$BIN/supax" --version)"
echo "installed in $HOME_DIR"

# Put ~/.supax/bin on PATH for every new terminal, as rustup does: write an env
# file, and source it from the shell profiles. Each step is skipped when it is
# already done, so running the installer again changes nothing.
# Pass --no-modify-path (or set SUPAX_NO_MODIFY_PATH=1) to skip this.
ENV_FILE="$HOME_DIR/env"
cat > "$ENV_FILE" <<ENVEOF
# Added by the Supax installer.
case ":\${PATH}:" in
    *":$BIN:"*) ;;
    *) export PATH="$BIN:\$PATH" ;;
esac
ENVEOF

modify_path=1
for arg in "$@"; do [[ "$arg" == "--no-modify-path" ]] && modify_path=0; done
[[ "${SUPAX_NO_MODIFY_PATH:-0}" == 1 ]] && modify_path=0

if [[ "$modify_path" == 1 ]]; then
    line=". \"$ENV_FILE\""
    profiles=("$HOME/.zshenv" "$HOME/.profile")
    [[ -f "$HOME/.bashrc" ]] && profiles+=("$HOME/.bashrc")
    [[ -f "$HOME/.bash_profile" ]] && profiles+=("$HOME/.bash_profile")
    for profile in "${profiles[@]}"; do
        if [[ -f "$profile" ]] && grep -qF "$ENV_FILE" "$profile"; then
            continue
        fi
        printf '\n%s\n' "$line" >> "$profile"
        echo "PATH: added to $profile"
    done
fi

case ":$PATH:" in
    *":$BIN:"*) ;;
    *)
        echo
        echo "افتح نافذة طرفية جديدة، أو شغّل هذا السطر في النافذة الحالية:"
        echo "Open a new terminal, or run this in the current one:"
        echo
        echo "    . \"$ENV_FILE\""
        ;;
esac
