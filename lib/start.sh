#!/usr/bin/env bash
# vienna start — resume a stopped instance's Docker infrastructure

source "$VIENNA_DIR/lib/infra.sh"
source "$VIENNA_DIR/lib/context.sh"

cmd_start() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        name=$(detect_instance 2>/dev/null) || true
    fi

    if [[ -z "$name" ]]; then
        log_error "Instance name is required (or cd into an instance directory)"
        echo "Usage: vienna start <name>"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    if ! instance_exists "$name"; then
        log_error "Instance '$name' not found"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    echo ""
    log_info "Starting instance ${BOLD}$name${NC}..."
    infra_start "$name"
    echo ""

    local config_file="$VIENNA_STATE/instances/$name/config.json"
    if [[ -f "$config_file" ]]; then
        local pg_nestjs pg_go redis localstack
        pg_nestjs=$(jq -r '.ports.pg_nestjs' "$config_file")
        pg_go=$(jq -r '.ports.pg_go' "$config_file")
        redis=$(jq -r '.ports.redis' "$config_file")
        localstack=$(jq -r '.ports.localstack' "$config_file")

        log_success "Instance ${BOLD}$name${NC} is running."
        echo ""
        echo "  PostgreSQL (NestJS): localhost:$pg_nestjs"
        echo "  PostgreSQL (Go):     localhost:$pg_go"
        echo "  Redis:               localhost:$redis"
        echo "  LocalStack (AWS):    localhost:$localstack"
        echo ""
    else
        log_success "Instance ${BOLD}$name${NC} started."
    fi
}
