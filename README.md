# Vienna

**Parallel-safe isolated development environments for multi-repo projects.**

Vienna solves a specific problem: you have 3 codebases (`commenda`, `commenda-logical-backend`, `sales-tax-api-2`) that each have their own environment configuration, and all three need to run together and talk to each other. Getting that working once is already painful. Getting multiple isolated copies running in parallel — so you or your AI agents can work on several tickets at the same time — is what Vienna automates.

---

## The Problem

### Three codebases, each with their own config, all need to run together

Each codebase has its own `.env` file defining database URLs, Redis hosts, SQS queue ARNs, API ports, and service-to-service URLs. The NestJS backend needs to know where the Go API lives. The frontend needs to know where the NestJS backend lives. Each service has 50+ env vars. Getting all three running and wired together locally is already a chore for a single instance.

### The environment is shared — even across worktrees

This is the core problem. Say you create a git worktree of `sales-tax-api-2` for a second ticket. You now have two checkouts of the code. But the `.env` in both has the same `DATABASE_URL=postgresql://localhost:5432/salestax`. Both point at the **same Postgres**.

Git worktrees give you isolated code. They do **not** give you an isolated environment. The `.env` belongs to the codebase, and every worktree inherits the same one. So every worktree talks to the same database, same Redis, same SQS queues, same ports.

### Migrations from different branches destroy each other

If you have three tickets each requiring a database migration, and all three agents (or you + two agents) run their migrations against the same Postgres, you get a tangled mess. The migration history has changes from three unrelated branches interleaved. You can't roll back one without rolling back the others. If a ticket gets abandoned, its migration is still baked in. Your working branch — the one you're coding on manually — suddenly has schema changes you didn't make, and things break in ways you can't trace back.

Resetting from this is painful: figure out which migrations came from which branch, reverse them in order, hope nothing depended on the intermediate state. In practice, people blow away the database and re-migrate from scratch, losing all test data.

### You can't even run two instances at once

Even for a single second copy, both would try to bind to port 8000 (NestJS), port 8001 (Go API), port 5432 (Postgres). One fails to start. You'd have to manually change ports across 50+ env vars in 3 codebases and make sure all the cross-service references still match.

---

## How Vienna Fixes This

Vienna creates a **new environment** for each instance — new databases, new Redis, new queues, new ports — and generates **new `.env` files** in each worktree pointing to that instance's own infrastructure. Instance 1's `sales-tax-api-2/.env` points to Postgres on port 5501. Instance 2's points to port 5502. Different containers, different data, different migration histories. Completely independent.

One command does all of it:

```bash
vienna spawn --ticket PLAT-2086 --branch main
```

This:

1. Fetches the ticket from Linear (title, description, priority, comments)
2. Creates a new branch from `main` using Linear's suggested branch name
3. Creates git worktrees for all 3 codebases on that branch
4. Spins up isolated Docker containers — its own Postgres (x2), Redis, and LocalStack
5. Generates `.env` files **in each worktree** with instance-specific ports, DB URLs, queue ARNs — so the three services within this instance find each other and nothing else
6. Installs all dependencies (npm, pnpm, go modules)
7. Runs all migrations against **this instance's databases only** (Prisma for NestJS, Atlas for Go)
8. Starts the NestJS backend, Go API, and Enterprise frontend
9. Opens a new AI agent chat in Cursor with the ticket context
10. The agent reads the ticket and starts solving

Each ticket gets its own databases with its own migration history. Agents on different tickets never touch each other's data. Your working branch stays clean.

---

## Quick Start

### Prerequisites

- macOS (uses AppleScript for Cursor integration)
- Docker Desktop running
- `jq` installed (`brew install jq`)
- Git repos cloned: `commenda`, `commenda-logical-backend`, `sales-tax-api-2`

### Install

```bash
cd Vienna/vienna
chmod +x install.sh
./install.sh
```

This creates a `vienna` symlink in `/usr/local/bin`.

### Set up Linear API key (optional, for ticket mode)

1. Go to [linear.app](https://linear.app) → Settings → API → Personal API keys
2. Create a key, then:

```bash
mkdir -p .vienna-state
echo 'VIENNA_LINEAR_API_KEY=lin_api_YOUR_KEY_HERE' > .vienna-state/secrets.env
```

This file is gitignored automatically.

---

## Commands

### Create an environment

```bash
# From a Linear ticket (fetches context, starts services, opens AI agent)
vienna spawn --ticket PLAT-2086

# From a ticket, branching from a specific base
vienna spawn --ticket PLAT-2086 --branch main

# With a ticket, in a separate Cursor window (hard isolation)
vienna spawn --ticket PLAT-2086 --new-window

# Without a ticket (manual mode, no agent)
vienna spawn my-feature --branch feature-auth
```

### Manage environments

```bash
vienna list                  # See all instances with status and ports
vienna info my-feature       # Detailed ports, DB URLs, connection commands
vienna run my-feature        # Start CLB + Sales Tax + Enterprise in terminal tabs
vienna stop my-feature       # Pause containers (data preserved)
vienna start my-feature      # Resume where you left off
vienna destroy my-feature    # Tear everything down
```

---

## What Gets Created

```
Vienna/
├── instances/
│   ├── plat-2086/                          # Isolated environment
│   │   ├── commenda/                       # Git worktree
│   │   ├── commenda-logical-backend/       # Git worktree
│   │   ├── sales-tax-api-2/               # Git worktree
│   │   ├── .cursor/rules/task.mdc         # AI agent instructions
│   │   └── .vienna-task.json              # Machine-readable task context
│   │
│   └── plat-2087/                          # Another environment (fully independent)
│       └── ...
│
├── .vienna-state/                           # Runtime state (gitignored)
│   ├── registry.json                       # Port allocation
│   ├── secrets.env                         # API keys (gitignored)
│   └── instances/<name>/config.json        # Per-instance config
│
└── vienna/                                  # The CLI
```

Each instance also gets 4 Docker containers (namespaced `vienna-<name>-*`):
- `postgres-nestjs` — NestJS/Prisma database
- `postgres-go` — Go/Atlas database
- `redis` — Redis
- `localstack` — SQS queues + S3 buckets

---

## Port Allocation

Each instance gets a unique offset. No manual config.

| Service | Instance 1 | Instance 2 | Instance 3 |
|---|---|---|---|
| PostgreSQL (NestJS) | 5501 | 5502 | 5503 |
| PostgreSQL (Go) | 5601 | 5602 | 5603 |
| Redis | 6401 | 6402 | 6403 |
| LocalStack | 4567 | 4568 | 4569 |
| NestJS backend | 8101 | 8102 | 8103 |
| Go API | 8201 | 8202 | 8203 |
| Enterprise frontend | 3010 | 3020 | 3030 |

Freed offsets are reused when you destroy an instance.

---

## AI Agent Integration

When spawning with `--ticket`, Vienna writes a `.cursor/rules/task.mdc` file that Cursor automatically loads. This file contains:

- **Workspace boundary rules** — the agent must only work within the instance directory, must only use this instance's databases and ports. This prevents it from accidentally modifying your main checkout or another instance.
- **Ticket context** — title, description, priority, labels, comments from Linear
- **Instance ports** — so the agent knows how to connect to its databases and services

Then Vienna opens a new agent chat in your current Cursor window, pastes the ticket prompt, and the agent starts working immediately. You see it in your chat list — switch to it anytime to review or guide.

---

## Why Not Just Use Docker Compose Profiles / Devcontainers / Worktrees Alone?

**Worktrees** give you isolated code but shared environment. Every worktree's `.env` still points to the same database. Migrations from different branches collide.

**Docker Compose profiles** can spin up extra containers, but they don't generate the `.env` files that make your 3 codebases point to those new containers. You still have to manually rewire 50+ env vars across 3 repos and make sure the services discover each other on the right ports.

**Devcontainers** could work in theory, but you'd need a separate config for every instance, and they don't coordinate across 3 repos that need to talk to each other.

Vienna handles the whole thing: worktrees + containers + `.env` generation + service wiring + dependency installation + migrations + AI agent context — in one command.

---

## Typical Workflow

**Working on 3 tickets simultaneously:**

```bash
# Ticket 1: Filing calculation bug
vienna spawn --ticket PLAT-2086 --branch main
# → Environment created, services running, AI agent solving

# Ticket 2: Registration schema cleanup
vienna spawn --ticket PLAT-2087 --branch main
# → Second environment, second agent, completely independent

# Ticket 3: You want to work manually
vienna spawn my-experiment --branch main
# → Third environment, no agent, you work in the worktrees yourself

# Check what's running
vienna list

# Done with ticket 1
vienna destroy plat-2086
```

Three separate databases with three independent migration histories. Three separate queue sets. Three separate code checkouts. Three separate `.env` files all pointing to their own infrastructure. Three running service stacks that don't know about each other. No conflicts. No tangled migrations. No data loss.
