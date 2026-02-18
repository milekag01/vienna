#!/usr/bin/env bash
# vienna info — show ports, database URLs, and connection details for an instance

source "$VIENNA_DIR/lib/context.sh"
source "$VIENNA_DIR/lib/config.sh"

cmd_info() {
    local name="${1:-}"

    if [[ "$name" == "--help" ]] || [[ "$name" == "-h" ]]; then
        echo "Usage: vienna info [name]"
        echo ""
        echo "Shows ports, database URLs, and connection details for an instance."
        echo "If no name is given, auto-detects from the current directory."
        return 0
    fi

    if [[ -z "$name" ]]; then
        name=$(detect_instance 2>/dev/null) || true
    fi

    if [[ -z "$name" ]]; then
        log_error "Instance name is required (or cd into an instance directory)"
        echo "Usage: vienna info [name]"
        return 1
    fi

    if ! instance_exists "$name"; then
        log_error "Instance '$name' not found"
        echo "Run 'vienna list' to see all instances."
        return 1
    fi

    ensure_jq

    local config_file="$VIENNA_STATE/instances/$name/config.json"
    local branch mode offset created
    branch=$(jq -r '.branch // "-"' "$config_file")
    mode=$(jq -r '.mode // "-"' "$config_file")
    offset=$(jq -r '.offset // "-"' "$config_file")
    created=$(jq -r '.created // "-"' "$config_file")

    local pg_nestjs pg_go redis localstack nestjs go_api enterprise
    pg_nestjs=$(jq -r '.ports.pg_nestjs' "$config_file")
    pg_go=$(jq -r '.ports.pg_go' "$config_file")
    redis=$(jq -r '.ports.redis' "$config_file")
    localstack=$(jq -r '.ports.localstack' "$config_file")
    nestjs=$(jq -r '.ports.nestjs' "$config_file")
    go_api=$(jq -r '.ports.go_api' "$config_file")
    enterprise=$(jq -r '.ports.enterprise // "-"' "$config_file")

    local sname
    sname=$(echo "${name//-/_}")
    local db_nestjs="${sname}_commenda"
    local db_go="${sname}_salestax"

    echo ""
    log_info "Instance: ${BOLD}$name${NC}"
    echo ""
    echo "  Branch:     $branch"
    echo "  Mode:       $mode"
    echo "  Created:    $created"
    echo "  Location:   $VIENNA_INSTANCES/$name/"
    echo ""

    echo -e "  ${BOLD}Ports${NC}"
    echo "  ─────────────────────────────────────"
    printf "  %-22s %s\n" "PostgreSQL (CLB):" "$pg_nestjs"
    printf "  %-22s %s\n" "PostgreSQL (Sales Tax):" "$pg_go"
    printf "  %-22s %s\n" "Redis:" "$redis"
    printf "  %-22s %s\n" "LocalStack:" "$localstack"
    printf "  %-22s %s\n" "CLB (NestJS):" "$nestjs"
    printf "  %-22s %s\n" "Sales Tax (Go):" "$go_api"
    printf "  %-22s %s\n" "Enterprise:" "$enterprise"
    echo ""

    echo -e "  ${BOLD}Database URLs${NC}"
    echo "  ─────────────────────────────────────"
    echo "  CLB (Prisma):"
    echo "    postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs}/${db_nestjs}"
    echo ""
    echo "  Sales Tax (Go):"
    echo "    postgres://${VIENNA_PG_GO_USER}:${VIENNA_PG_GO_PASS}@localhost:${pg_go}/${db_go}?sslmode=disable"
    echo ""

    echo -e "  ${BOLD}Redis${NC}"
    echo "  ─────────────────────────────────────"
    echo "    redis://localhost:${redis}"
    echo ""

    echo -e "  ${BOLD}LocalStack${NC}"
    echo "  ─────────────────────────────────────"
    echo "    http://localhost:${localstack}"
    echo ""

    echo -e "  ${BOLD}Backend URLs${NC}"
    echo "  ─────────────────────────────────────"
    echo "  CLB API:        http://localhost:${nestjs}/api/v1"
    echo "  Sales Tax API:  http://localhost:${go_api}/api/v1"
    if [[ "$enterprise" != "-" ]]; then
        echo "  Enterprise:     http://localhost:${enterprise}"
    fi
    echo ""

    echo -e "  ${BOLD}psql commands${NC}"
    echo "  ─────────────────────────────────────"
    echo "  CLB:       PGPASSWORD=${VIENNA_PG_NESTJS_PASS} psql -h localhost -p ${pg_nestjs} -U ${VIENNA_PG_NESTJS_USER} -d ${db_nestjs}"
    echo "  Sales Tax: PGPASSWORD=${VIENNA_PG_GO_PASS} psql -h localhost -p ${pg_go} -U ${VIENNA_PG_GO_USER} -d ${db_go}"
    echo ""
}
