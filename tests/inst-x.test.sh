#!/usr/bin/env sh
set -eu

PASS=0
FAIL=0
INST_X="$(cd "$(dirname "$0")/.." && pwd)/inst-x.sh"

pass() { PASS=$((PASS + 1)); echo "  ok  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  not ok  $1"; }

mock_setup() {
    TESTDIR=$(mktemp -d /tmp/inst-x-test.XXXXXX)
    MOCKDIR="$TESTDIR/mocks"
    mkdir -p "$MOCKDIR"

    cat > "$MOCKDIR/curl" <<'MOCK'
#!/bin/sh
echo "[MOCK curl] $*" >> "$MOCK_TRACE"
for arg in "$@"; do
    case "$arg" in */releases/latest) echo "https://github.com/wp-labs/wp-update/releases/tag/v9.9.9"; exit 0 ;; esac
done
next=0
for arg in "$@"; do
    if [ "$next" = "1" ]; then
        case "$arg" in
            *start.sh) printf '#!/bin/sh\necho "start.sh OK: channel=$1"\n' > "$arg" ;;
            *)
                printf '#!/bin/sh\ncase "$1" in -V) echo "wp-inst vtesting" ;; install) echo "mock-install: $*" ;; --skill) echo "mock-skill: $*" ;; esac\n' > "$arg"
                chmod +x "$arg"
                ;;
        esac
        exit 0
    fi
    if [ "$arg" = "-o" ]; then next=1; fi
done
exit 0
MOCK
    chmod +x "$MOCKDIR/curl"

    cat > "$MOCKDIR/uname" <<'MOCK'
#!/bin/sh
case "$1" in
    -s) echo "${MOCK_UNAME_S:-Linux}" ;;
    -m) echo "${MOCK_UNAME_M:-x86_64}" ;;
    *)  echo "${MOCK_UNAME_S:-Linux}" ;;
esac
MOCK
    chmod +x "$MOCKDIR/uname"

    export PATH="$MOCKDIR:$PATH"
    export MOCK_TRACE="$TESTDIR/trace.txt"
    > "$MOCK_TRACE"
    export MOCK_UNAME_S="Linux"
    export MOCK_UNAME_M="x86_64"
    export WP_INST_INSTALL_DIR="$TESTDIR/install"
    export HOME="$TESTDIR/home"
    export WP_INST_VERSION="testing"
}

mock_teardown() {
    rm -rf "${TESTDIR:-}"
}

# ============================================================
echo "=== CLI argument parsing"

set +e

_output=$("$INST_X" -h 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$_output" | grep -q "Usage"; then
    pass "prints usage with -h"
else
    fail "prints usage with -h"
fi

_output=$("$INST_X" --help 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$_output" | grep -q "Usage"; then
    pass "prints usage with --help"
else
    fail "prints usage with --help"
fi

_output=$("$INST_X" invalid-target 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$_output" | grep -q "unsupported target"; then
    pass "exits with error for invalid target"
else
    fail "exits with error for invalid target"
fi

_output=$("$INST_X" wparse invalid-channel 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$_output" | grep -q "unsupported channel"; then
    pass "exits with error for invalid channel (wparse)"
else
    fail "exits with error for invalid channel (wparse)"
fi

_output=$("$INST_X" monitor-docker invalid-channel 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$_output" | grep -q "unsupported channel"; then
    pass "exits with error for invalid channel (monitor-docker)"
else
    fail "exits with error for invalid channel (monitor-docker)"
fi

set -e

# ============================================================
echo "=== wp-inst download skip logic"

mock_setup; set +e
"$INST_X" wplabs-lsp >/dev/null 2>&1; set -e
if ! grep -q "releases" "$MOCK_TRACE" 2>/dev/null; then
    pass "wplabs-lsp skips wp-inst download"
else
    fail "wplabs-lsp skips wp-inst download"
fi
mock_teardown

mock_setup; set +e
"$INST_X" monitor-docker alpha >/dev/null 2>&1; set -e
if ! grep -q "releases" "$MOCK_TRACE" 2>/dev/null; then
    pass "monitor-docker skips wp-inst download"
else
    fail "monitor-docker skips wp-inst download"
fi
mock_teardown

mock_setup; set +e
"$INST_X" wparse >/dev/null 2>&1; set -e
if grep -q "releases/download" "$MOCK_TRACE" 2>/dev/null; then
    pass "wparse triggers wp-inst download"
else
    fail "wparse triggers wp-inst download"
fi
mock_teardown

# ============================================================
echo "=== monitor-docker"

mock_setup; set +e
MDIR="$HOME/.wp-monitor/docker"
"$INST_X" monitor-docker alpha >/dev/null 2>&1; set -e
all_ok=1
for f in start.sh docker-compose-alpha.yml .env.example; do
    [ -f "$MDIR/$f" ] || all_ok=0
done
[ -x "$MDIR/start.sh" ] || all_ok=0
if [ "$all_ok" = "1" ]; then
    pass "monitor-docker alpha downloads all files"
else
    fail "monitor-docker alpha downloads all files"
fi
mock_teardown

mock_setup; set +e
_output=$("$INST_X" monitor-docker stable 2>&1); set -e
if echo "$_output" | grep -q "main branch"; then
    pass "monitor-docker stable uses main branch"
else
    fail "monitor-docker stable uses main branch"
fi
mock_teardown

mock_setup; set +e
_output=$("$INST_X" monitor-docker beta 2>&1); set -e
if echo "$_output" | grep -q "beta branch"; then
    pass "monitor-docker beta uses beta branch"
else
    fail "monitor-docker beta uses beta branch"
fi
mock_teardown

# ============================================================
echo "=== version match skip"

mock_setup
mkdir -p "$WP_INST_INSTALL_DIR"
cat > "$WP_INST_INSTALL_DIR/wp-inst" <<'SCRIPT'
#!/bin/sh
echo "wp-inst vtesting"
SCRIPT
chmod +x "$WP_INST_INSTALL_DIR/wp-inst"
cat > "$WP_INST_INSTALL_DIR/.wp-inst-release-meta" <<'META'
repo=wp-labs/wp-update
tag=vtesting
target=x86_64-unknown-linux-gnu
META
> "$MOCK_TRACE"

set +e
_output=$("$INST_X" wparse 2>&1); rc=$?
set -e

skip_ok=0
if [ "$rc" -eq 0 ] && echo "$_output" | grep -q "already installed" && ! grep -q "releases" "$MOCK_TRACE" 2>/dev/null; then
    skip_ok=1
fi
if [ "$skip_ok" = "1" ]; then
    pass "skips download when same version already installed"
else
    fail "skips download when same version already installed"
fi
mock_teardown

# ============================================================
TOTAL=$((PASS + FAIL))
echo "1..$TOTAL"
echo "# tests $TOTAL"
echo "# pass  $PASS"
echo "# fail  $FAIL"

[ "$FAIL" -eq 0 ]
