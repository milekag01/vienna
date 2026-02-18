#!/usr/bin/env bash
# vienna run — start app services in new terminal tabs
#
# Usage:
#   vienna run <name>                      Start all three apps (clb, salestax, enterprise)
#   vienna run <name> clb                  Start only the NestJS backend
#   vienna run <name> salestax enterprise  Start the Go API and enterprise frontend

source "$VIENNA_DIR/lib/context.sh"
source "$VIENNA_DIR/lib/config.sh"

ALL_APPS=("clb" "salestax" "enterprise")

_resolve_app_command() {
    local app="$1"
    local instance_dir="$2"
    local config_file="$3"

    local nestjs_port go_api_port enterprise_port
    nestjs_port=$(jq -r '.ports.nestjs' "$config_file")
    go_api_port=$(jq -r '.ports.go_api' "$config_file")
    enterprise_port=$(jq -r '.ports.enterprise' "$config_file")

    case "$app" in
        clb|nestjs|backend)
            echo "cd '$instance_dir/commenda-logical-backend' && npm run start:dev"
            ;;
        salestax|sales-tax|go|tax-api)
            echo "cd '$instance_dir/sales-tax-api-2' && air"
            ;;
        enterprise|ent|frontend)
            echo "cd '$instance_dir/commenda/apps/enterprise' && pnpm dev -p $enterprise_port"
            ;;
        *)
            return 1
            ;;
    esac
}

_app_label() {
    case "$1" in
        clb|nestjs|backend)            echo "CLB" ;;
        salestax|sales-tax|go|tax-api) echo "Sales Tax" ;;
        enterprise|ent|frontend)       echo "Enterprise" ;;
        *)                             echo "$1" ;;
    esac
}

# Open a new terminal and run a command.
# Detects Cursor/VS Code, iTerm2, and Terminal.app.
_open_tab() {
    local title="$1"
    local cmd="$2"

    if [[ "$(uname)" != "Darwin" ]]; then
        log_step "Starting $title in background..."
        bash -c "$cmd" &
        return
    fi

    local term_program="${TERM_PROGRAM:-}"

    case "$term_program" in
        vscode)
            _open_cursor_tab "$title" "$cmd"
            ;;
        iTerm.app|iTerm2)
            _open_iterm_tab "$title" "$cmd"
            ;;
        *)
            # From Cursor shell or unknown — check what's running
            if [[ -z "$term_program" ]] && pgrep -xq "Cursor" 2>/dev/null; then
                _open_cursor_tab "$title" "$cmd"
            elif pgrep -xq iTerm2 2>/dev/null; then
                _open_iterm_tab "$title" "$cmd"
            else
                _open_terminal_tab "$title" "$cmd"
            fi
            ;;
    esac
}

_open_cursor_tab() {
    local title="$1"
    local cmd="$2"

    # Place the command on the clipboard so we can paste it reliably
    # (keystroke is fragile with special characters in long commands)
    printf '%s' "$cmd" | pbcopy

    osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "Cursor"
        set frontmost to true
        delay 0.3
        -- Ctrl+Shift+` → Create New Terminal in Cursor/VS Code
        key code 50 using {control down, shift down}
        delay 1.0
        -- Cmd+V → Paste the command from clipboard
        keystroke "v" using {command down}
        delay 0.2
        -- Press Enter to run
        key code 36
    end tell
end tell
APPLESCRIPT
}

_open_iterm_tab() {
    local title="$1"
    local cmd="$2"
    osascript <<APPLESCRIPT
tell application "iTerm2"
    tell current window
        create tab with default profile
        tell current session
            set name to "$title"
            write text "$cmd"
        end tell
    end tell
end tell
APPLESCRIPT
}

_open_terminal_tab() {
    local title="$1"
    local cmd="$2"
    osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "$cmd"
    set custom title of front window to "$title"
end tell
APPLESCRIPT
}

cmd_run() {
    local name=""
    local apps=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                echo "Usage: vienna run <name> [app ...]"
                echo ""
                echo "Starts app services in new terminal tabs."
                echo "If no apps are specified, starts all three."
                echo ""
                echo "Apps:"
                echo "  clb         Commenda Logical Backend (npm run start:dev)"
                echo "  salestax    Sales Tax API (air)"
                echo "  enterprise  Enterprise frontend (pnpm dev)"
                echo ""
                echo "Examples:"
                echo "  vienna run my-feature                    # Start all apps"
                echo "  vienna run my-feature clb salestax       # Start only backend services"
                echo "  vienna run my-feature enterprise         # Start only the frontend"
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                else
                    apps+=("$1")
                fi
                shift
                ;;
        esac
    done

    # If no name given, try to detect from cwd
    if [[ -z "$name" ]]; then
        name=$(detect_instance 2>/dev/null) || true
    fi

    if [[ -z "$name" ]]; then
        log_error "Instance name is required (or cd into an instance directory)"
        echo "Usage: vienna run <name> [app ...]"
        return 1
    fi

    if ! instance_exists "$name"; then
        log_error "Instance '$name' not found"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    # Default to all apps if none specified
    if [[ ${#apps[@]} -eq 0 ]]; then
        apps=("${ALL_APPS[@]}")
    fi

    local config_file="$VIENNA_STATE/instances/$name/config.json"
    local instance_dir="$VIENNA_INSTANCES/$name"

    # Validate all app names before opening any tabs
    for app in "${apps[@]}"; do
        if ! _resolve_app_command "$app" "$instance_dir" "$config_file" >/dev/null 2>&1; then
            log_error "Unknown app: $app"
            echo "Valid apps: clb, salestax, enterprise"
            return 1
        fi
    done

    # Save clipboard before we start (Cursor mode uses pbcopy/pbpaste)
    local _saved_clipboard=""
    _saved_clipboard=$(pbpaste 2>/dev/null) || true

    echo ""
    log_info "Starting ${#apps[@]} app(s) for instance ${BOLD}$name${NC}..."
    echo ""

    for app in "${apps[@]}"; do
        local label
        label=$(_app_label "$app")
        local cmd
        cmd=$(_resolve_app_command "$app" "$instance_dir" "$config_file")

        log_step "Opening tab: $label"
        _open_tab "vienna: $name — $label" "$cmd"
        sleep 0.5
    done

    # Restore clipboard
    printf '%s' "$_saved_clipboard" | pbcopy 2>/dev/null || true

    echo ""
    log_success "All apps launched. Check your terminal tabs."
    echo ""
}
