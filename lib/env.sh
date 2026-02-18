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
        printf '\n%s="%s"\n' "$key" "$value" >> "$file"
    fi
}

# Generate .env files for an instance
# Args: instance_name, offset
env_generate() {
    local name="$1"
    local offset="$2"
    local instance_dir="$VIENNA_INSTANCES/$name"

    local sname
    sname=$(safe_name "$name")

    local db_nestjs="${sname}_commenda"
    local db_go="${sname}_salestax"

    local pg_nestjs_port=$((VIENNA_PORT_BASE_PG_NESTJS + offset))
    local pg_go_port=$((VIENNA_PORT_BASE_PG_GO + offset))
    local redis_port=$((VIENNA_PORT_BASE_REDIS + offset))
    local localstack_port=$((VIENNA_PORT_BASE_LOCALSTACK + offset))
    local nestjs_port=$((VIENNA_PORT_BASE_NESTJS + offset))
    local go_api_port=$((VIENNA_PORT_BASE_GO_API + offset))

    local ls_url="http://localhost:${localstack_port}"
    local sqs_base="${ls_url}/${VIENNA_AWS_ACCOUNT_ID}"

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
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${db_nestjs}"
        _env_set "$clb_target" "DATABASE_URL_REPLICA" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${db_nestjs}"
        _env_set "$clb_target" "PROD_DATABASE_URL_REPLICA" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${db_nestjs}"
        _env_set "$clb_target" "REDIS_CONNECTION_HOST" "localhost"
        _env_set "$clb_target" "REDIS_CONNECTION_PORT" "$redis_port"
        _env_set "$clb_target" "PORT" "$nestjs_port"
        _env_set "$clb_target" "SALES_TAX_CLIENT_API_KEY" "$VIENNA_SALES_TAX_API_KEY"
        _env_set "$clb_target" "NODE_ENV" "development"

        # NestJS backend keeps real AWS creds from the base .env —
        # it needs them for SSM Parameter Store config loading at startup.
        # S3 also uses real AWS, which is fine (stateless file storage).

        # Patch backend.config.ts so the NestJS backend talks to this instance's Go API
        local config_ts="$clb_dir/src/common/configuration/backend.config.ts"
        if [[ -f "$config_ts" ]]; then
            sed -i '' \
                "s|\"http://localhost:8001/api/v1\"|\"http://localhost:${go_api_port}/api/v1\"|g; \
                 s|\"https://transaction-tax.api.in.staging.commenda.io/api/v1\"|\"http://localhost:${go_api_port}/api/v1\"|g" \
                "$config_ts" 2>/dev/null || \
            sed -i \
                "s|\"http://localhost:8001/api/v1\"|\"http://localhost:${go_api_port}/api/v1\"|g; \
                 s|\"https://transaction-tax.api.in.staging.commenda.io/api/v1\"|\"http://localhost:${go_api_port}/api/v1\"|g" \
                "$config_ts"

            sed -i '' \
                "s|\"http://localhost:8000/\"|\"http://localhost:${nestjs_port}/\"|g; \
                 s|\"http://localhost:8000\"|\"http://localhost:${nestjs_port}\"|g" \
                "$config_ts" 2>/dev/null || \
            sed -i \
                "s|\"http://localhost:8000/\"|\"http://localhost:${nestjs_port}/\"|g; \
                 s|\"http://localhost:8000\"|\"http://localhost:${nestjs_port}\"|g" \
                "$config_ts"

            log_step "Patched backend.config.ts (Sales Tax API → localhost:$go_api_port, Backend → localhost:$nestjs_port)"
        fi

        log_step "Generated .env for commenda-logical-backend (PG:$pg_nestjs_port/$db_nestjs, Redis:$redis_port)"
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
            "postgres://${VIENNA_PG_GO_USER}:${VIENNA_PG_GO_PASS}@localhost:${pg_go_port}/${db_go}?sslmode=disable"
        _env_set "$sta_target" "RDS_HOSTNAME" "localhost"
        _env_set "$sta_target" "RDS_PORT" "$pg_go_port"
        _env_set "$sta_target" "RDS_DBNAME" "$db_go"
        _env_set "$sta_target" "RDS_USERNAME" "$VIENNA_PG_GO_USER"
        _env_set "$sta_target" "RDS_PASSWORD" "$VIENNA_PG_GO_PASS"
        _env_set "$sta_target" "PORT" "$go_api_port"
        _env_set "$sta_target" "COMMENDA_LOGICAL_BACKEND_URL" "http://localhost:${nestjs_port}/api/v1"
        _env_set "$sta_target" "COMMENDA_FRONTEND_URL" "http://localhost:3000"
        _env_set "$sta_target" "SALES_TAX_CLIENT_API_KEY" "$VIENNA_SALES_TAX_API_KEY"
        _env_set "$sta_target" "ENVIRONMENT" "DEVELOPMENT"

        # AWS → LocalStack
        _env_set "$sta_target" "AWS_ACCESS_KEY" "test"
        _env_set "$sta_target" "AWS_ACCESS_SECRET" "test"
        _env_set "$sta_target" "AWS_ENDPOINT_URL" "$ls_url"
        _env_set "$sta_target" "AWS_REGION" "$VIENNA_AWS_REGION"
        _env_set "$sta_target" "AWS_BUCKET" "${name}-sales-tax-bucket-dev"

        # SQS queue URLs pointing to LocalStack (all prefixed with instance name)
        _env_set "$sta_target" "AWS_WEBHOOK_QUEUE_URL" "${sqs_base}/${sname}_webhook.fifo"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_INVOICE_INITIATE_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_invoice_initiate"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_INVOICE_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_invoice_process"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_CUSTOMER_INITIATE_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_customer_initiate"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_CUSTOMER_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_customer_process"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_PRODUCT_INITIATE_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_product_initiate"
        _env_set "$sta_target" "AWS_BULK_UPLOAD_PRODUCT_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_bulk_upload_product_process"
        _env_set "$sta_target" "AWS_BULK_DELETE_TRANSACTION_QUEUE_URL" "${sqs_base}/${sname}_bulk_delete_transaction"
        _env_set "$sta_target" "AWS_BULK_EXPORT_TRANSACTION_VALIDATION_QUEUE_URL" "${sqs_base}/${sname}_bulk_export_transaction_validation"
        _env_set "$sta_target" "AWS_BULK_EXPORT_TRANSACTION_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_bulk_export_transaction_processing"
        _env_set "$sta_target" "AWS_BULK_EXPORT_PRODUCT_VALIDATION_QUEUE_URL" "${sqs_base}/${sname}_bulk_export_product_validation"
        _env_set "$sta_target" "AWS_BULK_EXPORT_PRODUCT_PROCESSING_QUEUE_URL" "${sqs_base}/${sname}_bulk_export_product_processing"
        _env_set "$sta_target" "AWS_ENQUEUE_TAX_BREAKDOWN_GENERATION_URL" "${sqs_base}/${sname}_tax_breakdown_generation"
        _env_set "$sta_target" "AWS_TAX_BREAKDOWN_GENERATION_URL" "${sqs_base}/${sname}_tax_breakdown_generation"
        _env_set "$sta_target" "AWS_TAX_BREAKDOWN_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_tax_breakdown_process"
        _env_set "$sta_target" "AWS_FILING_NUMBERS_AGGREGATION_QUEUE_URL" "${sqs_base}/${sname}_filing_numbers_aggregation"
        _env_set "$sta_target" "AWS_ATTACH_INVOICES_TO_FILING_QUEUE_URL" "${sqs_base}/${sname}_attach_invoices_to_filing"
        _env_set "$sta_target" "AWS_BULK_EXPORT_TAX_BREAKDOWNS_QUEUE_URL" "${sqs_base}/${sname}_bulk_export_tax_breakdowns"
        _env_set "$sta_target" "AWS_TAX_ESTIMATE_RECALCULATION_INITIATE_QUEUE_URL" "${sqs_base}/${sname}_tax_estimate_recalculation_initiate"
        _env_set "$sta_target" "AWS_TAX_ESTIMATE_RECALCULATION_PROCESS_QUEUE_URL" "${sqs_base}/${sname}_tax_estimate_recalculation_process"
        _env_set "$sta_target" "AWS_NEXUS_SYNC_QUEUE_URL" "${sqs_base}/${sname}_nexus_sync"
        _env_set "$sta_target" "AWS_CONTENT_INGESTION_QUEUE_URL" "${sqs_base}/${sname}_content_ingestion"

        log_step "Generated .env for sales-tax-api-2 (PG:$pg_go_port/$db_go, API:$go_api_port, AWS:$localstack_port)"
    fi

    # --- commenda (Prisma package) ---
    local prisma_dir="$instance_dir/commenda/packages/prisma"
    if [[ -d "$prisma_dir" ]]; then
        local prisma_target="$prisma_dir/.env"
        echo "DATABASE_URL=\"postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${db_nestjs}\"" > "$prisma_target"
        log_step "Generated .env for commenda/packages/prisma (PG:$pg_nestjs_port/$db_nestjs)"
    fi

    # --- commenda/apps/enterprise ---
    local enterprise_port=$((VIENNA_PORT_BASE_APP_POOL + offset * VIENNA_APP_POOL_SIZE))
    local ent_dir="$instance_dir/commenda/apps/enterprise"
    if [[ -d "$ent_dir" ]]; then
        local ent_source="$VIENNA_WORKSPACE/commenda/apps/enterprise/.env"
        local ent_target="$ent_dir/.env"

        if [[ -f "$ent_source" ]]; then
            cp "$ent_source" "$ent_target"
        else
            touch "$ent_target"
        fi

        _env_set "$ent_target" "NEXT_PUBLIC_SERVER_URL" "http://localhost:${nestjs_port}"
        _env_set "$ent_target" "DATABASE_URL" \
            "postgres://${VIENNA_PG_NESTJS_USER}:${VIENNA_PG_NESTJS_PASS}@localhost:${pg_nestjs_port}/${db_nestjs}"
        _env_set "$ent_target" "PORT" "$enterprise_port"

        log_step "Generated .env for commenda/apps/enterprise (port:$enterprise_port, backend:localhost:$nestjs_port)"
    fi
}
