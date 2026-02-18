#!/usr/bin/env bash
# Git worktree management — create and remove worktrees for all repos

source "$VIENNA_DIR/lib/config.sh"

# Create worktrees for all repos in the instance directory
# Args: instance_name, branch
worktrees_create() {
    local name="$1"
    local branch="$2"
    local create_branch="${3:-false}"
    local instance_dir="$VIENNA_INSTANCES/$name"

    ensure_dir "$instance_dir"

    for repo in "${VIENNA_REPOS[@]}"; do
        local repo_dir="$VIENNA_WORKSPACE/$repo"
        local worktree_dir="$instance_dir/$repo"

        if [[ ! -d "$repo_dir/.git" ]] && [[ ! -f "$repo_dir/.git" ]]; then
            log_warn "Repo $repo not found at $repo_dir, skipping"
            continue
        fi

        # Check if branch exists in this repo
        local branch_to_use="$branch"
        if ! git -C "$repo_dir" rev-parse --verify "$branch" &>/dev/null 2>&1; then
            # Try remote
            git -C "$repo_dir" fetch origin 2>/dev/null || true
            if git -C "$repo_dir" rev-parse --verify "origin/$branch" &>/dev/null 2>&1; then
                log_step "$repo: tracking remote branch $branch"
            else
                if [[ "$create_branch" == "true" ]]; then
                    local base_branch="${VIENNA_BASE_BRANCH:-main}"
                    log_step "$repo: creating new branch '$branch' from $base_branch"
                    git -C "$repo_dir" worktree add -b "$branch" "$worktree_dir" "origin/$base_branch" 2>&1 | while IFS= read -r line; do
                        echo "    $line"
                    done
                    if [[ -d "$worktree_dir" ]]; then
                        log_success "  $repo: worktree created on new branch $branch"
                        continue
                    else
                        log_error "Failed to create worktree for $repo"
                        return 1
                    fi
                else
                    log_warn "$repo: branch '$branch' not found, using current branch"
                    branch_to_use=$(git -C "$repo_dir" branch --show-current)
                fi
            fi
        fi

        log_step "Creating worktree: $repo → $branch_to_use"

        # Create the worktree
        if [[ -d "$worktree_dir" ]]; then
            log_warn "Worktree already exists at $worktree_dir, skipping"
            continue
        fi

        git -C "$repo_dir" worktree add "$worktree_dir" "$branch_to_use" 2>&1 | while IFS= read -r line; do
            echo "    $line"
        done

        if [[ $? -ne 0 ]]; then
            log_error "Failed to create worktree for $repo"
            return 1
        fi
    done

    log_success "Worktrees created at $instance_dir/"
}

# Remove worktrees for all repos in an instance
worktrees_remove() {
    local name="$1"
    local instance_dir="$VIENNA_INSTANCES/$name"

    for repo in "${VIENNA_REPOS[@]}"; do
        local repo_dir="$VIENNA_WORKSPACE/$repo"
        local worktree_dir="$instance_dir/$repo"

        if [[ -d "$worktree_dir" ]]; then
            log_step "Removing worktree: $repo"
            git -C "$repo_dir" worktree remove "$worktree_dir" --force 2>/dev/null || {
                log_warn "git worktree remove failed for $repo, cleaning up manually"
                rm -rf "$worktree_dir"
                git -C "$repo_dir" worktree prune 2>/dev/null || true
            }
        fi
    done

    # Remove the instance directory if empty
    if [[ -d "$instance_dir" ]]; then
        rm -rf "$instance_dir"
    fi
}

# List branches for worktrees in an instance
worktrees_info() {
    local name="$1"
    local instance_dir="$VIENNA_INSTANCES/$name"

    for repo in "${VIENNA_REPOS[@]}"; do
        local worktree_dir="$instance_dir/$repo"
        if [[ -d "$worktree_dir" ]]; then
            local branch
            branch=$(git -C "$worktree_dir" branch --show-current 2>/dev/null || echo "detached")
            echo "$repo:$branch"
        fi
    done
}
