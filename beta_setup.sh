#!/usr/bin/env sh
set -euo pipefail

INSTALL_DIR="${WARP_PARSE_INSTALL_DIR:-$HOME/bin}"
REQUESTED_TAG="${WARP_PARSE_VERSION:-latest}"
MANIFEST_URL="${WARP_PARSE_MANIFEST_URL:-https://raw.githubusercontent.com/wp-labs/wp-install/main/updates/beta/manifest.json}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[warp-parse] missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl
need_cmd uname
need_cmd mktemp
need_cmd tar
need_cmd install
need_cmd find
need_cmd python3
need_cmd sed

sha256_check() {
    expected="$1"
    file="$2"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$expected" "$file" | sha256sum -c - >/dev/null
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s  %s\n' "$expected" "$file" | shasum -a 256 -c - >/dev/null
    else
        echo "[warp-parse:beta] missing required command: sha256sum or shasum" >&2
        exit 1
    fi
}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux|darwin) : ;;
    *)
        echo "[warp-parse] unsupported OS: $OS" >&2
        exit 1
        ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
        echo "[warp-parse] unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

TMP_DIR=$(mktemp -d)
MANIFEST_FILE=$(mktemp)
cleanup() {
    rm -rf "$TMP_DIR"
    rm -f "$MANIFEST_FILE"
}
trap cleanup EXIT

printf '[warp-parse:beta] fetching manifest %s\n' "$MANIFEST_URL"
if ! curl -fsSL "$MANIFEST_URL" -o "$MANIFEST_FILE"; then
    echo "[warp-parse:beta] failed to download manifest" >&2
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

version = data.get("version", "")
if not version:
    sys.exit("manifest missing version")

def normalize(ver: str) -> str:
    return ver if ver.startswith("v") else f"v{ver}"

resolved = normalize(version)
if requested != "latest" and normalize(requested) != resolved:
    sys.exit(f"version '{requested}' not found in manifest (current: {resolved})")

target_map = {
    ("darwin", "arm64"): "aarch64-apple-darwin",
    ("darwin", "x86_64"): "x86_64-apple-darwin",
    ("linux", "arm64"): "aarch64-unknown-linux-gnu",
    ("linux", "x86_64"): "x86_64-unknown-linux-gnu",
}
target = target_map.get((os_key, arch_key))
if not target:
    sys.exit(f"unsupported target combination: {os_key}-{arch_key}")

asset = data.get("assets", {}).get(target, {})
url = asset.get("url", "")
if not url:
    sys.exit(f"no asset url entry for {target}")
sha256 = asset.get("sha256", "")
if not sha256:
    sys.exit(f"no asset sha256 entry for {target}")

print(resolved)
print(url)
print(sha256)
PY
)

TAG=$(printf '%s' "$PY_OUT" | sed -n '1p')
DOWNLOAD_URL=$(printf '%s' "$PY_OUT" | sed -n '2p')
EXPECTED_SHA256=$(printf '%s' "$PY_OUT" | sed -n '3p')

if [ -z "$TAG" ] || [ -z "$DOWNLOAD_URL" ] || [ -z "$EXPECTED_SHA256" ]; then
    echo "[warp-parse:beta] failed to resolve download artifact" >&2
    exit 1
fi

ASSET_NAME="${DOWNLOAD_URL##*/}"
ARCHIVE_PATH="$TMP_DIR/$ASSET_NAME"
printf '[warp-parse:beta] downloading %s\n' "$DOWNLOAD_URL"
if ! curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"; then
    echo "[warp-parse:beta] download failed" >&2
    exit 1
fi
printf '[warp-parse:beta] verifying sha256 %s\n' "$ASSET_NAME"
if ! sha256_check "$EXPECTED_SHA256" "$ARCHIVE_PATH"; then
    echo "[warp-parse:beta] sha256 verification failed for $ASSET_NAME" >&2
    exit 1
fi

tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
mkdir -p "$INSTALL_DIR"

BINARIES="wparse wpgen wprescue wpadm"
INSTALLED=""
for bin in $BINARIES; do
    BIN_PATH=$(find "$TMP_DIR" -maxdepth 3 -type f -name "$bin" | head -n 1)
    if [ -n "$BIN_PATH" ]; then
        install -m 755 "$BIN_PATH" "$INSTALL_DIR/$bin"
        INSTALLED="$INSTALLED $bin"
    fi
done

if [ -z "$INSTALLED" ]; then
    echo "[warp-parse:beta] no binaries were installed (archive layout unexpected)" >&2
    exit 1
fi

printf '[warp-parse:beta] installed binaries:%s\n' "$INSTALLED"
printf '[warp-parse:beta] location: %s\n' "$INSTALL_DIR"
printf '\nEnsure %s is on your PATH, e.g.:\n  export PATH="%s":$PATH\n\n' "$INSTALL_DIR" "$INSTALL_DIR"
