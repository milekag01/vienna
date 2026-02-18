#!/usr/bin/env bash
set -euo pipefail

# Resolve the real location of this script (follows symlinks)
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
VIENNA_DIR="$(cd "$SCRIPT_PATH/.." && pwd)"

# The workspace root is where the repos live (parent of vienna/)
# If invoked from a worktree instance, we still need the original workspace root
if [[ -f "$VIENNA_DIR/../commenda-logical-backend/package.json" ]]; then
    VIENNA_WORKSPACE="$(cd "$VIENNA_DIR/.." && pwd)"
elif [[ -n "${VIENNA_WORKSPACE:-}" ]]; then
    : # Already set via env
else
    echo "Error: Cannot determine workspace root. Expected vienna/ to be inside the workspace."
    exit 1
fi

export VIENNA_DIR
export VIENNA_WORKSPACE
export VIENNA_STATE="$VIENNA_WORKSPACE/.vienna-state"
export VIENNA_INSTANCES="$VIENNA_WORKSPACE/instances"

source "$VIENNA_DIR/lib/config.sh"
source "$VIENNA_DIR/lib/utils.sh"

command="${1:-help}"
shift || true

case "$command" in
    spawn)
        source "$VIENNA_DIR/lib/spawn.sh"
        cmd_spawn "$@"
        ;;
    destroy)
        source "$VIENNA_DIR/lib/destroy.sh"
        cmd_destroy "$@"
        ;;
    stop)
        source "$VIENNA_DIR/lib/stop.sh"
        cmd_stop "$@"
        ;;
    start)
        source "$VIENNA_DIR/lib/start.sh"
        cmd_start "$@"
        ;;
    list|ls)
        source "$VIENNA_DIR/lib/list.sh"
        cmd_list "$@"
        ;;
    run)
        source "$VIENNA_DIR/lib/run.sh"
        cmd_run "$@"
        ;;
    info)
        source "$VIENNA_DIR/lib/info.sh"
        cmd_info "$@"
        ;;
    help|--help|-h)
        echo ""
        log_info "Vienna — Branch-Aware Development Environment Manager"
        echo ""
        echo "Usage: vienna <command> [options]"
        echo ""
        echo "Commands:"
        echo "  spawn <name> --branch <branch>   Create isolated environment with worktrees"
        echo "  spawn --ticket <ID-or-URL>       Spawn from Linear ticket (fetches context, opens Cursor agent)"
        echo "  destroy <name>                    Tear down an instance completely"
        echo "  stop <name>                       Pause infrastructure (preserves data)"
        echo "  start <name>                      Resume a stopped instance"
        echo "  run <name> [app ...]              Start apps in new terminal tabs"
        echo "  info [name]                       Show ports, DB URLs, and connection details"
        echo "  list                              Show all instances"
        echo ""
        echo "Examples:"
        echo "  vienna spawn my-feature --branch feature-auth"
        echo "  vienna spawn --ticket COM-4521"
        echo "  vienna spawn --ticket https://linear.app/commenda/issue/COM-4521/some-title"
        echo "  vienna run my-feature                    # Start all apps"
        echo "  vienna run my-feature clb salestax       # Start specific apps"
        echo "  vienna stop my-feature"
        echo "  vienna start my-feature"
        echo "  vienna list"
        echo "  vienna destroy my-feature"
        echo ""
        ;;
    *)
        log_error "Unknown command: $command"
        echo "Run 'vienna help' for usage."
        exit 1
        ;;
esac
