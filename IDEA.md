# Vienna

**One command. Your whole product, running locally, ready to use.**

Vienna lets anyone on your team — engineers, product managers, designers, QA — run the product on their own computer with a single command. No setup guides. No asking engineering for help. No waiting.

Need to test a new feature? One command. Need to switch to a different version to compare? One command. Need to go back to what you were looking at before? One command. Everything is saved, everything is restored, nothing breaks.

---

## The Problem Today

Getting the product running locally is painful. Here's what it looks like right now:

**For product managers and QA:**
You want to test a feature that's in progress. You ask an engineer to set it up on your machine. They're busy. You wait. When they finally help, it takes 30 minutes of terminal commands, configuration files, and troubleshooting. Next week, you need to test a different feature — same story.

**For engineers:**
You're working on Feature A. Your teammate asks you to quickly look at a bug on the main version. You can't just switch — your local setup has changes that are incompatible with the main version. Switching means undoing your work, reconfiguring everything, and hoping you can get back to where you were. It's a 20-minute detour that should take 20 seconds.

**For teams using AI coding agents:**
You want two AI agents to work on two different tasks simultaneously. They can't — they'd both be changing the same files, the same databases, the same configuration. One would overwrite the other. So they have to work one at a time, which defeats the purpose.

---

## How Vienna Fixes This

Vienna creates a separate, complete copy of your product's environment for every task or version you're working on. Each copy has its own databases, its own configuration, its own everything. They don't interfere with each other.

Think of it like browser tabs. Each tab is its own world. You can have five tabs open, switch between them instantly, and closing one doesn't affect the others. Vienna does the same thing, but for your entire product stack.

### Switch between versions instantly

```
vienna switch main
```

You're now running the main version. All your data, all your configuration — exactly as it should be for this version.

```
vienna switch feature-new-dashboard
```

Now you're running the new dashboard feature. The main version is paused in the background, untouched. Switch back anytime.

### Test any feature without help

A product manager wants to see the new onboarding flow that's being built:

```
vienna switch feature-new-onboarding
```

That's it. The full product starts up with the right version, the right data, and the right configuration. No Slack messages. No engineering time. No setup guide.

### Let AI agents work in parallel

```
vienna spawn --ticket LIN-4521
vienna spawn --ticket LIN-4522
```

Each ticket gets its own isolated workspace. An AI agent picks up the task, understands what needs to be done (pulled directly from the ticket), and works on it independently. Two agents working on two tickets at the same time, without stepping on each other.

---

## What Vienna Does

### One-Command Setup
Run a single command to get the full product running locally. Vienna handles all the behind-the-scenes complexity — databases, services, configuration — automatically.

### Instant Context Switching
Switch between different versions or feature branches without losing your place. Each version's state is preserved separately. Coming back to where you left off takes seconds, not minutes.

### No Engineering Bottleneck
Product managers, designers, and QA can test any in-progress feature themselves. No need to understand technical details. No need to ask an engineer for help. One command gets you a working product.

### Side-by-Side Comparison
Run multiple versions of the product at the same time. Compare the current version against a proposed change. Test two different features simultaneously. Each runs independently without conflicts.

### AI Agent Workspaces
Give each AI coding agent its own isolated workspace. The agent gets the task description, the code, and a fully working environment. Multiple agents work on different tasks in parallel — no conflicts, no overwriting, no waiting.

### Save and Restore
Take a snapshot of your current state at any point. Try something risky. If it doesn't work, restore back to where you were. Share a snapshot with a teammate so they can see exactly what you're seeing.

### Team-Ready
The configuration is shared across the team. When one person sets up the templates, everyone benefits. New team members get a working environment on their first day with one command.

---

## Day in the Life

**Sarah, Product Manager:**
Sarah needs to review a feature before the sprint demo. She opens her terminal, types `vienna switch feature-payment-redesign`, and the product starts up with the new payment flow. She tests it, finds an edge case, and files a bug. Total time: 3 minutes. Engineering time required: zero.

**Raj, Backend Engineer:**
Raj is building a new tax calculation feature. His manager pings him about a bug on the production version. He types `vienna switch main`, reproduces the bug, pushes a fix, and types `vienna switch feature-tax-calc` to go back to his feature. His database, his test data, his progress — all exactly where he left it.

**The AI Agents:**
The team has 5 tickets labeled "auto-agent" in Linear. Vienna spins up 5 isolated workspaces, one per ticket. Each AI agent reads its ticket, writes the code, runs the tests, and creates a pull request. All five work simultaneously. Engineers review the PRs the next morning over coffee.

---

## How It Works (The Simple Version)

Vienna runs behind the scenes on your computer using Docker (a tool that creates isolated containers — think of them as tiny virtual computers). When you switch to a different version, Vienna:

1. Saves everything about your current version (databases, configuration)
2. Sets up the new version with its own separate databases and configuration
3. Starts the product with everything connected and ready

When you switch back, it reverses the process. Nothing is lost. Nothing is shared between versions unless you want it to be.

You don't need to understand Docker, databases, or any of the internals. You just use the commands.

---

## Who Is It For

**Product managers** who want to test features without waiting for engineering or following outdated setup docs.

**QA teams** who need to switch between versions quickly and test multiple features side by side.

**Engineers** who work on multiple things at once and are tired of losing time to environment setup every time they switch context.

**Teams using AI agents** who want multiple agents working on different tasks simultaneously without conflicts.

**New team members** who should be productive on day one, not day three.

---

## What's Coming Next

- **Cloud workspaces.** Run environments on remote servers instead of your laptop — faster, more powerful, always available.
- **Automatic AI agents.** Create a ticket, label it, and an AI agent picks it up, sets up its own workspace, and starts working — no human needed to kick it off.
- **Shareable environments.** Package your exact setup — code version, database state, everything — and send it to a teammate. They open it and see exactly what you see.
