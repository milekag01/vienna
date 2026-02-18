# Vienna

**One command. Isolated environment. Parallel tickets. Zero conflicts.**

Vienna creates fully isolated development environments for every ticket you work on — separate databases, separate queues, separate ports, separate code checkouts. Pass a Linear ticket and it spawns the whole stack, starts all services, opens an AI agent in Cursor, and the agent starts solving it. Five tickets at once, five environments, five agents, no interference.

---

## The Problem

### Worktrees alone aren't enough

You can `git worktree add` to get a second checkout, but that solves maybe 10% of the problem. The real issues:

- **Three codebases, not one.** Commenda has `commenda` (frontend monorepo), `commenda-logical-backend` (NestJS API), and `sales-tax-api-2` (Go microservice). A worktree for one repo is useless without worktrees for all three, configured to talk to each other.

- **Shared infrastructure destroys isolation.** Two worktrees both pointing at the same Postgres means one agent's migration breaks the other's data. Same Redis, same queues — one agent's background job eats the other's messages. Same ports — only one can run at a time.

- **Environment files are a minefield.** Each service has 50+ env vars. Database URLs, Redis hosts, SQS queue ARNs, service-to-service URLs, API keys — all hardcoded to default ports. Changing one and forgetting another means silent failures.

- **Nobody wants to do this setup manually.** An engineer could theoretically set all this up by hand: create 3 worktrees, spin up 2 Postgres containers on custom ports, Redis on a custom port, LocalStack with 22 queues, generate .env files, patch config files, run migrations. That's 45 minutes of setup per environment. Nobody does it.

### What actually happens today

**Engineer A** is working on filing calculations. **Engineer B** needs to fix a registration bug. They can't both work locally at the same time without stepping on each other's databases. One of them works on staging instead, which is slow, shared, and unreliable.

**AI agents** are even worse. You want two Cursor agents working on two tickets simultaneously. They'd both be mutating the same database, the same files, the same queue messages. So they work sequentially — one at a time — defeating the purpose.

---

## How Vienna Fixes This

### One command, everything isolated

```
vienna spawn --ticket PLAT-2086 --branch main
```

This single command:

1. **Fetches the ticket** from Linear (title, description, priority, acceptance criteria)
2. **Creates a new branch** from `main` using Linear's suggested branch name
3. **Creates git worktrees** for all three repos on that branch
4. **Starts isolated infrastructure** — its own Postgres (x2), Redis, and LocalStack with 22 SQS queues and 3 S3 buckets
5. **Generates .env files** — every service configured with instance-specific ports, database names, queue URLs
6. **Patches service configs** — NestJS backend.config.ts rewritten so services talk to each other on the right ports
7. **Installs dependencies** — npm, pnpm, go modules, Prisma client generation
8. **Runs all migrations** — Prisma for NestJS, Atlas for Go, seeds admin API tokens
9. **Starts all services** — NestJS backend, Go API, and Enterprise frontend in new terminal tabs
10. **Opens a new AI agent** in Cursor with full ticket context and starts solving immediately

Each environment gets unique ports. Instance 1 gets Postgres on 5501/5601, Redis on 6401. Instance 2 gets 5502/5602/6402. No collisions. Run five simultaneously.

### Without a ticket — plain spawn

```
vienna spawn my-feature --branch feature-auth
```

Same isolation, just without the Linear integration and AI agent. You get the environment, you work in it manually.

### The full lifecycle

```bash
vienna spawn --ticket PLAT-2086              # Create everything, agent starts working
vienna list                                   # See all running instances
vienna info plat-2086                         # See ports, DB URLs, connection details
vienna run plat-2086                          # Start services (auto in ticket mode)
vienna stop plat-2086                         # Pause infrastructure, keep data
vienna start plat-2086                        # Resume where you left off
vienna destroy plat-2086                      # Tear everything down when done
```

---

## What Gets Created

When you `vienna spawn`, here's what physically exists on your machine:

```
Vienna/
├── instances/
│   ├── plat-2086/                        # One instance
│   │   ├── commenda/                     # Git worktree (frontend monorepo)
│   │   ├── commenda-logical-backend/     # Git worktree (NestJS backend)
│   │   ├── sales-tax-api-2/             # Git worktree (Go microservice)
│   │   ├── .cursor/rules/task.mdc       # AI agent task context (auto-loaded)
│   │   ├── .vienna-task.json            # Machine-readable task context
│   │   └── .vienna-instance.json        # Instance marker
│   │
│   └── plat-2087/                        # Another instance (fully independent)
│       ├── commenda/
│       ├── commenda-logical-backend/
│       └── sales-tax-api-2/
│
├── .vienna-state/                         # Runtime state (gitignored)
│   ├── registry.json                     # Port allocation registry
│   ├── secrets.env                       # API keys (gitignored)
│   └── instances/
│       └── plat-2086/config.json         # Ports, branch, creation time
│
└── vienna/                                # The CLI itself
    ├── bin/vienna.sh                     # Entry point
    ├── lib/                              # Shell modules
    ├── docker/                           # Compose + LocalStack init
    └── overlays/                         # File patches for worktrees
```

Docker containers per instance (namespaced with `vienna-<name>-`):
- `postgres-nestjs` — NestJS/Prisma database
- `postgres-go` — Go/Atlas database
- `redis` — Redis instance
- `localstack` — SQS queues + S3 buckets

---

## Port Allocation

Each instance gets a unique offset. No manual configuration needed.

| Service | Formula | Instance 1 | Instance 2 | Instance 3 |
|---|---|---|---|---|
| PostgreSQL (NestJS) | 5500 + N | 5501 | 5502 | 5503 |
| PostgreSQL (Go) | 5600 + N | 5601 | 5602 | 5603 |
| Redis | 6400 + N | 6401 | 6402 | 6403 |
| LocalStack | 4566 + N | 4567 | 4568 | 4569 |
| NestJS backend | 8100 + N | 8101 | 8102 | 8103 |
| Go API | 8200 + N | 8201 | 8202 | 8203 |
| Enterprise frontend | 3000 + N*10 | 3010 | 3020 | 3030 |

Freed offsets are reused when instances are destroyed.

---

## AI Agent Integration

When you spawn with `--ticket`:

1. **Linear API** fetches the full ticket — title, description, priority, labels, assignee, comments
2. **Task context file** (`.cursor/rules/task.mdc`) is written with:
   - Hard workspace boundary rules — "you MUST NOT touch files outside this instance"
   - The ticket description and acceptance criteria
   - All instance-specific ports and database URLs
   - Guidelines for committing and testing
3. **A new Cursor agent chat** opens automatically in your current window
4. The agent reads the task context and starts solving the ticket immediately
5. You see it in your agent list — switch to it anytime to review or guide

Each agent works in its own worktree, talks to its own databases, runs on its own ports. Five agents, five tickets, zero conflicts.

---

## Who This Is For

**Engineers working on multiple tickets.** Switch context without losing state. Each ticket has its own databases, its own migrations, its own running services.

**Teams using AI coding agents.** Give each agent a ticket and a fully isolated environment. They work in parallel without stepping on each other.

**Anyone tired of environment setup.** One command. Everything works. No 45-minute setup guides.

---

## What's Next

- **`vienna switch`** — Lighter-weight mode for human developers (infra isolation, shared code checkout)
- **Snapshots and restore** — `pg_dump`/`pg_restore` to save and roll back database state
- **Garbage collection** — Auto-destroy instances older than a threshold
- **Linear webhook automation** — Label a ticket "auto-agent" in Linear, Vienna spawns an agent automatically
- **Remote environments** — Run on cloud VMs instead of local machine
