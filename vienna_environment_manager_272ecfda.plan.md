---
name: Vienna Environment Manager
overview: >
  Shell-based CLI that creates fully isolated development environments — separate databases, queues,
  ports, code checkouts — for every ticket you work on. Pass a Linear ticket and it spawns the whole
  stack, starts all services, and opens an AI agent in Cursor that starts solving immediately.
---

# Vienna — Implementation Plan

## Stage 1: Core Environment Isolation (COMPLETED)

Everything needed to create, manage, and destroy fully isolated development environments.

### Implemented

- [x] **CLI scaffold** — `bin/vienna.sh` entry point, `lib/` shell modules, `install.sh` symlink installer
- [x] **Configuration** — `lib/config.sh` with repo list, port base ranges, Docker image versions, database creds, AWS/LocalStack settings, SQS queue definitions
- [x] **Port registry** — `lib/ports.sh` allocates unique port offsets per instance in `.vienna-state/registry.json`, reuses freed offsets on destroy
- [x] **Docker infrastructure** — `docker/docker-compose.base.yaml` with PostgreSQL x2 + Redis + LocalStack, `lib/infra.sh` for start/stop/destroy lifecycle
- [x] **LocalStack integration** — `docker/init-localstack.sh` creates 3 S3 buckets and 22 SQS queues (21 standard + 1 FIFO) per instance, namespaced by instance name
- [x] **Git worktree management** — `lib/worktree.sh` creates/removes worktrees for all 3 repos (commenda, commenda-logical-backend, sales-tax-api-2) on a given branch
- [x] **Environment generation** — `lib/env.sh` copies base `.env` files and overrides instance-specific vars (DB URLs, Redis, SQS queue URLs, ports); patches `backend.config.ts` for NestJS service-to-service URLs
- [x] **Migration runner** — `lib/migrate.sh` runs Prisma migrations for NestJS, Atlas migrations for Go service, seeds admin API token
- [x] **File overlays** — `overlays/` directory with patches applied to worktrees (e.g., S3 LocalStack compatibility for sales-tax-api-2)
- [x] **Dependency installation** — `lib/deps.sh` runs `npm install` (CLB), `pnpm install` + `prisma generate` (commenda monorepo), `go mod download` (Go service)
- [x] **`vienna spawn <name> --branch <branch>`** — full flow: allocate ports → create worktrees → apply overlays → start Docker → generate .env → install deps → run migrations
- [x] **`vienna destroy <name>`** — remove worktrees, stop/remove Docker containers + volumes, free ports, remove state
- [x] **`vienna list`** — table showing all instances with name, branch, Docker status, ports
- [x] **`vienna info [name]`** — detailed view: ports, DB URLs, Redis, LocalStack, psql commands, backend URLs; auto-detects instance from cwd
- [x] **`vienna stop [name]`** — pause Docker containers (data preserved)
- [x] **`vienna start [name]`** — resume stopped containers
- [x] **`vienna run [name]`** — start CLB, Sales Tax API, and Enterprise frontend in new terminal tabs (detects Cursor/VS Code/iTerm2/Terminal.app)
- [x] **Instance context detection** — `lib/context.sh` resolves instance from `VIENNA_INSTANCE` env var, `.vienna-instance.json` marker, or `.vienna-state/current`
- [x] **Utilities** — `lib/utils.sh` with color codes, logging helpers, name sanitizer, prereq checks (jq, Docker)
- [x] **Testing docs** — `TESTING.md` with prerequisites, command reference, smoke test, full scenarios

### Commands available after Stage 1

```
vienna spawn my-feature --branch feature-auth   # Create fully isolated environment
vienna list                                      # See all instances
vienna info my-feature                           # Ports, DB URLs, connection details
vienna run my-feature                            # Start CLB + Sales Tax + Enterprise
vienna stop my-feature                           # Pause containers (keep data)
vienna start my-feature                          # Resume
vienna destroy my-feature                        # Tear down everything
```

---

## Stage 2: Linear Ticket Integration + AI Agent Spawning (COMPLETED)

Connects Vienna to Linear and Cursor so that a single command fetches a ticket, creates the environment, starts all services, and opens an AI agent that begins solving.

### Implemented

- [x] **Linear API module** — `lib/linear.sh` with GraphQL queries to fetch ticket details (title, description, priority, labels, assignee, comments, suggested branch name)
- [x] **Secrets management** — `VIENNA_LINEAR_API_KEY` loaded from gitignored `.vienna-state/secrets.env`
- [x] **Ticket parsing** — accepts ticket ID (`PLAT-2086`) or full Linear URL (`https://linear.app/commenda/issue/PLAT-2086/...`)
- [x] **Auto-derived instance name** — lowercased ticket ID becomes instance name (e.g., `PLAT-2086` → `plat-2086`)
- [x] **Auto-derived branch name** — uses Linear's suggested branch name, falls back to slugified `<id>-<title>`
- [x] **Base branch support** — `--branch` flag specifies the base to create the ticket branch from (defaults to `main`)
- [x] **Task context generation** — `linear_write_task_context` writes two files:
  - `.cursor/rules/task.mdc` — Cursor-native rules file with workspace boundary instructions, ticket details, instance ports
  - `.vienna-task.json` — machine-readable JSON summary
- [x] **Workspace boundary enforcement** — task.mdc starts with hard rules: "you MUST NOT read/edit/create files outside this instance", "all migrations MUST target this instance's databases only"
- [x] **Auto-start services** — `vienna run` called automatically in ticket mode so CLB, Sales Tax, and Enterprise are running before the agent starts
- [x] **Cursor agent chat integration** — `linear_open_agent_chat` opens a new agent chat in the current Cursor window via AppleScript, pastes the ticket prompt, and sends it
- [x] **Hard isolation mode** — `--new-window` flag opens a separate Cursor window at the instance root instead of an agent chat tab
- [x] **`vienna spawn --ticket <ID-or-URL>`** — full flow: fetch ticket → derive name + branch → spawn environment → start services → open Cursor agent

### Commands available after Stage 2

```
vienna spawn --ticket PLAT-2086                  # Fetch ticket, spawn, start, open agent
vienna spawn --ticket PLAT-2086 --branch main    # Same, branching from main
vienna spawn --ticket PLAT-2086 --new-window     # Open in separate Cursor window
vienna spawn --ticket https://linear.app/...     # Works with full URLs too
```

---

## Stage 3: Human Developer Mode + Reliability (PLANNED)

Adds the lighter-weight `switch` mode for human developers who don't need separate code checkouts, plus snapshot/restore and maintenance features.

### Planned

- [ ] **`vienna switch <branch>`** — human developer mode: checkout branch in all repos (no worktrees), create/resume infra, generate .env, write `.vienna-state/current`
- [ ] **Snapshot/restore** — `vienna snapshot <label>` and `vienna restore <label>` using pg_dump/pg_restore for both databases
- [ ] **`vienna reset`** — drop databases, recreate, re-apply all migrations from scratch
- [ ] **`vienna gc [--older-than 7d]`** — garbage collect instances older than a threshold
- [ ] **`vienna ports`** — full port map across all instances with availability status
- [ ] **`--context` flag** — manual task context injection without Linear for plain spawns
- [ ] **Auto-branch detection** — gracefully skip repos that don't have the target branch
- [ ] **Worktree conflict warnings** — detect and warn when a branch is already checked out elsewhere

---

## Stage 4: Automation + Remote Environments (PLANNED)

Fully autonomous agent orchestration and cloud-based environments.

### Planned

- [ ] **Linear webhook listener** — label a ticket "auto-agent" in Linear, Vienna spawns an agent automatically
- [ ] **Remote VM provisioning** — `--remote` flag to create environments on cloud VMs instead of local machine
- [ ] **Agent orchestrator** — manage multiple concurrent agents, track their progress, auto-cleanup on PR merge
- [ ] **PR automation** — agent creates PR when done, links back to Linear ticket, updates status
- [ ] **Shareable environments** — export/import instance configs so team members can reproduce environments

---

## Architecture Summary

```
vienna/
├── bin/vienna.sh              # CLI entry point (dispatcher)
├── lib/
│   ├── config.sh              # Ports, repos, Docker images, DB creds, SQS queues
│   ├── context.sh             # Instance detection (env var → marker file → current)
│   ├── deps.sh                # npm/pnpm/go dependency installation
│   ├── destroy.sh             # Tear down instance
│   ├── env.sh                 # Generate .env files + patch backend.config.ts
│   ├── info.sh                # Show instance details
│   ├── infra.sh               # Docker Compose lifecycle
│   ├── linear.sh              # Linear API + Cursor agent integration
│   ├── list.sh                # List all instances
│   ├── migrate.sh             # Prisma + Atlas migrations + seeding
│   ├── ports.sh               # Port allocation registry
│   ├── run.sh                 # Start apps in terminal tabs
│   ├── spawn.sh               # Create isolated environment (core command)
│   ├── start.sh               # Resume stopped instance
│   ├── stop.sh                # Pause instance
│   ├── utils.sh               # Colors, logging, prereq checks
│   └── worktree.sh            # Git worktree management
├── docker/
│   ├── docker-compose.base.yaml   # PG x2 + Redis + LocalStack
│   └── init-localstack.sh         # Create S3 buckets + SQS queues
├── overlays/                  # File patches applied to worktrees
├── install.sh                 # Symlink installer
├── IDEA.md                    # Product vision
├── TESTING.md                 # Test scenarios and commands
└── README.md                  # Usage guide
```
