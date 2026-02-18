#!/usr/bin/env bash
# Vienna configuration — sourced by all modules

VIENNA_REPOS=("commenda" "commenda-logical-backend" "sales-tax-api-2")

# Port base ranges — each instance gets base + offset
VIENNA_PORT_BASE_PG_NESTJS=5500
VIENNA_PORT_BASE_PG_GO=5600
VIENNA_PORT_BASE_REDIS=6400
VIENNA_PORT_BASE_LOCALSTACK=4566  # LocalStack gateway (SQS, S3, SNS, etc.)
VIENNA_PORT_BASE_NESTJS=8100
VIENNA_PORT_BASE_GO_API=8200
VIENNA_PORT_BASE_APP_POOL=3000
VIENNA_APP_POOL_SIZE=10

# Docker image versions
VIENNA_POSTGRES_IMAGE="postgres:15"
VIENNA_REDIS_IMAGE="redis:7-alpine"
VIENNA_LOCALSTACK_IMAGE="localstack/localstack:latest"

# Database credentials (local dev only)
VIENNA_PG_NESTJS_USER="commenda"
VIENNA_PG_NESTJS_PASS="commenda"
VIENNA_PG_NESTJS_DB="commenda"

VIENNA_PG_GO_USER="salestax"
VIENNA_PG_GO_PASS="salestax"
VIENNA_PG_GO_DB="salestax"

# Shared API key between NestJS and Go services
VIENNA_SALES_TAX_API_KEY="localkey"

# AWS / LocalStack config
VIENNA_AWS_REGION="us-east-1"
VIENNA_AWS_ACCOUNT_ID="000000000000"

# S3 buckets to create in LocalStack
VIENNA_S3_BUCKETS=("commenda-dev" "commenda-auto-delete-dev" "sales-tax-bucket-dev")

# --- Secrets (loaded from .vienna-state/secrets.env if present) ---
VIENNA_LINEAR_API_KEY="${VIENNA_LINEAR_API_KEY:-}"

_vienna_secrets_file="$VIENNA_WORKSPACE/.vienna-state/secrets.env"
if [[ -f "$_vienna_secrets_file" ]]; then
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        value="${value%\"}"
        value="${value#\"}"
        export "$key=$value"
    done < "$_vienna_secrets_file"
    VIENNA_LINEAR_API_KEY="${VIENNA_LINEAR_API_KEY:-}"
fi

# SQS queues to create in LocalStack (Go service)
VIENNA_SQS_QUEUES=(
    "webhook.fifo"
    "bulk_upload_invoice_initiate"
    "bulk_upload_invoice_process"
    "bulk_upload_customer_initiate"
    "bulk_upload_customer_process"
    "bulk_upload_product_initiate"
    "bulk_upload_product_process"
    "bulk_delete_transaction"
    "bulk_export_transaction_validation"
    "bulk_export_transaction_processing"
    "bulk_export_product_validation"
    "bulk_export_product_processing"
    "tax_breakdown_generation"
    "tax_breakdown_process"
    "filing_numbers_aggregation"
    "attach_invoices_to_filing"
    "bulk_export_tax_breakdowns"
    "tax_estimate_recalculation_initiate"
    "tax_estimate_recalculation_process"
    "nexus_sync"
    "content_ingestion"
    "textract"
)
