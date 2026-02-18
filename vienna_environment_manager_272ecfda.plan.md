---
name: Vienna Environment Manager
overview: 'Design for "Vienna" — a shell-based CLI that manages branch-aware, fully isolated development environments (databases, Redis, queues, ports, env vars) with two modes: `vienna switch` for human developers (infra isolation, shared checkout) and `vienna spawn` for parallel AI agents (full isolation via git worktrees + separate infra).'
todos:
  - id: s1-scaffold
    content: "Stage 1: Create .vienna/ directory structure, vienna.sh CLI entry point, lib/ shell modules, config.yaml, .gitignore entries"
    status: pending
  - id: s1-ports
    content: "Stage 1: Implement port registry — allocate unique infra ports (PG x2, Redis) + backend ports (NestJS, Go) per instance"
    status: pending
  - id: s1-docker
    content: "Stage 1: Create docker-compose.base.yaml (parameterized Postgres x2 + Redis) and infra.sh to start/stop/destroy Docker infra"
    status: pending
  - id: s1-worktree
    content: "Stage 1: Implement worktree.sh — create and remove git worktrees across all 4 repos for a given branch"
    status: pending
  - id: s1-templates
    content: "Stage 1: Create .env templates for commenda-logical-backend, sales-tax-api-2, commenda/packages/prisma + env.sh renderer"
    status: pending
  - id: s1-migrate
    content: "Stage 1: Implement migrate.sh — run Prisma migrate deploy + Atlas migrate apply against the instance's databases"
    status: pending
  - id: s1-spawn
    content: "Stage 1: Implement `vienna spawn <name> --branch <branch>` — full flow: worktrees, Docker up, migrate, env gen, marker file"
    status: pending
  - id: s1-destroy
    content: "Stage 1: Implement `vienna destroy <name>` — remove worktrees, stop and remove Docker containers + volumes, free ports"
    status: pending
  - id: s1-list
    content: "Stage 1: Implement `vienna list` — show all instances with name, branch, status, ports, age"
    status: pending
  - id: s2-switch
    content: "Stage 2: Implement `vienna switch <branch>` — human mode with infra-only isolation (no worktrees, shared checkout)"
    status: pending
  - id: s2-stop-start
    content: "Stage 2: Implement `vienna stop` / `vienna start` — pause and resume instance containers"
    status: pending
  - id: s2-status
    content: "Stage 2: Implement `vienna status` — detailed view of current instance (ports, migration state, running services)"
    status: pending
  - id: s2-ports-cmd
    content: "Stage 2: Implement `vienna ports` — full port map across all instances with availability"
    status: pending
  - id: s2-run
    content: "Stage 2: Implement `vienna run <app>` — dynamic frontend app port claiming and startup"
    status: pending
  - id: s3-snapshots
    content: "Stage 3: Implement `vienna snapshot` / `vienna restore` using pg_dump/pg_restore"
    status: pending
  - id: s3-gc
    content: "Stage 3: Implement `vienna gc` — garbage collect stale instances older than threshold"
    status: pending
  - id: s3-reset
    content: "Stage 3: Implement `vienna reset` — drop databases, recreate, re-apply all migrations"
    status: pending
  - id: s3-polish
    content: "Stage 3: Health checks (wait for PG healthy), colored output, auto-branch-detection, worktree conflict warnings"
    status: pending
  - id: s4-linear
    content: "Stage 4: Linear API integration — `vienna spawn --ticket LIN-XXXX` fetches ticket, derives name/branch/context"
    status: pending
  - id: s4-cursor
    content: "Stage 4: Auto-generate .cursor/rules/task.mdc in spawned instances and launch Cursor window"
    status: pending
  - id: s4-remote
    content: "Stage 4: Remote VM provisioning and Linear webhook listener for autonomous agent spawning"
    status: pending
isProject: false
---

# Vienna: Branch-Aware Isolated Environment Manager

## 1. Core Concept — The Instance Model

The fundamental unit is an **instance**, not a branch. An instance is a complete, isolated runtime environment:

- Its own PostgreSQL database for NestJS/Prisma (from `commenda-logical-backend`)
- Its own PostgreSQL database for Go/sqlc (from `sales-tax-api-2`)
- Its own Redis
- Its own allocated ports (including service ports, not just infra)
- Its own generated `.env` files
- Optionally, its own code checkout (for parallel agents)

**A branch can have multiple instances** — this is critical for parallelization. Two agents can both work on `main` with completely separate environments.

## 2. Two Operational Modes

### Mode A: `vienna switch <branch>` — Human Developer

- **Code**: Checks out `<branch>` in the existing repo directories (same working tree)
- **Infra**: Creates/resumes a Docker infrastructure set namespaced to `<branch>`
- **Env**: Generates `.env` files in each repo pointing to the instance's ports
- **State**: Writes to `.vienna/current` so all terminals share the same context
- **Constraint**: Only one "switched" instance active at a time (though containers keep running)

### Mode B: `vienna spawn <name> --branch <branch>` — Parallel Agent

- **Code**: Creates `git worktree` for each of the 4 repos in `Vienna/instances/<name>/`
- **Infra**: Creates a new Docker infrastructure set namespaced to `<name>`
- **Env**: Generates `.env` files inside the worktree directories
- **State**: Writes `.vienna-instance.json` marker in the instance root
- **Constraint**: None — unlimited concurrent spawns (limited by system resources)

```mermaid
flowchart TB
    subgraph humanMode [Mode A: vienna switch]
        switchCmd["vienna switch feature-auth"] --> checkBranch[Check out branch in all repos]
        checkBranch --> checkExisting{Existing instance?}
        checkExisting -->|Yes| offerChoice[Resume or Recreate?]
        checkExisting -->|No| createInfra[Create Docker infra]
        offerChoice -->|Resume| startContainers[Start existing containers]
        offerChoice -->|Recreate| destroyOld[Destroy + Create fresh]
        createInfra --> applyMigrations[Apply migrations]
        startContainers --> genEnv[Generate .env files]
        destroyOld --> applyMigrations
        applyMigrations --> genEnv
        genEnv --> writeCurrent["Write .vienna/current"]
        writeCurrent --> ready1[Ready - all terminals share context]
    end

    subgraph agentMode [Mode B: vienna spawn]
        spawnCmd["vienna spawn agent-1 --branch fix-tax"] --> createWorktrees[Create git worktrees]
        createWorktrees --> allocPorts[Allocate unique ports]
        allocPorts --> createInfra2[Create Docker infra]
        createInfra2 --> applyMig2[Apply migrations]
        applyMig2 --> genEnv2[Generate .env in worktree dirs]
        genEnv2 --> writeMarker["Write .vienna-instance.json"]
        writeMarker --> ready2["Ready - cd instances/agent-1/ to work"]
    end
```

## 3. Instance Context Detection

Every `vienna` command needs to know which instance it's operating on. Detection order (similar to how `git` finds `.git`):

1. `**VIENNA_INSTANCE` env var — explicit override, highest priority
2. **Walk up from `cwd**`— look for`.vienna-instance.json` marker file (spawned instances)
3. **Read `.vienna/current**` — the globally "switched" instance (human mode)
4. **Error** — "No active instance"

This means:

- An agent that `cd`s into `Vienna/instances/agent-1/commenda-logical-backend/` automatically resolves to `agent-1`
- A human developer in `Vienna/commenda-logical-backend/` resolves to whatever was last `switch`ed
- Two terminals in different instance directories work independently with zero coordination

## 4. Directory Structure

```
Vienna/
├── .vienna/                              # git-tracked (team shares this)
│   ├── vienna.sh                         # Main CLI entry point
│   ├── lib/                              # Shell library modules
│   │   ├── switch.sh                     # `vienna switch` logic
│   │   ├── spawn.sh                      # `vienna spawn` logic
│   │   ├── infra.sh                      # Docker Compose orchestration
│   │   ├── migrate.sh                    # Prisma + Atlas migration runner
│   │   ├── env.sh                        # .env template rendering
│   │   ├── ports.sh                      # Port allocation / registry
│   │   ├── context.sh                    # Instance context detection
│   │   ├── worktree.sh                   # Git worktree management
│   │   └── utils.sh                      # Colors, logging, common helpers
│   ├── docker/
│   │   └── docker-compose.base.yaml      # Postgres x2 + Redis template
│   ├── templates/                         # .env templates with placeholders
│   │   ├── commenda-logical-backend.env.tmpl
│   │   ├── sales-tax-api-2.env.tmpl
│   │   └── commenda-prisma.env.tmpl
│   └── config.yaml                        # Global settings (port ranges, defaults)
│
├── .vienna-state/                         # gitignored — local runtime state
│   ├── current                            # Currently "switched" instance name
│   ├── registry.json                      # Port allocation registry
│   └── instances/                         # Per-instance state
│       ├── main/
│       │   └── config.json                # Ports, creation time, branch, mode
│       └── agent-1/
│           └── config.json
│
├── instances/                             # gitignored — spawned worktrees live here
│   └── agent-1/
│       ├── .vienna-instance.json          # Marker file (instance name, config path)
│       ├── commenda/                      # git worktree
│       ├── commenda-logical-backend/      # git worktree
│       ├── sales-tax-api-2/              # git worktree
│       └── sales-tax-connectors/         # git worktree
│
├── commenda/                              # Original repos (used by `switch` mode)
├── commenda-logical-backend/
├── sales-tax-api-2/
└── sales-tax-connectors/
```

Key separation: `.vienna/` is git-tracked (templates, docker configs, the CLI itself), while `.vienna-state/` and `instances/` are gitignored (runtime state, worktrees).

## 5. Unified Port Registry (Cross-Instance + Within-Instance)

There are two port allocation problems, and the registry solves both:

**Problem A (cross-instance):** Two instances must not collide on infrastructure ports.
**Problem B (within-instance):** A developer running 3 of 8 frontend apps needs to know which ports are available for the next app they start.

### Design: Two-Tier Port Allocation

**Tier 1 — Reserved ports (auto-allocated when instance is created):**
These are infrastructure and backend services that MUST be running and whose ports other services depend on (e.g., `NEXT_PUBLIC_SERVER_URL` needs to know the NestJS port).

Each instance gets a unique offset. For instance with offset N:

- Postgres (NestJS/Prisma): **5500 + N** (maps to container 5432)
- Postgres (Go/Atlas): **5600 + N** (maps to container 5432)
- Redis: **6400 + N** (maps to container 6379)
- NestJS backend: **8100 + N** (for `nest start`)
- Go API: **8200 + N** (for `tax-api serve`)

These are written into the instance's config at creation time and never change.

**Tier 2 — App port pool (claimed dynamically when a frontend app starts):**
Each instance gets a block of 10 ports for frontend apps: **3000 + (N 10)** through **3000 + (N 10) + 9**.

So instance offset 1 gets ports 3010-3019, offset 2 gets 3020-3029, etc.

Within that block, ports are claimed on-demand:

- `vienna run enterprise` — claims 3010, starts `next dev -p 3010`
- `vienna run admin` — claims 3011, starts `next dev -p 3011`
- `vienna run agent` — claims 3012
- `vienna ports` — shows 3013-3019 still available in this instance

If you don't use `vienna run`, you can manually check: `vienna ports --available` shows free ports you can pass to `next dev -p <port>` yourself.

### Registry Format (`.vienna-state/registry.json`)

```json
{
  "next_offset": 3,
  "instances": {
    "main": {
      "offset": 1,
      "created": "2026-02-18T10:00:00Z",
      "mode": "switch",
      "branch": "main",
      "reserved": {
        "pg_nestjs": 5501,
        "pg_go": 5601,
        "redis": 6401,
        "nestjs": 8101,
        "go_api": 8201
      },
      "app_pool": {
        "range": [3010, 3019],
        "claimed": {
          "3010": { "app": "enterprise", "pid": 12345 },
          "3011": { "app": "admin", "pid": 12346 }
        }
      }
    },
    "lin-4521": {
      "offset": 2,
      "created": "2026-02-18T11:00:00Z",
      "mode": "spawn",
      "branch": "fix-filing-calc",
      "reserved": {
        "pg_nestjs": 5502,
        "pg_go": 5602,
        "redis": 6402,
        "nestjs": 8102,
        "go_api": 8202
      },
      "app_pool": {
        "range": [3020, 3029],
        "claimed": {}
      }
    }
  },
  "freed_offsets": []
}
```

When an instance is destroyed, its offset goes into `freed_offsets` for reuse.

### `vienna ports` Output

```
$ vienna ports

INSTANCE     SERVICE           PORT    STATUS
main         postgres-nestjs   5501    running
main         postgres-go       5601    running
main         redis             6401    running
main         nestjs-backend    8101    listening
main         go-api            8201    listening
main         enterprise        3010    listening (pid 12345)
main         admin             3011    listening (pid 12346)
main         (available)       3012-3019
lin-4521     postgres-nestjs   5502    running
lin-4521     postgres-go       5602    running
lin-4521     redis             6402    running
lin-4521     nestjs-backend    8102    not started
lin-4521     go-api            8202    not started
lin-4521     (available)       3020-3029
```

### `vienna run <app>` — App Launcher

Rather than manually figuring out ports:

```
$ vienna run enterprise

  Starting enterprise on port 3010...
  Running: cd commenda/apps/enterprise && next dev -p 3010
  NEXT_PUBLIC_SERVER_URL=http://localhost:8101/api/v1
```

This claims a port from the pool, sets the right env vars (including pointing to this instance's backend), and starts the app. The PID is tracked so `vienna ports` can show live status and `vienna stop enterprise` can kill it.

## 6. Docker Infrastructure

A single `docker-compose.base.yaml` parameterized with environment variables, invoked with `-p vienna-<instance>`:

```yaml
# .vienna/docker/docker-compose.base.yaml
services:
  postgres-nestjs:
    image: postgres:15
    ports: ["${VIENNA_PG_NESTJS_PORT}:5432"]
    environment:
      POSTGRES_DB: commenda
      POSTGRES_USER: commenda
      POSTGRES_PASSWORD: commenda
    volumes: [pg-nestjs-data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U commenda"]
      interval: 3s
      retries: 10

  postgres-go:
    image: postgres:15
    ports: ["${VIENNA_PG_GO_PORT}:5432"]
    environment:
      POSTGRES_DB: salestax
      POSTGRES_USER: salestax
      POSTGRES_PASSWORD: salestax
    volumes: [pg-go-data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U salestax"]
      interval: 3s
      retries: 10

  redis:
    image: redis:7-alpine
    ports: ["${VIENNA_REDIS_PORT}:6379"]
    volumes: [redis-data:/data]

volumes:
  pg-nestjs-data:
  pg-go-data:
  redis-data:
```

Invoked as: `VIENNA_PG_NESTJS_PORT=5501 VIENNA_PG_GO_PORT=5601 VIENNA_REDIS_PORT=6401 docker compose -p vienna-main -f .vienna/docker/docker-compose.base.yaml up -d`

The `-p vienna-main` project name means all containers and volumes are namespaced: `vienna-main-postgres-nestjs-1`, volume `vienna-main_pg-nestjs-data`, etc. Fully isolated.

## 7. Environment Template System

Templates use simple `{{PLACEHOLDER}}` syntax, rendered by the CLI using `sed`:

```bash
# .vienna/templates/commenda-logical-backend.env.tmpl
DATABASE_URL=postgresql://commenda:commenda@localhost:{{PG_NESTJS_PORT}}/commenda
REDIS_CONNECTION_HOST=localhost
REDIS_CONNECTION_PORT={{REDIS_PORT}}
SALES_TAX_CLIENT_API_KEY=local-dev-key
PORT={{NESTJS_PORT}}
# ... other vars copied from current .env with infra-specific values replaced
```

```bash
# .vienna/templates/sales-tax-api-2.env.tmpl
DATABASE_URL=postgresql://salestax:salestax@localhost:{{PG_GO_PORT}}/salestax
COMMENDA_LOGICAL_BACKEND_URL=http://localhost:{{NESTJS_PORT}}/api/v1
PORT={{GO_API_PORT}}
REDIS_URL=redis://localhost:{{REDIS_PORT}}
```

The render function replaces placeholders with the instance's allocated ports:

- For `switch` mode: writes to `Vienna/commenda-logical-backend/.env`, `Vienna/sales-tax-api-2/.env`
- For `spawn` mode: writes to `Vienna/instances/<name>/commenda-logical-backend/.env`, etc.

## 8. Migration Handling

After infrastructure is up and healthy:

1. **NestJS/Prisma** — `npx prisma migrate deploy` (applies pending migrations without interactive prompts, production-safe). Leverages existing setup in [commenda-logical-backend/prisma/migrations/](commenda-logical-backend/prisma/migrations/).
2. **Go/Atlas** — `atlas migrate apply --dir file://database/migrations --url $DATABASE_URL`. Leverages existing [sales-tax-api-2/scripts/apply.sh](sales-tax-api-2/scripts/apply.sh).

Both commands are idempotent — safe to run repeatedly. They track which migrations have been applied and only run new ones.

## 9. Git Worktrees — How Code Isolation and Push Work

A git worktree is NOT a clone. It's an additional working directory linked to the **same** `.git` repository. This is important for understanding why push works:

```
Vienna/
├── commenda/                     # Main working tree (.git lives here)
│   └── .git/                     # The actual repository
├── instances/
│   ├── lin-4521/
│   │   └── commenda/             # Worktree — shares commenda/.git
│   └── lin-4522/
│       └── commenda/             # Another worktree — same .git
```

**Key properties:**

- All worktrees share the same `.git` (remotes, history, reflog)
- `git commit` + `git push` from a worktree works identically to the main checkout — same remote, same auth
- An agent in `instances/lin-4521/commenda/` can commit, push, and create PRs normally
- **Constraint enforced by Git**: Two worktrees cannot be on the same branch simultaneously. This is actually desirable — it prevents two agents from stomping on the same branch.

**Since there are 4 separate repos**, each repo's worktrees are independent:

- `vienna spawn lin-4521 --branch fix-filing` creates 4 worktrees:
  - `instances/lin-4521/commenda/` → worktree of `commenda/.git` on branch `fix-filing`
  - `instances/lin-4521/commenda-logical-backend/` → worktree of `commenda-logical-backend/.git` on `fix-filing`
  - `instances/lin-4521/sales-tax-api-2/` → worktree of `sales-tax-api-2/.git` on `fix-filing`
  - `instances/lin-4521/sales-tax-connectors/` → worktree of `sales-tax-connectors/.git` on `main` (if branch doesn't exist there)

**What happens when the agent is done:**

1. Agent commits and pushes from the worktree — goes to the same remote as always
2. Agent (or human) creates a PR
3. `vienna destroy lin-4521` removes the worktrees (via `git worktree remove`) and Docker containers
4. The branch and commits still exist on the remote — nothing is lost

## 10. Agent Context — How AI Agents Get Task Instructions

### The Problem

`vienna spawn agent-1 --branch fix-tax` creates an isolated environment, but the name `agent-1` is meaningless. An AI agent needs to know: **what am I supposed to work on?**

### The Solution: Task Context File + Cursor Integration

When `vienna spawn` is called, it creates a task context file that AI agents (Cursor, Claude CLI, etc.) automatically pick up.

### Flow: `vienna spawn --ticket LIN-4521`

```mermaid
flowchart LR
    cmd["vienna spawn --ticket LIN-4521"] --> fetchLinear["Fetch ticket from Linear API"]
    fetchLinear --> createInstance["Create instance 'lin-4521'"]
    createInstance --> writeContext["Write task context files"]
    writeContext --> openCursor["Open Cursor window at instance dir"]
    openCursor --> agentReads["Cursor agent reads .cursor/rules/task.mdc"]
    agentReads --> agentWorks["Agent understands the task and starts working"]
```

**Step 1: Fetch ticket (if `--ticket` flag used)**

```bash
vienna spawn --ticket LIN-4521
# Calls Linear API: GET /issues/LIN-4521
# Extracts: title, description, labels, priority, acceptance criteria
# Instance name auto-derived: "lin-4521"
# Branch name auto-derived: "lin-4521-fix-filing-calculation"
```

**Step 2: Write task context into the instance**

Two files are created in the instance root:

1. `.cursor/rules/task.mdc` — Cursor-native rules file so the Cursor agent automatically gets task context:

```markdown
---
description: Task context for this development instance
alwaysApply: true
---

# Task: Fix filing calculation for multi-state corporations

**Ticket:** LIN-4521
**Branch:** lin-4521-fix-filing-calculation
**Priority:** High

## Description

The filing calculation is double-counting tax for corporations registered
in multiple states when they have overlapping jurisdiction boundaries...

## Acceptance Criteria

- Filing totals match expected values for multi-state corps
- Existing single-state filing calculations are not affected
- Add test coverage for the multi-state edge case

## Instance Info

- NestJS backend: http://localhost:8102
- Go API: http://localhost:8202
- Postgres (NestJS): localhost:5502
- Postgres (Go): localhost:5602
```

1. `.vienna-task.json` — Machine-readable context for any agent:

```json
{
  "ticket": "LIN-4521",
  "title": "Fix filing calculation for multi-state corporations",
  "description": "...",
  "branch": "lin-4521-fix-filing-calculation",
  "priority": "high",
  "labels": ["bug", "sales-tax"],
  "ports": { "nestjs": 8102, "go_api": 8202, "pg_nestjs": 5502, "pg_go": 5602 }
}
```

**Step 3: Open Cursor window**

```bash
cursor "Vienna/instances/lin-4521/"
```

This opens a new Cursor window rooted at the instance directory. The Cursor agent in that window:

- Automatically loads `.cursor/rules/task.mdc` (Cursor's native rules system)
- Knows what ticket it's working on, what the bug is, what the acceptance criteria are
- Knows which ports to use for testing
- Works in the isolated worktree — all file edits are scoped to this instance

**The developer can see this Cursor window** in their window list, switch to it, observe what the agent is doing, provide guidance via chat, and approve/reject changes.

### Manual spawn (without Linear)

For cases where you don't have a Linear ticket:

```bash
vienna spawn fix-flaky-test --branch fix-flaky-test --context "The test in sales-tax-api-2/integration-tests/filing_test.go is flaky because it depends on timestamp ordering. Make it deterministic."
```

The `--context` flag gets written into the same task files. Or omit it entirely for a bare instance with no AI context.

### Naming Convention

Since the instance name is derived from the ticket:

- `vienna spawn --ticket LIN-4521` → instance name `lin-4521`, branch `lin-4521-fix-filing-calculation`
- `vienna spawn --ticket LIN-4522` → instance name `lin-4522`, branch `lin-4522-add-nexus-rules`

No more meaningless `agent-1`, `agent-2`. Every instance is tied to a task.

### Future: Fully Automated (No Human in the Loop)

```
Linear webhook (ticket created with "auto-agent" label)
  → Vienna orchestrator receives webhook
  → vienna spawn --ticket LIN-4521 --auto
  → Instance created, Cursor/Claude agent launched
  → Agent works autonomously
  → Agent creates PR, links to ticket
  → vienna destroy lin-4521 (or keep for review)
```

## 12. Parallelization Model — The Full Picture

```mermaid
flowchart LR
    subgraph cursor1 [Cursor Window: lin-4521]
        t1cmd["Agent reads .cursor/rules/task.mdc\nKnows: fix filing calc bug\nWorks in instances/lin-4521/"]
    end
    subgraph cursor2 [Cursor Window: lin-4522]
        t2cmd["Agent reads .cursor/rules/task.mdc\nKnows: add nexus rules\nWorks in instances/lin-4522/"]
    end
    subgraph humanTerm [Human Developer Terminal]
        t3cmd["vienna switch main\nWorks in Vienna/commenda-*"]
    end

    subgraph docker [Docker Containers]
        subgraph proj1 ["vienna-lin-4521"]
            pg1a["PG :5501"]
            pg1b["PG :5601"]
            r1["Redis :6401"]
        end
        subgraph proj2 ["vienna-lin-4522"]
            pg2a["PG :5502"]
            pg2b["PG :5602"]
            r2["Redis :6402"]
        end
        subgraph proj3 ["vienna-main"]
            pg3a["PG :5503"]
            pg3b["PG :5603"]
            r3["Redis :6403"]
        end
    end

    t1cmd --> proj1
    t2cmd --> proj2
    t3cmd --> proj3
```

**Concrete scenario — 2 AI agents + 1 human, simultaneously:**

1. Human: `vienna spawn --ticket LIN-4521` → Cursor window opens at `instances/lin-4521/`, agent reads task context, starts working on filing calc bug
2. Human: `vienna spawn --ticket LIN-4522` → Second Cursor window opens at `instances/lin-4522/`, different agent works on nexus rules
3. Human: `vienna switch main` → Their own terminals now point to `main` instance, they debug something manually
4. All three work simultaneously. Different code checkouts. Different databases. Different ports. Zero conflicts.
5. Agent in window 1 finishes → commits, pushes, creates PR. Human reviews it in Cursor.
6. `vienna destroy lin-4521` cleans up.

**Why this works:**

- **Code**: Git worktrees give each agent its own filesystem. Two agents editing the same file in different worktrees don't conflict.
- **Data**: Docker Compose project names give each agent its own Postgres volumes. Migrations in one instance don't affect another.
- **Ports**: The unified port registry ensures no collisions, even if all three instances run full service stacks.
- **Context**: `.cursor/rules/task.mdc` gives each Cursor agent its task instructions without manual copy-pasting.
- **Push**: Worktrees share the same git remote, so push/PR creation works identically to a normal checkout.

## 13. CLI Command Reference

```
# Instance lifecycle
vienna spawn --ticket LIN-4521    Agent mode: fetch ticket, worktree, infra, migrate, open Cursor
vienna spawn <name> --branch <b>  Agent mode (manual): worktree + infra + migrate + env
  [--context "description"]         Optional task context
vienna switch <branch>            Human mode: checkout + infra + migrate + env
vienna destroy <name>             Tear down instance (containers + volumes + worktree)
vienna list                       Show all instances with status, ports, branch, age
vienna status                     Show current instance details

# Infrastructure control
vienna stop [name]                Stop Docker containers (preserve volumes/data)
vienna start [name]               Restart stopped containers
vienna migrate                    Apply pending migrations for current instance
vienna reset                      Drop databases, recreate, re-apply all migrations
vienna env                        Regenerate .env files for current instance

# Port management
vienna ports                      Show full port map across all instances
vienna ports --available          Show free ports for current instance
vienna run <app>                  Start a frontend app on next available port

# Maintenance
vienna gc [--older-than 7d]       Destroy instances older than threshold
vienna snapshot <label>           pg_dump both databases to named snapshot
vienna restore <label>            Restore databases from snapshot
vienna exec <name> -- <cmd>       Run command in an instance's context
```

## 14. The `vienna` Script Entry Point

The main `vienna` script is a thin dispatcher:

```bash
#!/usr/bin/env bash
VIENNA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIENNA_DIR="$VIENNA_ROOT/.vienna"
VIENNA_STATE="$VIENNA_ROOT/.vienna-state"
source "$VIENNA_DIR/lib/utils.sh"
source "$VIENNA_DIR/lib/context.sh"

command="${1:-help}"
shift || true

case "$command" in
    switch)   source "$VIENNA_DIR/lib/switch.sh";   cmd_switch "$@" ;;
    spawn)    source "$VIENNA_DIR/lib/spawn.sh";     cmd_spawn "$@" ;;
    destroy)  source "$VIENNA_DIR/lib/infra.sh";     cmd_destroy "$@" ;;
    list)     source "$VIENNA_DIR/lib/infra.sh";     cmd_list "$@" ;;
    # ... etc
    *)        show_help ;;
esac
```

Installed via symlink: `ln -s .vienna/vienna.sh /usr/local/bin/vienna` (or added to PATH).

## 15. Implementation Stages

### Stage 1 — Spawn + Worktree + Isolated Environment (MVP)

The core loop. After this stage, you can spawn a fully isolated environment for any branch and destroy it when done. This is the foundation everything else builds on.

**What you can do after Stage 1:**
```
vienna spawn my-feature --branch feature-auth    # Create isolated env
cd instances/my-feature/commenda-logical-backend  # Work in the worktree
vienna list                                       # See all instances
vienna destroy my-feature                         # Clean up
```

**What gets built:**
- `.vienna/` directory scaffold — CLI entry point (`vienna.sh`), shell library modules (`lib/`), config, `.gitignore`
- Port registry — allocate unique ports (PG x2, Redis, NestJS, Go API) per instance, track in `registry.json`
- Docker infrastructure — `docker-compose.base.yaml` (parameterized Postgres x2 + Redis), `infra.sh` to manage lifecycle
- Git worktree management — `worktree.sh` to create/remove worktrees for all 4 repos on a given branch
- Env template system — `.env.tmpl` files for each repo, `env.sh` to render them with instance-specific ports
- Migration runner — `migrate.sh` to run Prisma migrate deploy + Atlas migrate apply against the instance's databases
- `vienna spawn <name> --branch <branch>` — the full flow: create worktrees, start Docker, wait for healthy DBs, apply migrations, generate `.env` files, write marker file
- `vienna destroy <name>` — remove worktrees, stop Docker containers, delete volumes, free ports
- `vienna list` — show all instances with name, branch, status, ports, age

### Stage 2 — Human Developer Mode + Port Visibility

Adds the lighter-weight `switch` mode for human developers who don't need separate code checkouts, plus port management commands.

**What you can do after Stage 2:**
```
vienna switch main                 # Infra-only isolation, same code checkout
vienna switch feature-auth         # Switch to another branch, main's DB preserved
vienna stop main                   # Pause containers to save resources
vienna start main                  # Resume
vienna status                      # Detailed view of current instance
vienna ports                       # Full port map across all instances
vienna run enterprise              # Start frontend on next available port
```

**What gets built:**
- `vienna switch <branch>` — git checkout in all repos, infra up, migrate, env gen, write `.vienna-state/current`
- `vienna stop [name]` / `vienna start [name]` — pause and resume Docker containers (data preserved)
- `vienna status` — detailed info: ports, migration state, running containers, branch
- `vienna ports` — full port map across all instances (reserved, in-use, available)
- `vienna run <app>` — claim a port from the app pool, start a frontend app with correct env vars

### Stage 3 — Reliability + Maintenance

Makes the tool production-grade for daily use: snapshots, garbage collection, health checks, polished output.

**What you can do after Stage 3:**
```
vienna snapshot before-risky-change   # Save database state
vienna restore before-risky-change    # Roll back if things break
vienna reset                          # Full wipe + re-migrate
vienna gc --older-than 7d             # Clean up stale instances
```

**What gets built:**
- `vienna snapshot <label>` / `vienna restore <label>` — pg_dump/pg_restore both databases to named snapshots
- `vienna gc [--older-than 7d]` — destroy instances older than a threshold
- `vienna reset` — drop and recreate databases, re-apply all migrations from scratch
- Health checks — wait for Postgres to be healthy before running migrations (prevents race conditions)
- Colored output and progress indicators
- Auto-detection of which repos have the target branch (gracefully skip repos that don't)
- Worktree branch conflict warnings (if a branch is already checked out in another instance)

### Stage 4 — AI Agent + Linear Integration

The automation layer. AI agents get task context automatically, and Linear tickets can trigger environment creation.

**What you can do after Stage 4:**
```
vienna spawn --ticket LIN-4521       # Fetch ticket, create branch, inject context
# Cursor window opens with task instructions loaded
```

**What gets built:**
- Linear API integration — `--ticket LIN-XXXX` flag on spawn: fetch title, description, acceptance criteria
- Auto-generate `.cursor/rules/task.mdc` in spawned instances so Cursor agents get task context
- Launch Cursor window at instance directory via `cursor` CLI
- `--context "description"` flag for manual context injection without Linear
- Future: remote VM provisioning (`--remote` flag)
- Future: Linear webhook listener for fully autonomous agent spawning

## 16. Open Design Questions

- **Shared secrets**: Some env vars are actual secrets (API keys, Clerk keys). The template system should have a "passthrough" layer: a gitignored `.vienna-state/secrets.env` file that users populate once with their keys. Templates reference `{{SECRET_CLERK_KEY}}` which pulls from this file. This way infrastructure vars are templated per-instance, but secrets are shared across instances.
- **Service startup**: `vienna switch` and `vienna spawn` should only start infrastructure (Postgres, Redis) and apply migrations. Starting application services (NestJS, Go API, frontends) should be explicit via `vienna run <service>` — developers and agents may want to start services with specific flags or in debug mode.
- **Concurrency during switch**: When a human runs `vienna switch main`, the previous instance's containers should keep running (they're on different ports, so no conflict). Only `vienna stop <name>` or `vienna destroy <name>` should stop them. This lets you switch quickly without waiting for containers to restart.
- **Worktree branch conflict**: If an agent is spawned on branch `fix-filing` and the human tries to `vienna switch fix-filing`, git will refuse (can't have two worktrees on the same branch). The CLI should detect this and suggest: "Branch fix-filing is in use by instance lin-4521. Switch to that instance instead?"
