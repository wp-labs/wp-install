#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO="${WP_INST_REPO:-wp-labs/wp-update}"
INSTALL_DIR="${WP_INST_INSTALL_DIR:-$HOME/bin}"
REQUESTED_TAG="${WP_INST_VERSION:-latest}"
WP_SKILLS_REPO="${WP_SKILLS_REPO:-wp-labs/wp-skills}"
WP_SKILLS_PATH="${WP_SKILLS_PATH:-skills/warpparse-log-engineering}"
WP_SKILLS_VERSION="${WP_SKILLS_VERSION:-latest}"
WPARSE_UPDATES_BASE_URL="${WP_INST_UPDATES_BASE_URL:-https://raw.githubusercontent.com/wp-labs/wp-install/main/updates}"
GX_UPDATES_BASE_URL="${GX_UPDATES_BASE_URL:-https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx}"
GOPS_UPDATES_BASE_URL="${GOPS_UPDATES_BASE_URL:-https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops}"
TARGET="${1:-}"
CHANNEL="${2:-}"

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
Usage: inst-x.sh [wparse [stable|beta|alpha] | gx [stable|beta|alpha] | gops [stable|beta|alpha] | wpl-check | wp-skills | wplabs-lsp]

Options:
  wparse    After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/wp-labs/wp-install/main/updates
  gx        After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx
  gops      After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops
  channel   Optional update channel.
            default: stable
  wpl-check After installing wp-inst, run:
            wp-inst install --github https://github.com/wp-labs/wpl-check --yes
  wp-skills After installing wp-inst, run:
            wp-inst --skill --github https://github.com/wp-labs/wp-skills --path skills/warpparse-log-engineering
  wplabs-lsp Install wplabs-lsp via lsp_setup.sh
EOF
}

case "$TARGET" in
    ""|wparse|gx|gops|wpl-check|wp-skills|wplabs-lsp) : ;;
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

if [ -z "$CHANNEL" ]; then
    CHANNEL="stable"
fi

if [ "$TARGET" = "wparse" ] || [ "$TARGET" = "gx" ] || [ "$TARGET" = "gops" ]; then
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
DEST="$INSTALL_DIR/wp-inst"
META_FILE="$INSTALL_DIR/.wp-inst-release-meta"

printf '[wp-inst] resolved version: %s\n' "$TAG"
printf '[wp-inst] resolved asset: %s\n' "$ASSET_NAME"

mkdir -p "$INSTALL_DIR"
INSTALLED_TAG=""
INSTALLED_REPO=""
INSTALLED_TARGET=""
if [ -x "$DEST" ]; then
    VERSION_OUTPUT=$("$DEST" -V 2>/dev/null || true)
    case "$VERSION_OUTPUT" in
        "wp-inst "*) INSTALLED_TAG=$(normalize_tag "${VERSION_OUTPUT#wp-inst }") ;;
    esac
fi
if [ -f "$META_FILE" ]; then
    while IFS='=' read -r KEY VALUE; do
        case "$KEY" in
            repo) INSTALLED_REPO="$VALUE" ;;
            target) INSTALLED_TARGET="$VALUE" ;;
        esac
    done < "$META_FILE"
fi

if [ "$INSTALLED_TAG" = "$TAG" ] && [ "$INSTALLED_REPO" = "$REPO" ] && [ "$INSTALLED_TARGET" = "$TARGET_TRIPLE" ]; then
    printf '[wp-inst] already installed: %s (%s from %s for %s)\n' "$DEST" "$TAG" "$REPO" "$TARGET_TRIPLE"
else
    printf '[wp-inst] downloading %s\n' "$DOWNLOAD_URL"
    if ! curl -fL "$DOWNLOAD_URL" -o "$DOWNLOAD_FILE"; then
        echo "[wp-inst] download failed" >&2
        exit 1
    fi

    install -m 755 "$DOWNLOAD_FILE" "$DEST"
    {
        printf 'repo=%s\n' "$REPO"
        printf 'tag=%s\n' "$TAG"
        printf 'target=%s\n' "$TARGET_TRIPLE"
    } > "$META_FILE"
    printf '[wp-inst] installed: %s\n' "$DEST"
    printf '[wp-inst] version: %s\n' "$TAG"
fi

if [ "$TARGET" = "wparse" ]; then
    printf '[wp-inst] running: %s install --channel %s --source %s --dir %s --yes\n' "$DEST" "$CHANNEL" "$WPARSE_UPDATES_BASE_URL" "$INSTALL_DIR"
    "$DEST" install --channel "$CHANNEL" --source "$WPARSE_UPDATES_BASE_URL" --dir "$INSTALL_DIR" --yes
fi

if [ "$TARGET" = "gx" ]; then
    printf '[wp-inst] running: %s install --channel %s --source %s --dir %s --yes\n' "$DEST" "$CHANNEL" "$GX_UPDATES_BASE_URL" "$INSTALL_DIR"
    "$DEST" install --channel "$CHANNEL" --source "$GX_UPDATES_BASE_URL" --dir "$INSTALL_DIR" --yes
fi

if [ "$TARGET" = "gops" ]; then
    printf '[wp-inst] running: %s install --channel %s --source %s --dir %s --yes\n' "$DEST" "$CHANNEL" "$GOPS_UPDATES_BASE_URL" "$INSTALL_DIR"
    "$DEST" install --channel "$CHANNEL" --source "$GOPS_UPDATES_BASE_URL" --dir "$INSTALL_DIR" --yes
fi

if [ "$TARGET" = "wpl-check" ]; then
    printf '[wp-inst] running: %s install --github %s --yes\n' "$DEST" "https://github.com/wp-labs/wpl-check"
    "$DEST" install --github "https://github.com/wp-labs/wpl-check" --yes
fi

if [ "$TARGET" = "wp-skills" ]; then
    if [ "$WP_SKILLS_VERSION" = "latest" ]; then
        printf '[wp-inst] running: %s --skill --github %s --path %s\n' "$DEST" "https://github.com/${WP_SKILLS_REPO}" "$WP_SKILLS_PATH"
        "$DEST" --skill --github "https://github.com/${WP_SKILLS_REPO}" --path "$WP_SKILLS_PATH"
    else
        WP_SKILLS_TAG=$(normalize_tag "$WP_SKILLS_VERSION")
        printf '[wp-inst] running: %s --skill --github %s --path %s --tag %s\n' "$DEST" "https://github.com/${WP_SKILLS_REPO}" "$WP_SKILLS_PATH" "$WP_SKILLS_TAG"
        "$DEST" --skill --github "https://github.com/${WP_SKILLS_REPO}" --path "$WP_SKILLS_PATH" --tag "$WP_SKILLS_TAG"
    fi
fi

if [ "$TARGET" = "wplabs-lsp" ]; then
    printf '[wp-inst] running: %s/lsp_setup.sh\n' "$SCRIPT_DIR"
    "$SCRIPT_DIR/lsp_setup.sh"
fi

printf '\nEnsure %s is on your PATH, e.g.:\n  export PATH="%s":$PATH\n\n' "$INSTALL_DIR" "$INSTALL_DIR"
printf 'Optional env vars:\n  WP_INST_VERSION=v0.1.5\n  WP_INST_INSTALL_DIR=/usr/local/bin\n  WP_INST_REPO=wp-labs/wp-update\n  WP_INST_UPDATES_BASE_URL=https://raw.githubusercontent.com/wp-labs/wp-install/main/updates\n  GX_UPDATES_BASE_URL=https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx\n  GOPS_UPDATES_BASE_URL=https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops\n  WP_SKILLS_REPO=wp-labs/wp-skills\n  WP_SKILLS_PATH=skills/warpparse-log-engineering\n  WP_SKILLS_VERSION=latest\n'
