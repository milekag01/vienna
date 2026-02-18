# Vienna

**One command. Isolated environment. Parallel tickets. Zero conflicts.**

Vienna creates fully isolated development environments for every ticket you work on — separate databases, separate queues, separate ports, separate code checkouts. Pass a Linear ticket and it spawns the whole stack, starts all services, opens an AI agent in Cursor, and the agent starts solving it. Five tickets at once, five environments, five agents, no interference.

---

## The Problem

### Three codebases that are already hard to run together

The Commenda platform is three separate services that talk to each other:

- `commenda` — frontend monorepo (Next.js apps)
- `commenda-logical-backend` — NestJS API backend
- `sales-tax-api-2` — Go microservice (tax calculation engine)

Each has its own `.env` file with different configuration — database URLs, Redis hosts, SQS queue ARNs, API ports. The NestJS backend needs to know where the Go API lives. The frontends need to know where the NestJS backend lives. Getting all three running and talking to each other locally is already painful for a single setup.

### The environment is shared — even across worktrees

This is the real problem. Say you create a git worktree of `sales-tax-api-2` for a second ticket. You now have two checkouts of the code. But the `.env` file in both checkouts has the same `DATABASE_URL=postgresql://localhost:5432/salestax`. Both point at the **same Postgres instance**.

The same is true for every piece of infrastructure:

- Both worktrees talk to the same database
- Both worktrees push to the same SQS queues
- Both worktrees connect to the same Redis
- Both worktrees run on the same ports

**Worktrees give you isolated code. They do not give you an isolated environment.** The `.env` belongs to the codebase, and every worktree inherits the same one.

### Migrations from different branches destroy each other

This is where it gets dangerous. Say you have three tickets, each requiring a database migration:

- Ticket A adds a `filing_status` column to the registrations table
- Ticket B renames `tax_rate` to `effective_rate` across three tables
- Ticket C adds a whole new `nexus_rules` table

If all three agents (or you + two agents) run their migrations against the same Postgres, you get a tangled mess:

- The migration history now has changes from three unrelated branches interleaved
- You can't roll back Ticket A's migration without also rolling back B's and C's
- If Ticket B gets abandoned, its migration is still baked into the database — you can't cleanly undo it
- Your working branch (the one you're coding on manually) suddenly has schema changes you didn't make, and things break in ways you can't explain

Once that happens, resetting is extremely painful. You'd have to figure out which migrations came from which branch, manually reverse them in the right order, and hope nothing was dependent on the intermediate state. In practice, people just blow away the database and re-migrate from scratch — losing all their test data.

### And you can't run multiple instances at all

Even if you only want to work on one ticket at a time, you can't run two copies of the stack simultaneously. Both would try to bind to port 8000 for NestJS, port 8001 for the Go API, port 5432 for Postgres. One of them fails to start. You'd have to manually change ports across 50+ env vars in 3 codebases to get a second instance running — and make sure the services still find each other on the new ports.

---

## How Vienna Fixes This

### Vienna gives each instance its own environment

The key idea: Vienna doesn't just create worktrees — it creates a **complete, isolated environment** for each instance. New databases, new Redis, new queues, new ports. And most importantly, **new `.env` files** in each worktree that point to that instance's own infrastructure.

Instance 1's `sales-tax-api-2/.env` has `DATABASE_URL=postgresql://localhost:5501/salestax`.
Instance 2's has `DATABASE_URL=postgresql://localhost:5502/salestax`.
Different Postgres containers, different data, different migration histories. Completely independent.

### One command, everything set up

```
vienna spawn --ticket PLAT-2086 --branch main
```

This single command:

1. **Fetches the ticket** from Linear (title, description, priority, acceptance criteria)
2. **Creates a new branch** from `main` using Linear's suggested branch name
3. **Creates git worktrees** for all three codebases on that branch
4. **Spins up isolated infrastructure** — its own Postgres (x2), Redis, and LocalStack with 22 SQS queues and 3 S3 buckets, all on unique ports
5. **Generates `.env` files** in each worktree pointing to this instance's databases, Redis, queues, and ports — so the services within this instance talk to each other and to nothing else
6. **Patches service configs** — NestJS `backend.config.ts` rewritten so the backend calls the Go API on the right port
7. **Installs dependencies** — npm, pnpm, go modules, Prisma client generation
8. **Runs all migrations** — Prisma for NestJS, Atlas for Go — against this instance's databases only
9. **Starts all three services** — NestJS backend, Go API, and Enterprise frontend in new terminal tabs
10. **Opens a new AI agent** in Cursor with full ticket context and starts solving immediately

Now each ticket has its own databases with its own migration history. An agent working on Ticket A applies migrations to port 5501. An agent on Ticket B applies different migrations to port 5502. They never interfere. Your working branch stays clean.

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

| Service             | Formula      | Instance 1 | Instance 2 | Instance 3 |
| ------------------- | ------------ | ---------- | ---------- | ---------- |
| PostgreSQL (NestJS) | 5500 + N     | 5501       | 5502       | 5503       |
| PostgreSQL (Go)     | 5600 + N     | 5601       | 5602       | 5603       |
| Redis               | 6400 + N     | 6401       | 6402       | 6403       |
| LocalStack          | 4566 + N     | 4567       | 4568       | 4569       |
| NestJS backend      | 8100 + N     | 8101       | 8102       | 8103       |
| Go API              | 8200 + N     | 8201       | 8202       | 8203       |
| Enterprise frontend | 3000 + N\*10 | 3010       | 3020       | 3030       |

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
