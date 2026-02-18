#!/usr/bin/env bash
# vienna spawn — create a fully isolated environment with worktrees
# With --ticket: also fetches Linear context, injects task file, opens Cursor agent

source "$VIENNA_DIR/lib/ports.sh"
source "$VIENNA_DIR/lib/infra.sh"
source "$VIENNA_DIR/lib/worktree.sh"
source "$VIENNA_DIR/lib/env.sh"
source "$VIENNA_DIR/lib/deps.sh"
source "$VIENNA_DIR/lib/migrate.sh"
source "$VIENNA_DIR/lib/context.sh"
source "$VIENNA_DIR/lib/linear.sh"
source "$VIENNA_DIR/lib/run.sh"

cmd_spawn() {
    local name=""
    local branch=""
    local ticket=""
    local new_window="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch|-b)
                branch="$2"
                shift 2
                ;;
            --ticket|-t)
                ticket="$2"
                shift 2
                ;;
            --new-window)
                new_window="true"
                shift
                ;;
            --help|-h)
                echo "Usage: vienna spawn <name> --branch <branch>"
                echo "       vienna spawn --ticket <ID-or-URL>"
                echo "       vienna spawn --ticket <ID-or-URL> --new-window"
                echo ""
                echo "Creates a fully isolated environment:"
                echo "  - Git worktrees for all repos on the specified branch"
                echo "  - Separate PostgreSQL databases and Redis instance"
                echo "  - Unique ports (no conflicts with other instances)"
                echo "  - Generated .env files with correct configuration"
                echo "  - Migrations applied automatically"
                echo ""
                echo "With --ticket:"
                echo "  - Fetches ticket details from Linear"
                echo "  - Auto-derives instance name and branch from ticket"
                echo "  - Writes task context (.cursor/rules/task.mdc)"
                echo "  - Opens an Agent chat in your current Cursor (default)"
                echo ""
                echo "Flags:"
                echo "  --new-window    Open a separate Cursor window instead of an agent chat"
                echo "                  (true hard isolation — agent can only see the instance)"
                echo ""
                echo "Examples:"
                echo "  vienna spawn my-feature --branch feature-auth"
                echo "  vienna spawn --ticket COM-4521"
                echo "  vienna spawn --ticket COM-4521 --new-window"
                echo "  vienna spawn --ticket https://linear.app/commenda/issue/COM-4521/some-title"
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

    # --- Ticket mode: fetch from Linear, derive name + branch ---
    if [[ -n "$ticket" ]]; then
        local identifier
        identifier=$(linear_parse_ticket_input "$ticket") || return 1

        if ! linear_fetch_ticket "$identifier"; then
            return 1
        fi

        # Auto-derive name if not explicitly provided
        if [[ -z "$name" ]]; then
            name=$(linear_instance_name "$LINEAR_TICKET_IDENTIFIER")
        fi

        # In ticket mode, --branch means "base branch to create FROM" (default: main).
        # The actual worktree branch is always a new ticket-specific branch.
        local base_branch="${branch:-main}"

        # Always derive a ticket-specific branch (never reuse main/develop directly)
        if [[ -n "$LINEAR_TICKET_BRANCH" ]]; then
            branch="$LINEAR_TICKET_BRANCH"
            log_step "Using Linear's suggested branch: $branch"
        else
            branch=$(linear_branch_name "$LINEAR_TICKET_IDENTIFIER" "$LINEAR_TICKET_TITLE")
            log_step "Auto-generated branch: $branch"
        fi

        # Store the base branch so worktree.sh knows where to branch from
        export VIENNA_BASE_BRANCH="$base_branch"

        echo ""
        log_info "Ticket mode: $LINEAR_TICKET_IDENTIFIER → instance ${BOLD}$name${NC}, branch ${BOLD}$branch${NC} (from $base_branch)"
        echo ""
    fi

    if [[ -z "$name" ]]; then
        log_error "Instance name is required"
        echo "Usage: vienna spawn <name> --branch <branch>"
        echo "       vienna spawn --ticket <ID-or-URL>"
        return 1
    fi

    if [[ -z "$branch" ]]; then
        log_error "--branch is required (or use --ticket to auto-derive)"
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

    # Step 2: Create worktrees (auto-create branch in ticket mode)
    local create_branch="false"
    [[ -n "$ticket" ]] && create_branch="true"

    log_info "Creating git worktrees..."
    if ! worktrees_create "$name" "$branch" "$create_branch"; then
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

    # Step 9 (ticket mode): Write task context + open Cursor
    if [[ -n "$ticket" ]]; then
        echo ""
        log_info "Writing task context for ${BOLD}$LINEAR_TICKET_IDENTIFIER${NC}..."
        linear_write_task_context "$VIENNA_INSTANCES/$name" "$instance_config_dir/config.json"
        echo ""
    fi

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

    if [[ -n "$ticket" ]]; then
        echo "  Ticket:              $LINEAR_TICKET_IDENTIFIER — $LINEAR_TICKET_TITLE"
        echo "  Task context:        $VIENNA_INSTANCES/$name/.cursor/rules/task.mdc"
        echo ""

        # Auto-start all services (CLB, Sales Tax API, Enterprise) in new terminal tabs
        log_info "Starting services for ${BOLD}$name${NC}..."
        cmd_run "$name" || log_warn "Some services may not have started. You can run 'vienna run $name' manually."
        echo ""

        # Wait for terminal tabs to settle before opening agent chat
        log_step "Waiting for services to initialize..."
        sleep 5

        # Open agent chat (or new window)
        if [[ "$new_window" == "true" ]]; then
            linear_open_cursor_window "$VIENNA_INSTANCES/$name"
        else
            linear_open_agent_chat "$VIENNA_INSTANCES/$name" "$LINEAR_TICKET_IDENTIFIER" "$LINEAR_TICKET_TITLE"
        fi
    else
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
    fi
    echo ""
}
