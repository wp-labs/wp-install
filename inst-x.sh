#!/usr/bin/env sh
set -euo pipefail

REPO="${WP_INST_REPO:-wp-labs/wp-update}"
INSTALL_DIR="${WP_INST_INSTALL_DIR:-$HOME/bin}"
REQUESTED_TAG="${WP_INST_VERSION:-latest}"
UPDATES_BASE_URL="${WP_INST_UPDATES_BASE_URL:-https://raw.githubusercontent.com/wp-labs/wp-install/main/updates}"
TARGET="${1:-}"
CHANNEL="${2:-stable}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[wp-inst] missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl
need_cmd uname
need_cmd mktemp
need_cmd install

usage() {
    cat <<'EOF'
Usage: inst-x.sh [wparse [stable|beta|alpha] | wpl-check]

Options:
  wparse    After installing wp-inst, run:
            wp-inst update --base-url https://raw.githubusercontent.com/wp-labs/wp-install/main/updates
  channel   Optional update channel for wparse. Default: stable
  wpl-check After installing wp-inst, run:
            wp-inst --github https://github.com/wp-labs/wpl-check --latest --yes
EOF
}

case "$TARGET" in
    ""|wparse|wpl-check) : ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "[wp-inst] unsupported target: $TARGET" >&2
        usage >&2
        exit 1
        ;;
esac

if [ "$TARGET" = "wparse" ]; then
    case "$CHANNEL" in
        stable|beta|alpha) : ;;
        *)
            echo "[wp-inst] unsupported channel: $CHANNEL" >&2
            usage >&2
            exit 1
            ;;
    esac
fi

normalize_tag() {
    case "$1" in
        v*) printf '%s\n' "$1" ;;
        *) printf 'v%s\n' "$1" ;;
    esac
}

release_endpoint() {
    case "$REQUESTED_TAG" in
        latest) printf 'https://github.com/%s/releases/latest\n' "$REPO" ;;
        *) printf 'https://github.com/%s/releases/tag/%s\n' "$REPO" "$(normalize_tag "$REQUESTED_TAG")" ;;
    esac
}

resolve_tag() {
    case "$REQUESTED_TAG" in
        latest)
            EFFECTIVE_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$(release_endpoint)") || {
                echo "[wp-inst] failed to resolve latest release tag" >&2
                exit 1
            }
            TAG="${EFFECTIVE_URL##*/}"
            if [ -z "$TAG" ]; then
                echo "[wp-inst] failed to parse latest release tag from $EFFECTIVE_URL" >&2
                exit 1
            fi
            normalize_tag "$TAG"
            ;;
        *)
            normalize_tag "$REQUESTED_TAG"
            ;;
    esac
}

resolve_target() {
    case "$OS-$ARCH" in
        darwin-arm64) printf 'aarch64-apple-darwin\n' ;;
        darwin-x86_64) printf 'x86_64-apple-darwin\n' ;;
        linux-arm64) printf 'aarch64-unknown-linux-gnu\n' ;;
        linux-x86_64) printf 'x86_64-unknown-linux-gnu\n' ;;
        *)
            echo "[wp-inst] unsupported target combination: $OS-$ARCH" >&2
            exit 1
            ;;
    esac
}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux|darwin) : ;;
    *)
        echo "[wp-inst] unsupported OS: $OS" >&2
        exit 1
        ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
        echo "[wp-inst] unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

DOWNLOAD_FILE=$(mktemp)
cleanup() {
    rm -f "$DOWNLOAD_FILE"
}
trap cleanup EXIT

TAG=$(resolve_tag)
TARGET_TRIPLE=$(resolve_target)
ASSET_NAME="wp-inst-${TAG}-${TARGET_TRIPLE}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"

printf '[wp-inst] resolved version: %s\n' "$TAG"
printf '[wp-inst] resolved asset: %s\n' "$ASSET_NAME"

printf '[wp-inst] downloading %s\n' "$DOWNLOAD_URL"
if ! curl -fL "$DOWNLOAD_URL" -o "$DOWNLOAD_FILE"; then
    echo "[wp-inst] download failed" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
DEST="$INSTALL_DIR/wp-inst"
install -m 755 "$DOWNLOAD_FILE" "$DEST"

printf '[wp-inst] installed: %s\n' "$DEST"
printf '[wp-inst] version: %s\n' "$TAG"

if [ "$TARGET" = "wparse" ]; then
    printf '[wp-inst] running: %s update --channel %s --base-url %s --install-dir %s --yes\n' "$DEST" "$CHANNEL" "$UPDATES_BASE_URL" "$INSTALL_DIR"
    "$DEST" update --channel "$CHANNEL" --base-url "$UPDATES_BASE_URL" --install-dir "$INSTALL_DIR" --yes
fi

if [ "$TARGET" = "wpl-check" ]; then
    printf '[wp-inst] running: %s --github %s --latest --yes\n' "$DEST" "https://github.com/wp-labs/wpl-check"
    "$DEST" --github "https://github.com/wp-labs/wpl-check" --latest --yes
fi

printf '\nEnsure %s is on your PATH, e.g.:\n  export PATH="%s":$PATH\n\n' "$INSTALL_DIR" "$INSTALL_DIR"
printf 'Optional env vars:\n  WP_INST_VERSION=v0.1.5\n  WP_INST_INSTALL_DIR=/usr/local/bin\n  WP_INST_REPO=wp-labs/wp-update\n  WP_INST_UPDATES_BASE_URL=https://raw.githubusercontent.com/wp-labs/wp-install/main/updates\n'
