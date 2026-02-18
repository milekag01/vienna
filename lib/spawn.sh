#!/usr/bin/env bash
# vienna spawn — create a fully isolated environment with worktrees

source "$VIENNA_DIR/lib/ports.sh"
source "$VIENNA_DIR/lib/infra.sh"
source "$VIENNA_DIR/lib/worktree.sh"
source "$VIENNA_DIR/lib/env.sh"
source "$VIENNA_DIR/lib/deps.sh"
source "$VIENNA_DIR/lib/migrate.sh"
source "$VIENNA_DIR/lib/context.sh"

cmd_spawn() {
    local name=""
    local branch=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch|-b)
                branch="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: vienna spawn <name> --branch <branch>"
                echo ""
                echo "Creates a fully isolated environment:"
                echo "  - Git worktrees for all repos on the specified branch"
                echo "  - Separate PostgreSQL databases and Redis instance"
                echo "  - Unique ports (no conflicts with other instances)"
                echo "  - Generated .env files with correct configuration"
                echo "  - Migrations applied automatically"
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                else
                    log_error "Unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        log_error "Instance name is required"
        echo "Usage: vienna spawn <name> --branch <branch>"
        return 1
    fi

    if [[ -z "$branch" ]]; then
        log_error "--branch is required"
        echo "Usage: vienna spawn $name --branch <branch>"
        return 1
    fi

    # Validate name (alphanumeric, dashes, underscores only)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Instance name must be alphanumeric (dashes and underscores allowed)"
        return 1
    fi

    # Check if instance already exists
    if instance_exists "$name"; then
        log_error "Instance '$name' already exists"
        echo "  Run 'vienna destroy $name' first, or choose a different name."
        echo "  Run 'vienna list' to see all instances."
        return 1
    fi

    echo ""
    log_info "Creating instance ${BOLD}$name${NC} on branch ${BOLD}$branch${NC}"
    echo ""

    ensure_jq
    ensure_docker

    # Step 1: Allocate ports
    log_info "Allocating ports..."
    local offset
    offset=$(allocate_ports "$name")
    log_step "Assigned port offset: $offset"

    # Compute ports for display
    local pg_nestjs_port=$((VIENNA_PORT_BASE_PG_NESTJS + offset))
    local pg_go_port=$((VIENNA_PORT_BASE_PG_GO + offset))
    local redis_port=$((VIENNA_PORT_BASE_REDIS + offset))
    local localstack_port=$((VIENNA_PORT_BASE_LOCALSTACK + offset))
    local nestjs_port=$((VIENNA_PORT_BASE_NESTJS + offset))
    local go_api_port=$((VIENNA_PORT_BASE_GO_API + offset))
    local enterprise_port=$((VIENNA_PORT_BASE_APP_POOL + offset * VIENNA_APP_POOL_SIZE))
    echo ""

    # Step 2: Create worktrees
    log_info "Creating git worktrees..."
    if ! worktrees_create "$name" "$branch"; then
        log_error "Failed to create worktrees. Cleaning up..."
        free_ports "$name"
        worktrees_remove "$name"
        return 1
    fi
    echo ""

    # Step 3: Apply overlays (patches that can't be committed to main yet)
    local overlay_dir="$VIENNA_DIR/overlays"
    if [[ -d "$overlay_dir" ]]; then
        local has_overlays=false
        for repo_overlay in "$overlay_dir"/*/; do
            [[ -d "$repo_overlay" ]] || continue
            local repo_name
            repo_name=$(basename "$repo_overlay")
            local target_dir="$VIENNA_INSTANCES/$name/$repo_name"
            if [[ -d "$target_dir" ]]; then
                cp -R "$repo_overlay"/* "$target_dir/" 2>/dev/null && has_overlays=true
            fi
        done
        if $has_overlays; then
            log_step "Applied file overlays from vienna/overlays/"
        fi
    fi
    echo ""

    # Step 4: Start Docker infrastructure
    log_info "Starting infrastructure..."
    if ! infra_up "$name"; then
        log_error "Failed to start infrastructure. Cleaning up..."
        free_ports "$name"
        worktrees_remove "$name"
        return 1
    fi
    echo ""

    # Step 5: Generate .env files
    log_info "Generating environment files..."
    env_generate "$name" "$offset"
    echo ""

    # Step 6: Save instance config (before migrations — so destroy works even if migrations fail)
    local instance_config_dir="$VIENNA_STATE/instances/$name"
    ensure_dir "$instance_config_dir"

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$instance_config_dir/config.json" <<EOF
{
    "name": "$name",
    "branch": "$branch",
    "mode": "spawn",
    "offset": $offset,
    "created": "$now",
    "ports": {
        "pg_nestjs": $pg_nestjs_port,
        "pg_go": $pg_go_port,
        "redis": $redis_port,
        "localstack": $localstack_port,
        "nestjs": $nestjs_port,
        "go_api": $go_api_port,
        "enterprise": $enterprise_port
    }
}
EOF

    # Write marker file in instance directory
    cat > "$VIENNA_INSTANCES/$name/.vienna-instance.json" <<EOF
{
    "name": "$name",
    "branch": "$branch",
    "config_path": "$instance_config_dir/config.json"
}
EOF

    # Step 7: Install dependencies (non-fatal — user can install manually)
    install_deps "$name" || {
        log_warn "Some dependency installations failed. You can run them manually:"
        log_warn "  cd $VIENNA_INSTANCES/$name/commenda-logical-backend && npm install"
        log_warn "  cd $VIENNA_INSTANCES/$name/commenda && pnpm install && npx prisma generate --schema=packages/prisma/schema.prisma"
    }
    echo ""

    # Step 8: Apply migrations (non-fatal — user can run `vienna migrate` later)
    log_info "Applying migrations..."
    migrate_all "$name" "$offset" || {
        log_warn "Some migrations failed. You can run them manually later:"
        log_warn "  cd $VIENNA_INSTANCES/$name/commenda-logical-backend && npx prisma migrate deploy"
        log_warn "  cd $VIENNA_INSTANCES/$name/sales-tax-api-2 && atlas migrate apply --dir file://database/migrations --url \$DATABASE_URL"
    }
    echo ""

    # Done
    echo ""
    log_success "========================================="
    log_success "Instance ${BOLD}$name${NC} is ready!"
    log_success "========================================="
    echo ""
    echo "  Branch:              $branch"
    echo "  Location:            $VIENNA_INSTANCES/$name/"
    echo ""
    echo "  PostgreSQL (NestJS): localhost:$pg_nestjs_port"
    echo "  PostgreSQL (Go):     localhost:$pg_go_port"
    echo "  Redis:               localhost:$redis_port"
    echo "  LocalStack (AWS):    localhost:$localstack_port"
    echo "  NestJS backend port: $nestjs_port"
    echo "  Go API port:         $go_api_port"
    echo "  Enterprise port:     $enterprise_port"
    echo ""
    echo "  To start the NestJS backend:"
    echo "    cd $VIENNA_INSTANCES/$name/commenda-logical-backend"
    echo "    npm run start:dev"
    echo ""
    echo "  To start the Go API:"
    echo "    cd $VIENNA_INSTANCES/$name/sales-tax-api-2"
    echo "    make start"
    echo ""
    echo "  To start the Enterprise frontend:"
    echo "    cd $VIENNA_INSTANCES/$name/commenda/apps/enterprise"
    echo "    pnpm dev -p $enterprise_port"
    echo ""
}
