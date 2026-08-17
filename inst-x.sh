#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO="${WP_INST_REPO:-wp-labs/wp-update}"
INSTALL_DIR="${WP_INST_INSTALL_DIR:-$HOME/bin}"
REQUESTED_TAG="${WP_INST_VERSION:-latest}"
WP_SKILLS_REPO="${WP_SKILLS_REPO:-wp-labs/wp-skills}"
WP_SKILLS_REF="${WP_SKILLS_REF:-${2:-main}}"
WPARSE_UPDATES_BASE_URL="${WP_INST_UPDATES_BASE_URL:-https://raw.githubusercontent.com/wp-labs/wp-install/main/updates}"
GX_UPDATES_BASE_URL="${GX_UPDATES_BASE_URL:-https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx}"
GOPS_UPDATES_BASE_URL="${GOPS_UPDATES_BASE_URL:-https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops}"
WFUSION_UPDATES_BASE_URL="${WFUSION_UPDATES_BASE_URL:-https://raw.githubusercontent.com/wp-labs/warp-fusion/main/updates}"
MONITOR_DOCKER_BASE_URL="${MONITOR_DOCKER_BASE_URL:-https://raw.githubusercontent.com/wp-labs/wp-monitor}"
MONITOR_DOCKER_DIR="${MONITOR_DOCKER_DIR:-$PWD/wp-monitor}"
TARGET="${1:-}"
ARG2="${2:-}"
CHANNEL="${ARG2:-}"

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

need_optional_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[wp-inst] missing required command: $1" >&2
        exit 1
    fi
}

resolve_monitor_docker_repo() {
    repo_path="${MONITOR_DOCKER_BASE_URL#https://raw.githubusercontent.com/}"
    repo_path="${repo_path#http://raw.githubusercontent.com/}"

    old_ifs=$IFS
    IFS='/'
    set -- $repo_path
    IFS=$old_ifs

    if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
        echo "[wp-inst] failed to resolve monitor-docker repo from $MONITOR_DOCKER_BASE_URL" >&2
        exit 1
    fi

    printf '%s/%s\n' "$1" "$2"
}

usage() {
    cat <<'EOF'
Usage: inst-x.sh [wparse [stable|beta|alpha] | gx [stable|beta|alpha] | gops [stable|beta|alpha] | wfusion [stable|beta|alpha] | monitor-docker [stable|beta|alpha] | wpl-check | wp-skills [ref] | wplabs-lsp]

Options:
  wparse    After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/wp-labs/wp-install/main/updates
  gx        After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx
  gops      After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops
  wfusion   After installing wp-inst, run:
            wp-inst install --source https://raw.githubusercontent.com/wp-labs/warp-fusion/main/updates
  channel   Optional update channel.
            default: stable
  wpl-check After installing wp-inst, run:
            wp-inst install --github https://github.com/wp-labs/wpl-check --yes
  wp-skills [ref]
            Download wp-skills archive from branch/tag ref (default: main),
            list available skills, and install selected ones interactively
  wplabs-lsp Install wplabs-lsp via lsp_setup.sh
  monitor-docker
             Install wp-monitor docker stack via start.sh
EOF
}

wp_skills_usage() {
    cat <<'EOF'
Usage: inst-x.sh wp-skills [ref]

Download the wp-skills archive from the given branch or tag ref.
Default ref: main

Examples:
  ./inst-x.sh wp-skills
  ./inst-x.sh wp-skills main
  ./inst-x.sh wp-skills v1.0.0

After extraction, the script lists available skills and prompts for
one or more numeric selections separated by spaces.
EOF
}

case "$TARGET" in
    ""|wparse|gx|gops|wfusion|wpl-check|wp-skills|wplabs-lsp|monitor-docker) : ;;
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

if [ "$TARGET" = "wp-skills" ]; then
    case "$ARG2" in
        -h|--help)
            wp_skills_usage
            exit 0
            ;;
    esac
fi

if [ "$TARGET" = "wparse" ] || [ "$TARGET" = "gx" ] || [ "$TARGET" = "gops" ] || [ "$TARGET" = "wfusion" ] || [ "$TARGET" = "monitor-docker" ]; then
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

download_wp_skills_archive() {
    ref="$1"
    archive_path="$2"
    branch_url="https://github.com/${WP_SKILLS_REPO}/archive/refs/heads/${ref}.tar.gz"
    tag_url="https://github.com/${WP_SKILLS_REPO}/archive/refs/tags/${ref}.tar.gz"

    printf '[wp-skills] downloading ref %s from %s\n' "$ref" "$WP_SKILLS_REPO"
    if curl -fL "$branch_url" -o "$archive_path"; then
        printf '[wp-skills] resolved ref type: branch\n'
        return 0
    fi

    if curl -fL "$tag_url" -o "$archive_path"; then
        printf '[wp-skills] resolved ref type: tag\n'
        return 0
    fi

    echo "[wp-skills] failed to download ref '$ref' from $WP_SKILLS_REPO" >&2
    exit 1
}

install_wp_skills() {
    need_optional_cmd tar
    need_optional_cmd find
    need_optional_cmd head
    need_optional_cmd bash

    archive_dir=$(mktemp -d)
    archive_path="$archive_dir/wp-skills.tar.gz"
    cleanup_wp_skills() {
        rm -rf "$archive_dir"
    }
    trap cleanup_wp_skills EXIT INT TERM

    download_wp_skills_archive "$WP_SKILLS_REF" "$archive_path"

    tar -xzf "$archive_path" -C "$archive_dir"
    repo_dir=$(find "$archive_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ -z "$repo_dir" ] || [ ! -d "$repo_dir/skills" ]; then
        echo "[wp-skills] extracted archive does not contain a skills directory" >&2
        exit 1
    fi

    skill_count=0
    for skill_dir in "$repo_dir"/skills/*; do
        if [ -d "$skill_dir" ]; then
            skill_count=$((skill_count + 1))
            skill_name=${skill_dir##*/}
            printf '[wp-skills] detected skill: %s\n' "$skill_name"
        fi
    done

    if [ "$skill_count" -eq 0 ]; then
        echo "[wp-skills] no skills found under $repo_dir/skills" >&2
        exit 1
    fi

    printf '[wp-skills] installing all detected skills\n'
    for skill_dir in "$repo_dir"/skills/*; do
        if [ ! -d "$skill_dir" ]; then
            continue
        fi
        skill_name=${skill_dir##*/}
        printf '[wp-skills] installing %s from ref %s\n' "$skill_name" "$WP_SKILLS_REF"
        (
            cd "$repo_dir"
            bash ./install-skill.sh "$skill_name"
        )
    done

    print_wp_skills_install_summary
}

print_wp_skills_install_summary() {
    install_dirs=""

    if [ -n "${WP_SKILLS_PLATFORM:-}" ]; then
        case "$WP_SKILLS_PLATFORM" in
            codex)
                install_dirs="$HOME/.codex/skills"
                ;;
            claude-code)
                install_dirs="$HOME/.claude/skills"
                ;;
            auto)
                if [ -d "$HOME/.claude/skills" ]; then
                    install_dirs="$HOME/.claude/skills"
                elif [ -d "$HOME/.codex/skills" ]; then
                    install_dirs="$HOME/.codex/skills"
                else
                    install_dirs="$HOME/.claude/skills"
                fi
                ;;
            *)
                install_dirs="$HOME/.claude/skills"
                ;;
        esac
    else
        if [ -d "$HOME/.codex/skills" ]; then
            install_dirs="$install_dirs $HOME/.codex/skills"
        fi
        if [ -d "$HOME/.claude/skills" ]; then
            install_dirs="$install_dirs $HOME/.claude/skills"
        fi
        if [ -z "$install_dirs" ]; then
            install_dirs="$HOME/.claude/skills"
        fi
    fi

    echo "[wp-skills] 安装成功"
    for install_dir in $install_dirs; do
        printf '[wp-skills] 安装的目录: %s\n' "$install_dir"
    done
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

NEEDS_WP_INST=""
case "$TARGET" in
    ""|wparse|gx|gops|wfusion|wpl-check) NEEDS_WP_INST="1" ;;
esac

if [ -n "$NEEDS_WP_INST" ]; then
    DOWNLOAD_FILE=$(mktemp)
    cleanup() { rm -f "$DOWNLOAD_FILE"; }
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

if [ "$TARGET" = "wfusion" ]; then
    printf '[wp-inst] running: %s install --channel %s --source %s --dir %s --yes\n' "$DEST" "$CHANNEL" "$WFUSION_UPDATES_BASE_URL" "$INSTALL_DIR"
    "$DEST" install --channel "$CHANNEL" --source "$WFUSION_UPDATES_BASE_URL" --dir "$INSTALL_DIR" --yes
fi

if [ "$TARGET" = "wpl-check" ]; then
    printf '[wp-inst] running: %s install --github %s --yes\n' "$DEST" "https://github.com/wp-labs/wpl-check"
    "$DEST" install --github "https://github.com/wp-labs/wpl-check" --yes
fi

if [ "$TARGET" = "wp-skills" ]; then
    install_wp_skills
fi

if [ "$TARGET" = "wplabs-lsp" ]; then
    printf '[wp-inst] running: %s/lsp_setup.sh\n' "$SCRIPT_DIR"
    "$SCRIPT_DIR/lsp_setup.sh"
fi

if [ "$TARGET" = "monitor-docker" ]; then
    need_optional_cmd tar
    need_optional_cmd cp
    need_optional_cmd find
    need_optional_cmd head

    case "$CHANNEL" in
        alpha) BRANCH="alpha" ;;
        beta)  BRANCH="beta" ;;
        stable) BRANCH="main" ;;
    esac
    MONITOR_DOCKER_REPO=$(resolve_monitor_docker_repo)
    ARCHIVE_DIR=$(mktemp -d)
    ARCHIVE_PATH="$ARCHIVE_DIR/wp-monitor.tar.gz"
    ARCHIVE_URL="https://github.com/${MONITOR_DOCKER_REPO}/archive/refs/heads/${BRANCH}.tar.gz"
    cleanup_monitor_docker() {
        rm -rf "$ARCHIVE_DIR"
    }
    trap cleanup_monitor_docker EXIT INT TERM

    printf '[wp-inst] monitor-docker 安装步骤 (%s channel, %s branch):\n' "$CHANNEL" "$BRANCH"
    printf '  [1/3] 下载仓库归档\n'
    printf '  [2/3] 解压 install/docker 到 %s\n' "$MONITOR_DOCKER_DIR"
    printf '  [3/3] 运行 ./start.sh %s\n' "$CHANNEL"
    printf '\n'

    printf '[wp-inst] [1/3] 下载 %s\n' "$ARCHIVE_URL"
    curl -fL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

    tar -xzf "$ARCHIVE_PATH" -C "$ARCHIVE_DIR"
    EXTRACTED_REPO_DIR=$(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    SOURCE_DOCKER_DIR="$EXTRACTED_REPO_DIR/install/docker"
    if [ ! -d "$SOURCE_DOCKER_DIR" ]; then
        echo "[wp-inst] extracted archive does not contain install/docker" >&2
        exit 1
    fi

    printf '[wp-inst] [2/3] 解压 install/docker 到 %s\n' "$MONITOR_DOCKER_DIR"
    mkdir -p "$MONITOR_DOCKER_DIR"
    cp -R "$SOURCE_DOCKER_DIR"/. "$MONITOR_DOCKER_DIR"/

    chmod +x "$MONITOR_DOCKER_DIR/start.sh"

    printf '[wp-inst] [3/3] 运行: %s/start.sh %s\n' "$MONITOR_DOCKER_DIR" "$CHANNEL"
    (
        cd "$MONITOR_DOCKER_DIR"
        ./start.sh "$CHANNEL" -f
    )
fi

printf '\nEnsure %s is on your PATH, e.g.:\n  export PATH="%s":$PATH\n\n' "$INSTALL_DIR" "$INSTALL_DIR"
printf 'Optional env vars:\n  WP_INST_VERSION=v0.1.5\n  WP_INST_INSTALL_DIR=/usr/local/bin\n  WP_INST_REPO=wp-labs/wp-update\n  WP_INST_UPDATES_BASE_URL=https://raw.githubusercontent.com/wp-labs/wp-install/main/updates\n  GX_UPDATES_BASE_URL=https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx\n  GOPS_UPDATES_BASE_URL=https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops\n  WFUSION_UPDATES_BASE_URL=https://raw.githubusercontent.com/wp-labs/warp-fusion/main/updates\n  WP_SKILLS_REPO=wp-labs/wp-skills\n  WP_SKILLS_REF=main\n  MONITOR_DOCKER_BASE_URL=https://raw.githubusercontent.com/wp-labs/wp-monitor\n'
