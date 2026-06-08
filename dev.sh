#!/usr/bin/env bash
#
# dev.sh — build / run / install / lint helper for this caelestia shell fork.
#
# Why this exists: testing changes by `sudo cmake --install`-ing into the
# system dirs is fragile. CMake's install compares timestamps at whole-second
# granularity, so it silently SKIPS some freshly-built plugin .so files while
# copying others, leaving a MISMATCHED plugin set in /usr/lib/qt6/qml/Caelestia
# (plugin .so from one build, base lib from another). The symptom is a QML type
# from the C++ plugins suddenly being "not a type" (e.g. `ButtonRow is not a
# type`) even though nothing in the QML changed.
#
# The reliable workflow — and the one the project's own CI uses — is to run the
# shell straight from the repo with the freshly-built plugins on the QML import
# path. No sudo, no system dirs, no conflict with the AUR package. See
# `docs/development.md`.
#
# Usage:
#   ./dev.sh build       Configure (if needed) + build the C++ plugins
#   ./dev.sh run         Build, then run the shell from THIS repo (dev loop)
#   ./dev.sh lint        Run the project's qmlformat / clang-format / qmllint
#   ./dev.sh install     Build, then install to the system (forces a full,
#                        consistent copy — works around the timestamp skip)
#   ./dev.sh clean       Remove the build dir (do this after a Qt update)
#   ./dev.sh all         clean + build + lint
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
SYSTEM_QML_DIR="/usr/lib/qt6/qml/Caelestia"
QT_BIN="${QT_BIN:-/usr/lib/qt6/bin}"

# Prefer `qs`, fall back to `quickshell`.
QS_BIN="$(command -v qs || command -v quickshell || true)"

log() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

configure() {
    # Reconfigure every time: it is cheap and, crucially, picks up a system Qt
    # update so we never build against stale Qt headers.
    log "Configuring (cmake)…"
    cmake -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/
}

build() {
    configure
    log "Building…"
    cmake --build "$BUILD_DIR"
}

run() {
    build
    [ -n "$QS_BIN" ] || die "quickshell (qs) not found in PATH"
    log "Running shell from repo (Ctrl-C to stop)…"
    # Run OUR shell.qml with OUR freshly-built plugins — never the system copy.
    QML2_IMPORT_PATH="$BUILD_DIR/qml:${QML2_IMPORT_PATH:-}" \
        QML_IMPORT_PATH="$BUILD_DIR/qml:${QML_IMPORT_PATH:-}" \
        "$QS_BIN" -p "$REPO_DIR"
}

lint() {
    build
    local rc=0

    log "qmlformat (idempotency check)…"
    while IFS= read -r -d '' f; do
        if ! "$QT_BIN/qmlformat" "$f" | diff -u "$f" - >/dev/null; then
            printf '  not formatted: %s\n' "$f"; rc=1
        fi
    done < <(find "$REPO_DIR" -name '*.qml' -not -path '*/build/*' -print0)

    log "clang-format (C++)…"
    while IFS= read -r -d '' f; do
        if ! clang-format --dry-run --Werror "$f" 2>/dev/null; then rc=1; fi
    done < <(find "$REPO_DIR/plugin" \( -name '*.cpp' -o -name '*.hpp' \) -print0)

    log "qmllint…"
    # Generate .qmlls.ini (buildDir + importPaths) by running the shell briefly,
    # exactly like the CI does, then lint with those import paths.
    : > "$REPO_DIR/.qmlls.ini"
    QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$BUILD_DIR/qml:${QML2_IMPORT_PATH:-}" \
        timeout 5 "$QS_BIN" -p "$REPO_DIR" >/dev/null 2>&1 || true
    local build_subdir
    build_subdir="$(grep -oP '(?<=buildDir=")(.*)(?=")' "$REPO_DIR/.qmlls.ini" || true)"
    local args=()
    [ -n "$build_subdir" ] && args+=(-I "$build_subdir")
    while IFS= read -r p; do [ -n "$p" ] && args+=(-I "$p"); done \
        < <(grep -oP '(?<=importPaths=")(.*)(?=")' "$REPO_DIR/.qmlls.ini" | tr ':' '\n')
    # Lint everything except build/ and the legacy controlcenter dir (as CI does).
    local qml_files=()
    while IFS= read -r -d '' f; do qml_files+=("$f"); done \
        < <(find "$REPO_DIR" -name '*.qml' -not -path '*/build/*' \
                 -not -path '*/modules/controlcenter/*' -print0)
    "$QT_BIN/qmllint" --import disable "${args[@]}" "${qml_files[@]}" || rc=1
    rm -f "$REPO_DIR/.qmlls.ini"

    [ "$rc" -eq 0 ] && log "Lint clean." || die "Lint/format issues above."
}

install() {
    build
    log "Forcing fresh mtimes on build artifacts (defeats CMake's timestamp skip)…"
    # Without this, CMake may report 'Up-to-date' and leave a mismatched plugin
    # set on the system. Touching guarantees every file is copied.
    find "$BUILD_DIR" -type f -exec touch {} +
    log "Installing to system (sudo)… this overwrites $SYSTEM_QML_DIR"
    sudo cmake --install "$BUILD_DIR"
    log "Installed. Restart with: caelestia shell -d"
}

clean() {
    log "Removing $BUILD_DIR…"
    rm -rf "$BUILD_DIR"
}

case "${1:-run}" in
    build)   build ;;
    run)     run ;;
    lint)    lint ;;
    install) install ;;
    clean)   clean ;;
    all)     clean; build; lint ;;
    *)       die "unknown command '${1:-}'. Use: build | run | lint | install | clean | all" ;;
esac
