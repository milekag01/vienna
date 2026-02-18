#!/usr/bin/env bash
# Instance context detection — determines which instance the user is in

# Detection order:
# 1. VIENNA_INSTANCE env var (explicit override)
# 2. Walk up from cwd looking for .vienna-instance.json (spawned instance)
# 3. Read .vienna-state/current (switched instance)
# 4. Error

detect_instance() {
    # 1. Explicit env var
    if [[ -n "${VIENNA_INSTANCE:-}" ]]; then
        echo "$VIENNA_INSTANCE"
        return 0
    fi

    # 2. Walk up from cwd looking for marker file
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.vienna-instance.json" ]]; then
            jq -r '.name' "$dir/.vienna-instance.json"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # 3. Read current file
    if [[ -f "$VIENNA_STATE/current" ]]; then
        cat "$VIENNA_STATE/current"
        return 0
    fi

    return 1
}

# Get instance config as JSON
get_instance_config() {
    local name="$1"
    local config_file="$VIENNA_STATE/instances/$name/config.json"
    if [[ -f "$config_file" ]]; then
        cat "$config_file"
        return 0
    fi
    return 1
}

# Check if an instance exists
instance_exists() {
    local name="$1"
    [[ -f "$VIENNA_STATE/instances/$name/config.json" ]]
}
