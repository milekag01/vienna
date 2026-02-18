#!/usr/bin/env bash
# Shared utilities — colors, logging, helpers

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[vienna]${NC} $*"; }
log_success() { echo -e "${GREEN}[vienna]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[vienna]${NC} $*"; }
log_error()   { echo -e "${RED}[vienna]${NC} $*"; }
log_step()    { echo -e "${CYAN}  →${NC} $*"; }

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# Sanitize instance name for use in PG database names and SQS queue prefixes
# Replaces hyphens with underscores (PG doesn't like unquoted hyphens in identifiers)
safe_name() {
    echo "${1//-/_}"
}

ensure_jq() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed."
        echo "  Install: brew install jq"
        exit 1
    fi
}

ensure_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is required but not installed."
        exit 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
}

# Wait for a TCP port to accept connections
wait_for_port() {
    local host="$1" port="$2" timeout="${3:-30}" name="${4:-service}"
    local elapsed=0
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if (( elapsed >= timeout )); then
            log_error "Timed out waiting for $name on port $port"
            return 1
        fi
        sleep 1
        ((elapsed++))
    done
}
