#!/usr/bin/env bash
# Migration runner — applies Prisma and Atlas migrations for an instance

source "$VIENNA_DIR/lib/config.sh"

# Run all migrations for an instance
# Args: instance_name, offset
migrate_all() {
    local name="$1"
    local offset="$2"
    local instance_dir="$VIENNA_INSTANCES/$name"

    local pg_nestjs_port=$((VIENNA_PORT_BASE_PG_NESTJS + offset))
    local pg_go_port=$((VIENNA_PORT_BASE_PG_GO + offset))

    log_info "Applying migrations..."

    # --- Prisma (NestJS backend) ---
    local clb_dir="$instance_dir/commenda-logical-backend"
    if [[ -d "$clb_dir/prisma" ]]; then
        log_step "Running Prisma migrations (commenda-logical-backend)..."
        (
            cd "$clb_dir"
            export DATABASE_URL="postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${VIENNA_PG_NESTJS_DB}"

            if [[ ! -d "node_modules/.prisma" ]]; then
                log_step "Installing prisma dependencies (this may take a minute on first run)..."
                npm install prisma @prisma/client --silent 2>&1 | tail -3
            fi

            npx prisma migrate deploy 2>&1 | while IFS= read -r line; do
                echo "    $line"
            done
        ) || true

        log_success "Prisma migrations step complete"
    else
        log_warn "No prisma/ directory found in commenda-logical-backend, skipping"
    fi

    # --- Atlas (Go service) ---
    local sta_dir="$instance_dir/sales-tax-api-2"
    if [[ -d "$sta_dir/database/migrations" ]]; then
        log_step "Running Atlas migrations (sales-tax-api-2)..."

        local go_db_url="postgres://${VIENNA_PG_GO_USER}:${VIENNA_PG_GO_PASS}@localhost:${pg_go_port}/${VIENNA_PG_GO_DB}?sslmode=disable"

        if command -v atlas &>/dev/null; then
            (
                cd "$sta_dir"
                atlas migrate apply \
                    --dir "file://database/migrations" \
                    --url "$go_db_url" 2>&1 | while IFS= read -r line; do
                    echo "    $line"
                done
            )
            log_success "Atlas migrations applied"
        else
            log_warn "atlas CLI not found — skipping Go service migrations"
            log_warn "Install: https://atlasgo.io/getting-started#installation"
        fi
    else
        log_warn "No database/migrations/ directory found in sales-tax-api-2, skipping"
    fi
}
