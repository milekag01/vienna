#!/usr/bin/env bash
# vienna destroy — tear down an instance completely

source "$VIENNA_DIR/lib/ports.sh"
source "$VIENNA_DIR/lib/infra.sh"
source "$VIENNA_DIR/lib/worktree.sh"
source "$VIENNA_DIR/lib/context.sh"

cmd_destroy() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Instance name is required"
        echo "Usage: vienna destroy <name>"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    # Check if the instance exists in any form (registry, config file, or worktree dir)
    local found=false
    init_registry
    local in_registry
    in_registry=$(jq -r --arg n "$name" '.instances[$n] // empty' "$REGISTRY_FILE" 2>/dev/null)
    [[ -n "$in_registry" ]] && found=true
    [[ -d "$VIENNA_INSTANCES/$name" ]] && found=true
    instance_exists "$name" && found=true

    if [[ "$found" == "false" ]]; then
        log_error "Instance '$name' not found"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    echo ""
    log_info "Destroying instance ${BOLD}$name${NC}..."
    echo ""

    # Step 1: Stop and remove Docker containers + volumes
    log_info "Removing infrastructure..."
    infra_destroy "$name" 2>/dev/null || log_warn "Docker cleanup had warnings (may already be stopped)"
    echo ""

    # Step 2: Remove git worktrees
    log_info "Removing worktrees..."
    worktrees_remove "$name"
    echo ""

    # Step 3: Free port allocation
    log_info "Freeing ports..."
    free_ports "$name"
    log_step "Ports released"

    # Step 4: Remove instance state
    local instance_config_dir="$VIENNA_STATE/instances/$name"
    if [[ -d "$instance_config_dir" ]]; then
        rm -rf "$instance_config_dir"
    fi

    # Step 5: Clear current if this was the active instance
    if [[ -f "$VIENNA_STATE/current" ]]; then
        local current
        current=$(cat "$VIENNA_STATE/current")
        if [[ "$current" == "$name" ]]; then
            rm -f "$VIENNA_STATE/current"
        fi
    fi

    echo ""
    log_success "Instance ${BOLD}$name${NC} destroyed."
}
