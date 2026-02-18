#!/usr/bin/env bash
# vienna list — show all instances with status

source "$VIENNA_DIR/lib/ports.sh"
source "$VIENNA_DIR/lib/context.sh"
source "$VIENNA_DIR/lib/config.sh"

cmd_list() {
    ensure_jq
    init_registry

    local instances
    instances=$(jq -r '.instances | keys[]' "$REGISTRY_FILE" 2>/dev/null)

    if [[ -z "$instances" ]]; then
        echo ""
        log_info "No instances found."
        echo "  Run 'vienna spawn <name> --branch <branch>' to create one."
        echo ""
        return 0
    fi

    echo ""
    printf "  ${BOLD}%-18s %-18s %-10s %-7s %-7s %-7s %-5s %-7s %-7s %-6s${NC}\n" \
        "INSTANCE" "BRANCH" "STATUS" "PG-NJS" "PG-GO" "REDIS" "AWS" "NESTJS" "GO-API" "ENT"
    printf "  %-18s %-18s %-10s %-7s %-7s %-7s %-5s %-7s %-7s %-6s\n" \
        "--------" "------" "------" "------" "-----" "-----" "---" "------" "------" "---"

    while IFS= read -r name; do
        local config_file="$VIENNA_STATE/instances/$name/config.json"
        local branch="-"
        local status="unknown"
        local pg_nestjs="-"
        local pg_go="-"
        local redis="-"
        local localstack="-"
        local nestjs="-"
        local go_api="-"
        local enterprise="-"

        if [[ -f "$config_file" ]]; then
            branch=$(jq -r '.branch // "-"' "$config_file")
            pg_nestjs=$(jq -r '.ports.pg_nestjs // "-"' "$config_file")
            pg_go=$(jq -r '.ports.pg_go // "-"' "$config_file")
            redis=$(jq -r '.ports.redis // "-"' "$config_file")
            localstack=$(jq -r '.ports.localstack // "-"' "$config_file")
            nestjs=$(jq -r '.ports.nestjs // "-"' "$config_file")
            go_api=$(jq -r '.ports.go_api // "-"' "$config_file")
            enterprise=$(jq -r '.ports.enterprise // "-"' "$config_file")
        fi

        # Check Docker status
        if docker compose -p "vienna-${name}" ps --format json 2>/dev/null | grep -q '"running"' 2>/dev/null; then
            status="${GREEN}running${NC}"
        elif docker compose -p "vienna-${name}" ps --format json 2>/dev/null | grep -q '"exited"' 2>/dev/null; then
            status="${YELLOW}stopped${NC}"
        else
            status="${DIM}down${NC}"
        fi

        printf "  %-18s %-18s %-10b %-7s %-7s %-7s %-5s %-7s %-7s %-6s\n" \
            "$name" "$branch" "$status" "$pg_nestjs" "$pg_go" "$redis" "$localstack" "$nestjs" "$go_api" "$enterprise"

    done <<< "$instances"

    echo ""
}
