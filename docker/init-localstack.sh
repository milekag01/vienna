#!/bin/bash
# LocalStack init script — runs automatically when the container is healthy
# Creates all SQS queues and S3 buckets needed by the application

REGION="${DEFAULT_REGION:-us-east-1}"

echo "=== Vienna LocalStack Init ==="
echo "Region: $REGION"

# --- S3 Buckets ---
for bucket in commenda-dev commenda-auto-delete-dev sales-tax-bucket-dev; do
    echo "Creating S3 bucket: $bucket"
    awslocal s3 mb "s3://$bucket" --region "$REGION" 2>/dev/null || true
done

# --- SQS Queues (standard) ---
STANDARD_QUEUES=(
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

for queue in "${STANDARD_QUEUES[@]}"; do
    echo "Creating SQS queue: $queue"
    awslocal sqs create-queue \
        --queue-name "$queue" \
        --region "$REGION" 2>/dev/null || true
done

# --- SQS FIFO Queues ---
FIFO_QUEUES=(
    "webhook.fifo"
)

for queue in "${FIFO_QUEUES[@]}"; do
    echo "Creating SQS FIFO queue: $queue"
    awslocal sqs create-queue \
        --queue-name "$queue" \
        --attributes "FifoQueue=true,ContentBasedDeduplication=false" \
        --region "$REGION" 2>/dev/null || true
done

echo ""
echo "=== Queues created ==="
awslocal sqs list-queues --region "$REGION" 2>/dev/null | head -30
echo ""
echo "=== Buckets created ==="
awslocal s3 ls 2>/dev/null
echo ""
echo "=== Vienna LocalStack Init Complete ==="
