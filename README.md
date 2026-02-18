# Vienna

**Parallel-safe isolated development environments for multi-repo projects.**

Vienna solves a specific problem: you have 3 codebases (a frontend monorepo, a NestJS backend, and a Go microservice) that share databases, Redis, and message queues. You want to work on multiple tickets simultaneously — or have AI agents do it — without them destroying each other's data.

---

## The Problem

### Git worktrees aren't enough

A git worktree gives you a second checkout of your code. That's it. It doesn't give you a second database. Two worktrees both run Prisma migrations against the same Postgres on port 5432. One agent adds a column, the other drops a table. Your data is gone.

### Everything is shared and everything breaks

When you have multiple codebases talking to each other through shared infrastructure:

- **Databases are shared.** Two branches with different migrations corrupt each other. Agent A runs `prisma migrate deploy` and adds a table. Agent B runs a different migration that conflicts. Now both are broken.

- **Queues are shared.** Both instances push to the same SQS queues. Agent A's webhook message gets consumed by Agent B's worker. Silent data corruption.

- **Ports are shared.** You can't run two NestJS backends on port 8000 at the same time. And even if you change one port, you need to update 50+ environment variables that reference it across 3 codebases.

- **Redis is shared.** Bull queues, caching, sessions — all stomped by whoever writes last.

### The real cost

Setting up a truly isolated environment by hand means: spin up 2 Postgres containers on custom ports, a Redis on a custom port, a LocalStack with 22 SQS queues and 3 S3 buckets, create 3 git worktrees, generate `.env` files for each with the right ports, patch config files so services find each other, install dependencies, run migrations. That's 30-45 minutes per environment. Nobody does it. So everyone works on one thing at a time.

---

## How Vienna Fixes This

One command creates everything:

```bash
vienna spawn --ticket PLAT-2086 --branch main
```

This:

1. Fetches the ticket from Linear (title, description, priority, comments)
2. Creates a new branch from `main` using Linear's suggested branch name
3. Creates git worktrees for all 3 repos on that branch
4. Starts isolated Docker containers — its own Postgres (x2), Redis, and LocalStack
5. Generates `.env` files with instance-specific ports and URLs for every service
6. Installs all dependencies (npm, pnpm, go modules)
7. Runs all migrations (Prisma for NestJS, Atlas for Go)
8. Starts the NestJS backend, Go API, and Enterprise frontend
9. Opens a new AI agent chat in Cursor with the ticket context
10. The agent reads the ticket and starts solving

Each environment gets unique ports. No collisions. Run 5 simultaneously.

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

## Why Not Just Use Docker Compose Profiles / Devcontainers / etc.?

Those tools solve container isolation. Vienna solves the full-stack problem:

- **Code isolation** — git worktrees so each agent edits its own files
- **Database isolation** — separate Postgres instances with independent migration state
- **Queue isolation** — namespaced SQS queues per instance
- **Configuration isolation** — auto-generated `.env` files with correct ports everywhere
- **Service discovery** — services within an instance find each other automatically
- **AI agent integration** — task context injection and Cursor automation

A Devcontainer can do some of this. But you'd need a separate Devcontainer config for every instance, and they don't help with the AI agent workflow.

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

Three separate databases. Three separate queue sets. Three separate code checkouts. Three separate running service stacks. No conflicts.
