#!/usr/bin/env bash
# Dependency installation — npm, pnpm, prisma generate, go modules

source "$VIENNA_DIR/lib/config.sh"

install_deps() {
    local name="$1"
    local instance_dir="$VIENNA_INSTANCES/$name"

    log_info "Installing dependencies..."

    # --- commenda-logical-backend (npm) ---
    local clb_dir="$instance_dir/commenda-logical-backend"
    if [[ -d "$clb_dir" ]] && [[ -f "$clb_dir/package.json" ]]; then
        log_step "Installing commenda-logical-backend dependencies (npm install)..."
        (
            cd "$clb_dir"
            npm install 2>&1 | tail -5
        ) || log_warn "npm install had issues for commenda-logical-backend (non-fatal)"
        log_success "commenda-logical-backend dependencies installed"
    fi

    # --- commenda monorepo (pnpm install + prisma generate) ---
    # pnpm install must run from the workspace root so all workspace deps resolve.
    # prisma generate must also run from root so the generated .prisma/client
    # lands inside pnpm's store next to @prisma/client.
    local commenda_dir="$instance_dir/commenda"
    if [[ -d "$commenda_dir" ]] && [[ -f "$commenda_dir/package.json" ]]; then
        if ! command -v pnpm &>/dev/null; then
            log_warn "pnpm not found — skipping commenda dependency install"
            log_warn "Install: npm install -g pnpm"
        else
            log_step "Installing commenda dependencies (pnpm install)..."
            (
                cd "$commenda_dir"
                pnpm install 2>&1 | tail -10
            ) || log_warn "pnpm install had issues for commenda (non-fatal)"
            log_success "commenda dependencies installed"

            local schema="$commenda_dir/packages/prisma/schema.prisma"
            if [[ -f "$schema" ]]; then
                log_step "Generating Prisma client types..."
                (
                    cd "$commenda_dir"
                    npx prisma generate --schema=packages/prisma/schema.prisma 2>&1 | tail -5
                ) || log_warn "prisma generate failed (non-fatal)"
                log_success "Prisma types generated"
            fi
        fi
    fi

    # --- sales-tax-api-2 (go modules) ---
    local sta_dir="$instance_dir/sales-tax-api-2"
    if [[ -d "$sta_dir" ]] && [[ -f "$sta_dir/go.mod" ]]; then
        if command -v go &>/dev/null; then
            log_step "Downloading Go modules for sales-tax-api-2..."
            (
                cd "$sta_dir"
                go mod download 2>&1 | tail -5
            ) || log_warn "go mod download had issues (non-fatal)"
            log_success "Go modules downloaded"
        else
            log_warn "Go not installed — skipping sales-tax-api-2 module download"
            log_warn "Install: https://go.dev/dl/"
        fi
    fi
}
