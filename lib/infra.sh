#!/usr/bin/env bash
# Docker infrastructure management — start, stop, destroy containers

source "$VIENNA_DIR/lib/config.sh"
source "$VIENNA_DIR/lib/ports.sh"

COMPOSE_FILE="$VIENNA_DIR/docker/docker-compose.base.yaml"

# Build the env vars needed by docker-compose for a given instance
_compose_env() {
    local name="$1"
    local offset
    offset=$(jq -r --arg n "$name" '.instances[$n].offset // empty' "$REGISTRY_FILE")

    export VIENNA_PG_NESTJS_PORT=$((VIENNA_PORT_BASE_PG_NESTJS + offset))
    export VIENNA_PG_GO_PORT=$((VIENNA_PORT_BASE_PG_GO + offset))
    export VIENNA_REDIS_PORT=$((VIENNA_PORT_BASE_REDIS + offset))
    export VIENNA_LOCALSTACK_PORT=$((VIENNA_PORT_BASE_LOCALSTACK + offset))
    export VIENNA_PG_NESTJS_USER VIENNA_PG_NESTJS_PASS VIENNA_PG_NESTJS_DB
    export VIENNA_PG_GO_USER VIENNA_PG_GO_PASS VIENNA_PG_GO_DB
    export VIENNA_POSTGRES_IMAGE VIENNA_REDIS_IMAGE VIENNA_LOCALSTACK_IMAGE
    export VIENNA_AWS_REGION
    export VIENNA_INIT_SCRIPT="$VIENNA_DIR/docker/init-localstack.sh"
}

# Run docker compose with the right project name and env
_compose() {
    local name="$1"
    shift
    _compose_env "$name"
    docker compose -p "vienna-${name}" -f "$COMPOSE_FILE" "$@"
}

# Start infrastructure for an instance
infra_up() {
    local name="$1"
    ensure_docker
    log_step "Starting Docker infrastructure for ${BOLD}$name${NC}..."
    _compose "$name" up -d --wait 2>&1 | while IFS= read -r line; do
        echo "    $line"
    done

    _compose_env "$name"
    log_success "Infrastructure ready:"
    log_step "PostgreSQL (NestJS): localhost:${VIENNA_PG_NESTJS_PORT}"
    log_step "PostgreSQL (Go):     localhost:${VIENNA_PG_GO_PORT}"
    log_step "Redis:               localhost:${VIENNA_REDIS_PORT}"
    log_step "LocalStack (AWS):    localhost:${VIENNA_LOCALSTACK_PORT}"
}

# Stop infrastructure (preserve data)
infra_stop() {
    local name="$1"
    log_step "Stopping containers for ${BOLD}$name${NC}..."
    _compose "$name" stop
}

# Start stopped infrastructure
infra_start() {
    local name="$1"
    ensure_docker
    log_step "Starting containers for ${BOLD}$name${NC}..."
    _compose "$name" start
}

# Destroy infrastructure completely (containers + volumes)
infra_destroy() {
    local name="$1"
    log_step "Destroying Docker infrastructure for ${BOLD}$name${NC}..."
    _compose "$name" down -v 2>&1 | while IFS= read -r line; do
        echo "    $line"
    done
}

# Check if infrastructure is running
infra_status() {
    local name="$1"
    _compose "$name" ps --format json 2>/dev/null
}
