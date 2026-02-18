#!/usr/bin/env bash
# Vienna configuration — sourced by all modules

VIENNA_REPOS=("commenda" "commenda-logical-backend" "sales-tax-api-2")

# Port base ranges — each instance gets base + offset
VIENNA_PORT_BASE_PG_NESTJS=5500
VIENNA_PORT_BASE_PG_GO=5600
VIENNA_PORT_BASE_REDIS=6400
VIENNA_PORT_BASE_NESTJS=8100
VIENNA_PORT_BASE_GO_API=8200
VIENNA_PORT_BASE_APP_POOL=3000
VIENNA_APP_POOL_SIZE=10

# Docker image versions
VIENNA_POSTGRES_IMAGE="postgres:15"
VIENNA_REDIS_IMAGE="redis:7-alpine"

# Database credentials (local dev only)
VIENNA_PG_NESTJS_USER="commenda"
VIENNA_PG_NESTJS_PASS="commenda"
VIENNA_PG_NESTJS_DB="commenda"

VIENNA_PG_GO_USER="salestax"
VIENNA_PG_GO_PASS="salestax"
VIENNA_PG_GO_DB="salestax"

# Shared API key between NestJS and Go services
VIENNA_SALES_TAX_API_KEY="localkey"
