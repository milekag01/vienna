#!/usr/bin/env bash
# Linear API integration — fetch ticket details for agent context

VIENNA_LINEAR_API_URL="https://api.linear.app/graphql"

# Extract a ticket identifier from various input formats:
#   "COM-4521"
#   "com-4521"
#   "https://linear.app/commenda/issue/COM-4521/some-title"
linear_parse_ticket_input() {
    local input="$1"

    if [[ "$input" =~ ^https?://linear\.app/.*/issue/([A-Za-z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
        return 0
    fi

    if [[ "$input" =~ ^[A-Za-z]+-[0-9]+$ ]]; then
        echo "$input" | tr '[:lower:]' '[:upper:]'
        return 0
    fi

    log_error "Invalid ticket identifier: $input"
    echo "  Expected: COM-4521 or https://linear.app/.../issue/COM-4521/..."
    return 1
}

# Derive an instance name from a ticket identifier: COM-4521 → com-4521
linear_instance_name() {
    local identifier="$1"
    echo "$identifier" | tr '[:upper:]' '[:lower:]'
}

# Derive a branch name from ticket identifier + title: com-4521-fix-filing-calculation
linear_branch_name() {
    local identifier="$1"
    local title="$2"

    local slug
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50)
    echo "$(echo "$identifier" | tr '[:upper:]' '[:lower:]')-${slug}"
}

# Fetch a ticket from Linear's GraphQL API.
# Sets global variables: LINEAR_TICKET_* for the caller to use.
# Returns 0 on success, 1 on failure.
linear_fetch_ticket() {
    local identifier="$1"

    if [[ -z "$VIENNA_LINEAR_API_KEY" ]]; then
        log_error "Linear API key not configured."
        echo ""
        echo "  To set it up:"
        echo "  1. Go to https://linear.app/settings/api"
        echo "  2. Create a Personal API key"
        echo "  3. Add it to .vienna-state/secrets.env:"
        echo ""
        echo "     echo 'VIENNA_LINEAR_API_KEY=lin_api_YOUR_KEY_HERE' >> .vienna-state/secrets.env"
        echo ""
        return 1
    fi

    log_step "Fetching ticket $identifier from Linear..."

    local query
    query=$(cat <<'GRAPHQL'
query GetIssue($id: String!) {
  issue(id: $id) {
    id
    identifier
    title
    description
    priority
    priorityLabel
    url
    branchName
    state {
      name
    }
    labels {
      nodes {
        name
      }
    }
    assignee {
      name
    }
    comments {
      nodes {
        body
        user {
          name
        }
      }
    }
  }
}
GRAPHQL
)

    local variables
    variables=$(jq -n --arg id "$identifier" '{"id": $id}')

    local payload
    payload=$(jq -n --arg q "$query" --argjson v "$variables" '{"query": $q, "variables": $v}')

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $VIENNA_LINEAR_API_KEY" \
        --data "$payload" \
        "$VIENNA_LINEAR_API_URL" 2>&1)

    local curl_exit=$?
    if [[ $curl_exit -ne 0 ]]; then
        log_error "Failed to reach Linear API (curl exit code: $curl_exit)"
        return 1
    fi

    # Check for GraphQL errors
    local errors
    errors=$(echo "$response" | jq -r '.errors[0].message // empty' 2>/dev/null)
    if [[ -n "$errors" ]]; then
        log_error "Linear API error: $errors"
        return 1
    fi

    # Check that we got data
    local issue_id
    issue_id=$(echo "$response" | jq -r '.data.issue.id // empty' 2>/dev/null)
    if [[ -z "$issue_id" ]]; then
        log_error "Ticket $identifier not found in Linear"
        return 1
    fi

    # Export ticket data as global variables
    LINEAR_TICKET_ID=$(echo "$response" | jq -r '.data.issue.id')
    LINEAR_TICKET_IDENTIFIER=$(echo "$response" | jq -r '.data.issue.identifier')
    LINEAR_TICKET_TITLE=$(echo "$response" | jq -r '.data.issue.title // ""')
    LINEAR_TICKET_DESCRIPTION=$(echo "$response" | jq -r '.data.issue.description // ""')
    LINEAR_TICKET_PRIORITY=$(echo "$response" | jq -r '.data.issue.priorityLabel // "None"')
    LINEAR_TICKET_URL=$(echo "$response" | jq -r '.data.issue.url // ""')
    LINEAR_TICKET_BRANCH=$(echo "$response" | jq -r '.data.issue.branchName // ""')
    LINEAR_TICKET_STATE=$(echo "$response" | jq -r '.data.issue.state.name // ""')
    LINEAR_TICKET_ASSIGNEE=$(echo "$response" | jq -r '.data.issue.assignee.name // "Unassigned"')

    LINEAR_TICKET_LABELS=$(echo "$response" | jq -r '[.data.issue.labels.nodes[].name] | join(", ")' 2>/dev/null || echo "")

    # Collect comments (last 5, for context)
    LINEAR_TICKET_COMMENTS=$(echo "$response" | jq -r '
        [.data.issue.comments.nodes[:5][] |
         "**" + .user.name + "**: " + (.body // "")]
        | join("\n\n")' 2>/dev/null || echo "")

    # Store the raw JSON for .vienna-task.json
    LINEAR_TICKET_RAW_JSON=$(echo "$response" | jq '.data.issue')

    log_success "Fetched: $LINEAR_TICKET_IDENTIFIER — $LINEAR_TICKET_TITLE"
    log_step "Priority: $LINEAR_TICKET_PRIORITY | Status: $LINEAR_TICKET_STATE | Assignee: $LINEAR_TICKET_ASSIGNEE"
    if [[ -n "$LINEAR_TICKET_LABELS" ]]; then
        log_step "Labels: $LINEAR_TICKET_LABELS"
    fi

    return 0
}

# Write task context files into the instance directory.
# Called after spawn + linear_fetch_ticket.
linear_write_task_context() {
    local instance_dir="$1"
    local config_file="$2"

    local pg_nestjs pg_go redis localstack nestjs go_api enterprise
    pg_nestjs=$(jq -r '.ports.pg_nestjs' "$config_file")
    pg_go=$(jq -r '.ports.pg_go' "$config_file")
    redis=$(jq -r '.ports.redis' "$config_file")
    localstack=$(jq -r '.ports.localstack' "$config_file")
    nestjs=$(jq -r '.ports.nestjs' "$config_file")
    go_api=$(jq -r '.ports.go_api' "$config_file")
    enterprise=$(jq -r '.ports.enterprise // "-"' "$config_file")

    local branch
    branch=$(jq -r '.branch' "$config_file")

    # --- .cursor/rules/task.mdc ---
    local cursor_rules_dir="$instance_dir/.cursor/rules"
    ensure_dir "$cursor_rules_dir"

    cat > "$cursor_rules_dir/task.mdc" <<TASKFILE
---
description: Task context for this Vienna development instance — auto-generated by vienna spawn --ticket
alwaysApply: true
---

# WORKSPACE BOUNDARY — READ THIS FIRST

You are an AI agent working inside a Vienna isolated instance. You MUST obey these rules:

**Your workspace is: \`${instance_dir}\`**

- You MUST NOT read, edit, or create files outside of \`${instance_dir}/\`. This is a hard boundary.
- You MUST NOT run any commands (npm, prisma, atlas, psql, etc.) from outside \`${instance_dir}/\`. Always \`cd\` into the correct subdirectory first.
- All migrations MUST target this instance's databases only (see ports below). Never use default ports like 5432, 6379, or 8000.
- If you need to run a shell command, always run it from within \`${instance_dir}/commenda-logical-backend\`, \`${instance_dir}/sales-tax-api-2\`, or \`${instance_dir}/commenda\` as appropriate.
- Do NOT touch the parent workspace, other instances, or the main repo checkouts.

---

# Task: ${LINEAR_TICKET_TITLE}

**Ticket:** [${LINEAR_TICKET_IDENTIFIER}](${LINEAR_TICKET_URL})
**Branch:** ${branch}
**Priority:** ${LINEAR_TICKET_PRIORITY}
**Status:** ${LINEAR_TICKET_STATE}
**Labels:** ${LINEAR_TICKET_LABELS:-None}
**Assignee:** ${LINEAR_TICKET_ASSIGNEE}

## Description

${LINEAR_TICKET_DESCRIPTION:-No description provided.}

## This Instance's Ports (use ONLY these)

| Service | Port |
|---|---|
| PostgreSQL (NestJS/Prisma) | localhost:${pg_nestjs} |
| PostgreSQL (Go/Atlas) | localhost:${pg_go} |
| Redis | localhost:${redis} |
| LocalStack (SQS/S3) | localhost:${localstack} |
| NestJS backend | localhost:${nestjs} |
| Go Sales Tax API | localhost:${go_api} |
| Enterprise frontend | localhost:${enterprise} |

## Working Directory

All code lives in this instance's worktree at \`${instance_dir}\`. You are on branch \`${branch}\`.
Commit and push from here — it goes to the same remote as the main checkout.

## Guidelines

- Read the ticket description carefully before starting
- Focus on the specific task described above
- Write tests for your changes when applicable
- Commit with a clear message referencing ${LINEAR_TICKET_IDENTIFIER}
- When running services, use the .env files already generated in each repo directory
TASKFILE

    log_step "Wrote .cursor/rules/task.mdc"

    # --- .vienna-task.json ---
    local task_json
    task_json=$(jq -n \
        --arg ticket "$LINEAR_TICKET_IDENTIFIER" \
        --arg title "$LINEAR_TICKET_TITLE" \
        --arg description "$LINEAR_TICKET_DESCRIPTION" \
        --arg priority "$LINEAR_TICKET_PRIORITY" \
        --arg state "$LINEAR_TICKET_STATE" \
        --arg url "$LINEAR_TICKET_URL" \
        --arg assignee "$LINEAR_TICKET_ASSIGNEE" \
        --arg labels "$LINEAR_TICKET_LABELS" \
        --arg branch "$branch" \
        --argjson ports "$(jq '.ports' "$config_file")" \
        '{
            ticket: $ticket,
            title: $title,
            description: $description,
            priority: $priority,
            state: $state,
            url: $url,
            assignee: $assignee,
            labels: ($labels | split(", ")),
            branch: $branch,
            ports: $ports
        }')

    echo "$task_json" > "$instance_dir/.vienna-task.json"
    log_step "Wrote .vienna-task.json"
}

# Open a new Cursor window at the instance directory and start an Agent chat
# with the Linear task context (--new-window mode).
linear_open_cursor_window() {
    local instance_dir="$1"

    if ! command -v cursor &>/dev/null; then
        log_warn "Cursor CLI not found. Open manually:"
        echo "  cursor $instance_dir"
        return
    fi

    if [[ "$(uname)" != "Darwin" ]]; then
        log_warn "Agent chat auto-open in new window requires macOS. Opening Cursor without agent chat..."
        cursor --new-window "$instance_dir" &
        return
    fi

    local task_file="$instance_dir/.cursor/rules/task.mdc"
    local prompt="Read the file at ${task_file} — it contains the full task context, workspace boundary rules, and instance ports for ticket ${LINEAR_TICKET_IDENTIFIER}. Follow every instruction in that file. Begin solving the ticket immediately."

    log_step "Opening new Cursor window at $instance_dir..."

    # Record how many Cursor windows exist before we open a new one
    local windows_before
    windows_before=$(osascript -e \
        'tell application "System Events" to tell process "Cursor" to return count of windows' \
        2>/dev/null || echo "0")

    # Force a brand-new Cursor window for the instance directory
    cursor --new-window "$instance_dir" &

    # Poll until a new window actually appears (up to 30 s)
    log_step "Waiting for new Cursor window to appear..."
    local waited=0
    local max_wait=30
    while (( waited < max_wait )); do
        sleep 1
        (( waited++ ))
        local windows_now
        windows_now=$(osascript -e \
            'tell application "System Events" to tell process "Cursor" to return count of windows' \
            2>/dev/null || echo "0")
        if (( windows_now > windows_before )); then
            log_step "New window detected after ${waited}s — letting it finish loading..."
            sleep 5
            break
        fi
    done

    if (( waited >= max_wait )); then
        log_warn "Timed out waiting for the new Cursor window."
        echo "  Open a chat manually and reference: $task_file"
        return
    fi

    log_step "Opening Agent chat with task context..."

    # Save current clipboard
    local _saved_clipboard=""
    _saved_clipboard=$(pbpaste 2>/dev/null) || true

    # Put the prompt on the clipboard
    printf '%s' "$prompt" | pbcopy

    # The new window should already have the Agent chat focused.
    # Just bring Cursor to front, paste the prompt, and send.
    osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "Cursor"
        set frontmost to true
        delay 1.5

        -- Cmd+V → paste the prompt into the already-focused chat input
        keystroke "v" using {command down}
        delay 0.5

        -- Enter → send
        key code 36
    end tell
end tell
APPLESCRIPT

    # Restore clipboard
    printf '%s' "$_saved_clipboard" | pbcopy 2>/dev/null || true

    log_success "New Cursor window opened with Agent chat for ${LINEAR_TICKET_IDENTIFIER}."
}

# Open a NEW Agent chat in the current Cursor window (default mode)
# Uses AppleScript: Command Palette → "new chat" to guarantee a fresh agent session
linear_open_agent_chat() {
    local instance_dir="$1"
    local ticket_id="$2"
    local ticket_title="$3"

    if [[ "$(uname)" != "Darwin" ]]; then
        log_warn "Agent chat auto-open requires macOS. Start manually:"
        echo "  Open a new Agent chat and reference: $instance_dir/.cursor/rules/task.mdc"
        return
    fi

    local task_file="$instance_dir/.cursor/rules/task.mdc"
    if [[ ! -f "$task_file" ]]; then
        log_warn "Task file not found at $task_file"
        return
    fi

    local prompt="Read the file at ${task_file} — it contains the full task context, workspace boundary rules, and instance ports for ticket ${ticket_id}. Follow every instruction in that file. Begin solving the ticket immediately."

    log_step "Opening NEW Agent chat for ${ticket_id} in current Cursor..."

    # Save current clipboard
    local _saved_clipboard=""
    _saved_clipboard=$(pbpaste 2>/dev/null) || true

    # Put the prompt on the clipboard
    printf '%s' "$prompt" | pbcopy

    osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "Cursor"
        set frontmost to true
        delay 2.0

        -- Step 1: Press Escape to clear any focused panel/terminal
        key code 53
        delay 0.5

        -- Step 2: Cmd+L to open chat (or focus it if already open)
        keystroke "l" using {command down}
        delay 1.0

        -- Step 3: Cmd+L again to create a NEW chat (when chat panel is already focused)
        keystroke "l" using {command down}
        delay 1.5

        -- Step 4: Paste the prompt (Cmd+V)
        keystroke "v" using {command down}
        delay 0.5

        -- Step 5: Press Enter to send
        key code 36
    end tell
end tell
APPLESCRIPT

    # Restore clipboard
    printf '%s' "$_saved_clipboard" | pbcopy 2>/dev/null || true

    log_success "New Agent chat opened for ${ticket_id}. Check your chat panel."
}
