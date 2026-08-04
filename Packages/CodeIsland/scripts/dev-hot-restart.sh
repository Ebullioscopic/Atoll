#!/usr/bin/env bash
set -euo pipefail

# Hot-restart dev loop for CodeIsland:
# - Watches source changes
# - Builds once per change batch
# - Restarts app only after successful build
# - Keeps current app process running if build fails
#
# Examples:
#   scripts/dev-hot-restart.sh --debounce 1.0 --paths "Sources,Tests,Package.swift"
#   scripts/dev-hot-restart.sh --build-cmd "swift build"
#   scripts/dev-hot-restart.sh --with-tests
#   scripts/dev-hot-restart.sh --socket-path /tmp/codeisland-dev.sock

DEBOUNCE="0.8"
WATCH_PATHS="Sources,Tests,Package.swift"
APP_PATH=".build/debug/CodeIsland"
BUILD_CMD="swift build"
WITH_TESTS=0
SOCKET_PATH=""

print_usage() {
  cat <<'EOF'
Usage: scripts/dev-hot-restart.sh [options]

Watch source changes, build once per change batch, and restart CodeIsland app only when build succeeds.
If build fails, current app keeps running.

Examples:
  scripts/dev-hot-restart.sh --debounce 1.0 --paths "Sources,Tests,Package.swift"
  scripts/dev-hot-restart.sh --build-cmd "swift build"
  scripts/dev-hot-restart.sh --with-tests
  scripts/dev-hot-restart.sh --socket-path /tmp/codeisland-dev.sock

Options:
  --paths <csv>          Watch paths (default: Sources,Tests,Package.swift)
  --debounce <seconds>   Debounce window (default: 0.8)
  --app-path <path>      Executable path (default: .build/debug/CodeIsland)
  --build-cmd <command>  Build command (default: swift build)
  --with-tests           Run swift test after successful build before restart
  --socket-path <path>   Set CODEISLAND_SOCKET_PATH when launching app
  --help                 Show this help message
EOF
}

log() {
  printf '[dev-hot-restart] %s\n' "$*"
}

fail() {
  printf '[dev-hot-restart] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing command: $1"
  fi
}

resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$script_dir/.." && pwd)"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --paths)
        WATCH_PATHS="$2"
        shift 2
        ;;
      --debounce)
        DEBOUNCE="$2"
        shift 2
        ;;
      --app-path)
        APP_PATH="$2"
        shift 2
        ;;
      --build-cmd)
        BUILD_CMD="$2"
        shift 2
        ;;
      --with-tests)
        WITH_TESTS=1
        shift
        ;;
      --socket-path)
        SOCKET_PATH="$2"
        shift 2
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

quit_app() {
  local existing_pids
  existing_pids="$(pgrep -x "CodeIsland" || true)"
  [[ -z "$existing_pids" ]] && return 0

  log "Stopping existing CodeIsland process(es): $existing_pids"
  local pid
  for pid in $existing_pids; do
    kill -TERM "$pid" >/dev/null 2>&1 || true
  done

  local deadline all_gone
  deadline=$((SECONDS + 2))
  while ((SECONDS < deadline)); do
    all_gone=1
    for pid in $existing_pids; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        all_gone=0
        break
      fi
    done
    ((all_gone == 1)) && return 0
    sleep 0.1
  done

  log "SIGTERM did not stop app within 2s; escalating to SIGKILL"
  for pid in $existing_pids; do
    kill -KILL "$pid" >/dev/null 2>&1 || true
  done

  deadline=$((SECONDS + 2))
  while ((SECONDS < deadline)); do
    all_gone=1
    for pid in $existing_pids; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        all_gone=0
        break
      fi
    done
    ((all_gone == 1)) && return 0
    sleep 0.1
  done

  fail "Existing CodeIsland process(es) still alive after SIGKILL; aborting restart"
}

launch_app() {
  if [[ "$APP_PATH" != *.app/Contents/MacOS/* ]]; then
    log "NOTE: launching a bare executable; Buddy Bluetooth requires a signed .app bundle with Bluetooth entitlements"
  fi
  if [[ -n "$SOCKET_PATH" ]]; then
    log "Launching app with CODEISLAND_SOCKET_PATH=$SOCKET_PATH"
    CODEISLAND_SOCKET_PATH="$SOCKET_PATH" "$APP_PATH" &
  else
    log "Launching app: $APP_PATH"
    "$APP_PATH" &
  fi
}

run_build_pipeline() {
  log "Building: $BUILD_CMD"
  # shellcheck disable=SC2206
  local build_cmd_parts=( $BUILD_CMD )
  if ((${#build_cmd_parts[@]} == 0)); then
    return 1
  fi
  if ! "${build_cmd_parts[@]}"; then
    return 1
  fi

  if ((WITH_TESTS == 1)); then
    log "Running tests: swift test"
    swift test
  fi
}

collect_watch_args() {
  IFS=',' read -r -a WATCH_ARRAY <<<"$WATCH_PATHS"
  WATCH_ARGS=()
  for raw in "${WATCH_ARRAY[@]}"; do
    local trimmed
    trimmed="${raw## }"
    trimmed="${trimmed%% }"
    [[ -z "$trimmed" ]] && continue

    local full_path="$REPO_ROOT/$trimmed"
    if [[ -e "$full_path" ]]; then
      WATCH_ARGS+=("$full_path")
    else
      log "Skip missing watch path: $trimmed"
    fi
  done

  if ((${#WATCH_ARGS[@]} == 0)); then
    fail "No valid watch paths left. Use --paths to configure existing paths."
  fi
}

wait_for_quiet_window() {
  while true; do
    local before after
    before=$(wc -c <"$EVENT_FILE")
    sleep "$DEBOUNCE"
    after=$(wc -c <"$EVENT_FILE")
    if [[ "$before" == "$after" ]]; then
      return
    fi
  done
}

cleanup() {
  if [[ -n "${WATCHER_PID:-}" ]]; then
    kill "$WATCHER_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$EVENT_FILE"
}

main() {
  parse_args "$@"
  resolve_repo_root

  cd "$REPO_ROOT"

  require_command fswatch
  require_command swift
  require_command pgrep

  if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$REPO_ROOT/${APP_PATH#./}"
  fi
  [[ -x "$APP_PATH" ]] || fail "App executable not found: $APP_PATH (run swift build first)"

  collect_watch_args

  EVENT_FILE="$(mktemp -t codeisland-hot-restart-events)"
  trap cleanup EXIT INT TERM

  log "Watching paths: ${WATCH_ARGS[*]}"
  log "Debounce: ${DEBOUNCE}s"
  log "Build command: $BUILD_CMD"
  ((WITH_TESTS == 1)) && log "Test gate enabled"

  fswatch -0 --event Created --event Updated --event Removed --event Renamed "${WATCH_ARGS[@]}" | while IFS= read -r -d '' _event; do
    printf '.' >>"$EVENT_FILE"
  done &
  WATCHER_PID=$!

  local seen latest_before_build latest_after_build
  seen=$(wc -c <"$EVENT_FILE")

  while true; do
    latest_before_build=$(wc -c <"$EVENT_FILE")
    if [[ "$latest_before_build" == "$seen" ]]; then
      sleep 0.2
      continue
    fi

    wait_for_quiet_window
    latest_before_build=$(wc -c <"$EVENT_FILE")

    if run_build_pipeline; then
      log "Build succeeded"
      quit_app
      launch_app
      log "Restart complete"
    else
      log "Build failed; keeping current app instance running"
    fi

    latest_after_build=$(wc -c <"$EVENT_FILE")
    if [[ "$latest_after_build" != "$latest_before_build" ]]; then
      log "Detected new changes during build/restart; running next build cycle"
      continue
    fi

    seen="$latest_after_build"
  done
}

main "$@"
