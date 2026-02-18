#!/usr/bin/env bash
# Port allocation registry — assigns unique ports per instance

source "$VIENNA_DIR/lib/config.sh"

REGISTRY_FILE="$VIENNA_STATE/registry.json"

init_registry() {
    ensure_dir "$VIENNA_STATE"
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo '{"next_offset": 1, "instances": {}, "freed_offsets": []}' > "$REGISTRY_FILE"
    fi
}

# Allocate ports for a new instance. Outputs the offset number.
allocate_ports() {
    local name="$1"
    ensure_jq
    init_registry

    # Check if already allocated
    local existing
    existing=$(jq -r --arg n "$name" '.instances[$n].offset // empty' "$REGISTRY_FILE")
    if [[ -n "$existing" ]]; then
        echo "$existing"
        return 0
    fi

    # Try to reuse a freed offset, otherwise take next_offset
    local offset
    local freed_count
    freed_count=$(jq '.freed_offsets | length' "$REGISTRY_FILE")

    if (( freed_count > 0 )); then
        offset=$(jq '.freed_offsets[0]' "$REGISTRY_FILE")
        # Remove from freed list
        jq '.freed_offsets = .freed_offsets[1:]' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" \
            && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    else
        offset=$(jq '.next_offset' "$REGISTRY_FILE")
        # Increment next_offset
        jq '.next_offset += 1' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" \
            && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    fi

    # Record the allocation
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg n "$name" --argjson o "$offset" --arg t "$now" \
        '.instances[$n] = {"offset": $o, "created": $t}' \
        "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" \
        && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"

    echo "$offset"
}

# Free ports for a destroyed instance
free_ports() {
    local name="$1"
    ensure_jq
    init_registry

    local offset
    offset=$(jq -r --arg n "$name" '.instances[$n].offset // empty' "$REGISTRY_FILE")
    if [[ -z "$offset" ]]; then
        return 0
    fi

    jq --arg n "$name" --argjson o "$offset" \
        'del(.instances[$n]) | .freed_offsets += [$o]' \
        "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" \
        && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
}

# Compute all ports for a given offset
compute_ports() {
    local offset="$1"
    echo "PG_NESTJS_PORT=$((VIENNA_PORT_BASE_PG_NESTJS + offset))"
    echo "PG_GO_PORT=$((VIENNA_PORT_BASE_PG_GO + offset))"
    echo "REDIS_PORT=$((VIENNA_PORT_BASE_REDIS + offset))"
    echo "LOCALSTACK_PORT=$((VIENNA_PORT_BASE_LOCALSTACK + offset))"
    echo "NESTJS_PORT=$((VIENNA_PORT_BASE_NESTJS + offset))"
    echo "GO_API_PORT=$((VIENNA_PORT_BASE_GO_API + offset))"
    echo "APP_POOL_START=$((VIENNA_PORT_BASE_APP_POOL + offset * VIENNA_APP_POOL_SIZE))"
    echo "APP_POOL_END=$((VIENNA_PORT_BASE_APP_POOL + offset * VIENNA_APP_POOL_SIZE + VIENNA_APP_POOL_SIZE - 1))"
}

# Get a specific port for an instance
get_port() {
    local name="$1" port_name="$2"
    ensure_jq
    local offset
    offset=$(jq -r --arg n "$name" '.instances[$n].offset // empty' "$REGISTRY_FILE")
    if [[ -z "$offset" ]]; then
        log_error "No port allocation found for instance: $name"
        return 1
    fi

    case "$port_name" in
        pg_nestjs)    echo $((VIENNA_PORT_BASE_PG_NESTJS + offset)) ;;
        pg_go)        echo $((VIENNA_PORT_BASE_PG_GO + offset)) ;;
        redis)        echo $((VIENNA_PORT_BASE_REDIS + offset)) ;;
        localstack)   echo $((VIENNA_PORT_BASE_LOCALSTACK + offset)) ;;
        nestjs)       echo $((VIENNA_PORT_BASE_NESTJS + offset)) ;;
        go_api)       echo $((VIENNA_PORT_BASE_GO_API + offset)) ;;
        *)            log_error "Unknown port name: $port_name"; return 1 ;;
    esac
}
