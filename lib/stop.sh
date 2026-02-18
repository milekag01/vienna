#!/usr/bin/env bash
# vienna stop — pause an instance's Docker infrastructure (preserves data)

source "$VIENNA_DIR/lib/infra.sh"
source "$VIENNA_DIR/lib/context.sh"

cmd_stop() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        name=$(detect_instance 2>/dev/null) || true
    fi

    if [[ -z "$name" ]]; then
        log_error "Instance name is required (or cd into an instance directory)"
        echo "Usage: vienna stop <name>"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    if ! instance_exists "$name"; then
        log_error "Instance '$name' not found"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    echo ""
    log_info "Stopping instance ${BOLD}$name${NC}..."
    infra_stop "$name"
    echo ""
    log_success "Instance ${BOLD}$name${NC} stopped. Data is preserved."
    echo "  Run 'vienna start $name' to resume."
    echo ""
}
