#!/usr/bin/env bash
# Environment file generation — copies base .env and overrides infra-specific vars

source "$VIENNA_DIR/lib/config.sh"

# Override a var in an env file. If the var exists, replace it. If not, append it.
_env_set() {
    local file="$1" key="$2" value="$3"

    if grep -q "^${key}=" "$file" 2>/dev/null || grep -q "^${key} =" "$file" 2>/dev/null; then
        # Replace existing line (handles both KEY=val and KEY = val)
        sed -i '' "s|^${key}[[:space:]]*=.*|${key}=\"${value}\"|" "$file" 2>/dev/null || \
        sed -i "s|^${key}[[:space:]]*=.*|${key}=\"${value}\"|" "$file"
    else
        echo "${key}=\"${value}\"" >> "$file"
    fi
}

# Generate .env files for an instance
# Args: instance_name, offset
env_generate() {
    local name="$1"
    local offset="$2"
    local instance_dir="$VIENNA_INSTANCES/$name"

    local pg_nestjs_port=$((VIENNA_PORT_BASE_PG_NESTJS + offset))
    local pg_go_port=$((VIENNA_PORT_BASE_PG_GO + offset))
    local redis_port=$((VIENNA_PORT_BASE_REDIS + offset))
    local nestjs_port=$((VIENNA_PORT_BASE_NESTJS + offset))
    local go_api_port=$((VIENNA_PORT_BASE_GO_API + offset))

    # --- commenda-logical-backend ---
    local clb_dir="$instance_dir/commenda-logical-backend"
    if [[ -d "$clb_dir" ]]; then
        local clb_source="$VIENNA_WORKSPACE/commenda-logical-backend/.env"
        local clb_target="$clb_dir/.env"

        if [[ -f "$clb_source" ]]; then
            cp "$clb_source" "$clb_target"
        else
            touch "$clb_target"
        fi

        _env_set "$clb_target" "DATABASE_URL" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${VIENNA_PG_NESTJS_DB}"
        _env_set "$clb_target" "DATABASE_URL_REPLICA" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${VIENNA_PG_NESTJS_DB}"
        _env_set "$clb_target" "PROD_DATABASE_URL_REPLICA" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${VIENNA_PG_NESTJS_DB}"
        _env_set "$clb_target" "REDIS_CONNECTION_HOST" "localhost"
        _env_set "$clb_target" "REDIS_CONNECTION_PORT" "$redis_port"
        _env_set "$clb_target" "SALES_TAX_CLIENT_API_KEY" "$VIENNA_SALES_TAX_API_KEY"
        _env_set "$clb_target" "NODE_ENV" "development"

        log_step "Generated .env for commenda-logical-backend (PG:$pg_nestjs_port, Redis:$redis_port)"
    fi

    # --- sales-tax-api-2 ---
    local sta_dir="$instance_dir/sales-tax-api-2"
    if [[ -d "$sta_dir" ]]; then
        local sta_source="$VIENNA_WORKSPACE/sales-tax-api-2/.env"
        local sta_target="$sta_dir/.env"

        if [[ -f "$sta_source" ]]; then
            cp "$sta_source" "$sta_target"
        else
            touch "$sta_target"
        fi

        _env_set "$sta_target" "DATABASE_URL" \
            "postgres://${VIENNA_PG_GO_USER}:${VIENNA_PG_GO_PASS}@localhost:${pg_go_port}/${VIENNA_PG_GO_DB}?sslmode=disable"
        _env_set "$sta_target" "RDS_HOSTNAME" "localhost"
        _env_set "$sta_target" "RDS_PORT" "$pg_go_port"
        _env_set "$sta_target" "RDS_DBNAME" "$VIENNA_PG_GO_DB"
        _env_set "$sta_target" "RDS_USERNAME" "$VIENNA_PG_GO_USER"
        _env_set "$sta_target" "RDS_PASSWORD" "$VIENNA_PG_GO_PASS"
        _env_set "$sta_target" "PORT" "$go_api_port"
        _env_set "$sta_target" "COMMENDA_LOGICAL_BACKEND_URL" "http://localhost:${nestjs_port}/api/v1"
        _env_set "$sta_target" "COMMENDA_FRONTEND_URL" "http://localhost:3000"
        _env_set "$sta_target" "SALES_TAX_CLIENT_API_KEY" "$VIENNA_SALES_TAX_API_KEY"
        _env_set "$sta_target" "ENVIRONMENT" "DEVELOPMENT"

        log_step "Generated .env for sales-tax-api-2 (PG:$pg_go_port, API:$go_api_port)"
    fi

    # --- commenda (Prisma package) ---
    local prisma_dir="$instance_dir/commenda/packages/prisma"
    if [[ -d "$prisma_dir" ]]; then
        local prisma_target="$prisma_dir/.env"
        echo "DATABASE_URL=\"postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${VIENNA_PG_NESTJS_DB}\"" > "$prisma_target"
        log_step "Generated .env for commenda/packages/prisma (PG:$pg_nestjs_port)"
    fi
}
