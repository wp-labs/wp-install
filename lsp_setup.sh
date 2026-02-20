#!/usr/bin/env sh
set -euo pipefail

REPO="wp-labs/wplabs-lsp"
INSTALL_DIR="${WPLABS_LSP_INSTALL_DIR:-$HOME/bin}"
REQUESTED_TAG="${WPLABS_LSP_VERSION:-latest}"
MANIFEST_URL="${WPLABS_LSP_MANIFEST_URL:-https://raw.githubusercontent.com/wp-labs/wplabs-lsp/main/dist/install-manifest.json}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[wplabs-lsp] missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl
need_cmd uname
need_cmd mktemp
need_cmd python3

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux|darwin) : ;;
    *)
        echo "[wplabs-lsp] unsupported OS: $OS" >&2
        exit 1
        ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
        echo "[wplabs-lsp] unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

MANIFEST_FILE=$(mktemp)
cleanup() {
    rm -f "$MANIFEST_FILE"
}
trap cleanup EXIT

printf '[wplabs-lsp] fetching manifest %s\n' "$MANIFEST_URL"
if ! curl -fsSL "$MANIFEST_URL" -o "$MANIFEST_FILE"; then
    echo "[wplabs-lsp] failed to download manifest" >&2
    exit 1
fi

PY_OUT=$(python3 - "$REQUESTED_TAG" "$OS" "$ARCH" "$MANIFEST_FILE" <<'PY'
import json
import sys

requested = sys.argv[1]
os_key = sys.argv[2]
arch_key = sys.argv[3]
manifest_path = sys.argv[4]

with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

releases = data.get("releases", [])
if not releases:
    sys.exit("manifest contains no releases")

def normalize(ver: str) -> str:
    return ver if ver.startswith("v") else f"v{ver}"

selected = None
if requested == "latest":
    selected = releases[0]
else:
    needle = normalize(requested)
    for rel in releases:
        ver = rel.get("version", "")
        if ver == needle or ver.lstrip("v") == requested.lstrip("v"):
            selected = rel
            break

if selected is None:
    sys.exit(f"version '{requested}' not found in manifest")

key = f"{os_key}-{arch_key}"
asset = selected.get("artifacts", {}).get(key)
if not asset:
    sys.exit(f"no artifact entry for {key}")

ver = selected.get("version", "")
print(ver if ver.startswith("v") else f"v{ver}")
print(asset)
PY
)

TAG=$(printf '%s' "$PY_OUT" | sed -n '1p')
ASSET=$(printf '%s' "$PY_OUT" | sed -n '2p')

if [ -z "$TAG" ] || [ -z "$ASSET" ]; then
    echo "[wplabs-lsp] failed to resolve download artifact" >&2
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
printf '[wplabs-lsp] downloading %s\n' "$DOWNLOAD_URL"

mkdir -p "$INSTALL_DIR"
DEST="$INSTALL_DIR/wplabs-lsp"

if ! curl -fL "$DOWNLOAD_URL" -o "$DEST"; then
    echo "[wplabs-lsp] download failed" >&2
    exit 1
fi

chmod 755 "$DEST"

printf '[wplabs-lsp] installed: %s\n' "$DEST"
printf '\nEnsure %s is on your PATH, e.g.:\n  export PATH="%s":$PATH\n\n' "$INSTALL_DIR" "$INSTALL_DIR"
printf 'Optional env vars:\n  WPLABS_LSP_VERSION=0.1.1\n  WPLABS_LSP_INSTALL_DIR=/usr/local/bin\n  WPLABS_LSP_MANIFEST_URL=https://example.com/custom-manifest.json\n'
