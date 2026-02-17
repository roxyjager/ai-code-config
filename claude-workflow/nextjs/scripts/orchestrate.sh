#!/bin/bash
# ============================================================================
# Agent Pipeline Orchestrator — Next.js
# ============================================================================
# Usage:
#   ./orchestrate.sh "Feature description here"
#   ./orchestrate.sh --plan /path/to/existing/plan.json
#   ./orchestrate.sh --resume  (resumes from last state)
#
# Requirements:
#   - Claude Code CLI (`claude`) installed and authenticated
#   - Agent files in shared agents/ and nextjs/agents/
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_AGENTS_DIR="${SCRIPT_DIR}/../agents"
SHARED_AGENTS_DIR="${SCRIPT_DIR}/../../agents"
LOGS_DIR="/tmp/pipeline-logs/$(date +%Y%m%d-%H%M%S)"
PLAN_FILE="/tmp/plan.json"

# Permission mode: bypasses all permission prompts so the pipeline runs unattended
# Change to "" if you want to approve each action manually
PERMISSION_FLAG="--dangerously-skip-permissions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

# ============================================================================
# Codebase Snapshot — gives the architect context about existing code
# ============================================================================
generate_codebase_snapshot() {
    local snapshot="/tmp/codebase-snapshot.md"

    cat > "$snapshot" << 'HEADER'
# Codebase Snapshot
> Auto-generated. Used by the architect to understand existing patterns.
HEADER

    # File structure (2 levels deep, ignore noise)
    echo -e "\n## Project Structure\n\`\`\`" >> "$snapshot"
    find . -maxdepth 3 -type f \
        -not -path '*/node_modules/*' \
        -not -path '*/.next/*' \
        -not -path '*/.git/*' \
        -not -path '*/dist/*' \
        -not -path '*/.claude/*' \
        -not -path '*/coverage/*' \
        -not -name '*.lock' \
        -not -name '*.map' \
        | sort >> "$snapshot" 2>/dev/null
    echo '```' >> "$snapshot"

    # Data models / schema
    echo -e "\n## Data Models & Schema" >> "$snapshot"
    echo '```typescript' >> "$snapshot"
    find . -type f \( -name "schema.*" -o -name "*.model.*" -o -name "*.entity.*" -o -path "*/models/*" -o -path "*/schema/*" -o -path "*/prisma/schema.prisma" -o -path "*/drizzle/*" \) \
        -not -path '*/node_modules/*' \
        -not -path '*/.next/*' \
        -exec echo "// === {} ===" \; \
        -exec cat {} \; 2>/dev/null | head -500 >> "$snapshot" || true
    echo '```' >> "$snapshot"

    # API routes
    echo -e "\n## API Routes" >> "$snapshot"
    echo '```typescript' >> "$snapshot"
    find . -type f -name "route.ts" -o -name "route.tsx" -o -name "route.js" \
        | grep -v node_modules \
        | sort \
        | while read -r f; do
            echo "// === $f ==="
            head -30 "$f"
            echo ""
        done >> "$snapshot" 2>/dev/null
    echo '```' >> "$snapshot"

    # Exported types and interfaces
    echo -e "\n## Types & Interfaces" >> "$snapshot"
    echo '```typescript' >> "$snapshot"
    grep -r "export interface\|export type\|export enum" \
        --include="*.ts" --include="*.tsx" \
        --exclude-dir=node_modules --exclude-dir=.next \
        . 2>/dev/null | head -100 >> "$snapshot" || true
    echo '```' >> "$snapshot"

    # Component inventory
    echo -e "\n## Components" >> "$snapshot"
    echo '```' >> "$snapshot"
    find . -path "*/components/*" -name "*.tsx" \
        -not -path '*/node_modules/*' \
        | sort >> "$snapshot" 2>/dev/null
    echo '```' >> "$snapshot"

    # Package.json dependencies (what's available)
    if [ -f "package.json" ]; then
        echo -e "\n## Dependencies" >> "$snapshot"
        echo '```json' >> "$snapshot"
        jq '{dependencies, devDependencies}' package.json >> "$snapshot" 2>/dev/null
        echo '```' >> "$snapshot"
    fi

    local size
    size=$(wc -l < "$snapshot")
    log_ok "Codebase snapshot: ${size} lines → /tmp/codebase-snapshot.md"
}

# ============================================================================
# Phase 1: Architecture
# ============================================================================
get_next_plan_number() {
    mkdir -p plans
    local last
    last=$(ls plans/[0-9]*.json 2>/dev/null | sort -V | tail -1 | sed 's|plans/||' | grep -oE '^[0-9]+' || echo "0")
    printf "%03d" $(( ${last:-0} + 1 ))
}

slugify() {
    # Take only the first line, strip markdown heading prefix, then slugify
    echo "$1" | head -1 | sed 's/^#* *//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-50
}

# ============================================================================
# Git: Feature Branch Management
# ============================================================================
get_plan_slug() {
    basename "$1" .json
}

create_or_checkout_feature_branch() {
    local slug
    slug=$(get_plan_slug "$1")
    local branch="feature/${slug}"

    if git rev-parse --verify "$branch" &>/dev/null; then
        log_info "Feature branch exists, checking out: ${branch}"
        git checkout "$branch"
    else
        log_info "Creating feature branch: ${branch}"
        git checkout -b "$branch"
    fi
}

run_architect() {
    local feature_desc="$1"
    local next_num
    next_num=$(get_next_plan_number)
    local slug
    slug=$(slugify "$feature_desc")
    local plan_name="${next_num}-${slug}.json"
    PLAN_FILE="plans/${plan_name}"

    log_step "Generating codebase snapshot..."
    generate_codebase_snapshot

    log_step "Running Architect Agent → ${plan_name}..."

    claude -p "Read the agent prompt at ${SHARED_AGENTS_DIR}/architect.md and follow its instructions.

Create a detailed implementation plan for the following feature:

${feature_desc}

EXISTING CODEBASE CONTEXT:
The file /tmp/codebase-snapshot.md contains a snapshot of the current project structure, existing data models, API routes, types, and components. Read this file BEFORE creating the plan so you can:
- Match existing naming conventions and patterns
- Extend existing models rather than recreating them
- Use correct import paths
- Avoid conflicting with existing files

PLAN NUMBERING:
- This is plan number: ${next_num}
- Feature slug: ${slug}
- Save to: plans/${plan_name}
- Also copy to: /tmp/plan.json
- Set metadata.plan_number to ${next_num}
- Set metadata.filename to ${plan_name}
- Set metadata.created_at to the current UTC timestamp
- Set metadata.feature_request to the exact feature description above
- Set metadata.status to \"pending\"
- Set all phase statuses to \"pending\" with empty execution blocks

Follow the schema defined in the architect prompt." \
        --tools "Bash,Edit,Read,Write" \
        ${PERMISSION_FLAG} \
        2>&1 | tee "${LOGS_DIR}/architect.log"

    if [ ! -f "$PLAN_FILE" ]; then
        # Fallback: check if it went to /tmp/plan.json instead
        if [ -f "/tmp/plan.json" ]; then
            cp /tmp/plan.json "$PLAN_FILE"
        else
            log_error "Architect failed to produce plan"
            exit 1
        fi
    fi

    # Always keep /tmp/plan.json in sync for the pipeline manager
    cp "$PLAN_FILE" /tmp/plan.json

    log_ok "Plan created: ${PLAN_FILE}"

    # Validate plan structure
    local phase_count
    phase_count=$(jq '.phases | length' "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$phase_count" -eq 0 ]; then
        log_error "Plan has no phases"
        exit 1
    fi
    log_ok "Plan has ${phase_count} phases (plan #${next_num})"
}

# ============================================================================
# Utility: Show detailed plan status
# ============================================================================
show_plan_status() {
    local plan_file="$1"
    if [ ! -f "$plan_file" ]; then
        log_error "Plan file not found: ${plan_file}"
        exit 1
    fi

    local feature status created
    feature=$(jq -r '.feature // "unknown"' "$plan_file")
    status=$(jq -r '.metadata.status // "unknown"' "$plan_file")
    created=$(jq -r '.metadata.created_at // "unknown"' "$plan_file")

    echo "========================================"
    echo "  Plan: $(basename "$plan_file" .json)"
    echo "  Feature: ${feature}"
    echo "  Status: ${status}"
    echo "  Created: ${created}"
    echo "========================================"
    echo ""
    printf "  %-4s %-30s %-12s %-8s %-8s %s\n" "ID" "PHASE" "STATUS" "REVIEWS" "UI REV" "TESTS"
    printf "  %-4s %-30s %-12s %-8s %-8s %s\n" "--" "-----" "------" "-------" "------" "-----"

    jq -r '.phases[] | [
        .id,
        (.name | .[0:28]),
        (.status // "pending"),
        (.execution.review_cycles // 0 | tostring),
        (.execution.ui_review_cycles // 0 | tostring),
        (.execution.tests_written // 0 | tostring)
    ] | @tsv' "$plan_file" 2>/dev/null | while IFS=$'\t' read -r id name phase_status reviews ui_reviews tests; do
        local status_icon
        case $phase_status in
            completed)   status_icon="✅" ;;
            in_progress) status_icon="🔄" ;;
            escalated)   status_icon="⚠️ " ;;
            failed)      status_icon="❌" ;;
            *)           status_icon="⏳" ;;
        esac
        printf "  %-4s %-30s %-12s %-8s %-8s %s\n" "$id" "$name" "${status_icon} ${phase_status}" "$reviews" "$ui_reviews" "$tests"
    done
    echo ""
    echo "========================================"
}

# ============================================================================
# Phase 2: Pipeline Execution (fully autonomous)
# ============================================================================
run_pipeline() {
    local resume_flag="${1:-false}"
    local resume_instruction=""

    # Create or checkout the feature branch for this plan
    create_or_checkout_feature_branch "$PLAN_FILE"

    if [ "$resume_flag" = "true" ]; then
        # Discard uncommitted partial work from an interrupted phase
        local current_branch
        current_branch=$(git branch --show-current)
        if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
            log_warn "Resetting uncommitted changes from interrupted phase"
            git reset --hard
        fi
        resume_instruction="RESUME MODE: This plan was previously interrupted. Check metadata.status and each phase's status. Skip any phase with status 'completed'. Resume from the first phase that is NOT 'completed'."
        log_step "Resuming Pipeline Manager Agent..."
    else
        log_step "Running Pipeline Manager Agent..."
    fi

    claude -p "Read the agent prompt at ${SHARED_AGENTS_DIR}/pipeline-manager.md and follow its instructions.

The plan is at ${PLAN_FILE} (also at /tmp/plan.json). Execute the full pipeline for every phase.

${resume_instruction}

AGENT FILE LOCATIONS (pass these paths to subagents):
- Senior Engineer: ${FRAMEWORK_AGENTS_DIR}/senior-engineer.md
- Code Reviewer: ${SHARED_AGENTS_DIR}/code-reviewer.md
- UI/UX Specialist: ${FRAMEWORK_AGENTS_DIR}/ui-ux-specialist.md
- SDET: ${SHARED_AGENTS_DIR}/sdet.md

IMPORTANT — STATE PERSISTENCE:
After EVERY pipeline step, update the plan JSON file at BOTH:
  1. /tmp/plan.json
  2. ${PLAN_FILE}
Update phase statuses, execution counters, and timestamps as described in the pipeline-manager prompt.

Use the Task tool to spawn each subagent. In each Task prompt, include:
1. 'Read the agent prompt at {path}' where path is the agent file
2. All relevant context from the plan
3. The specific phase information

Execute ALL phases sequentially through the full pipeline:
Engineer → Code Review (loop max 3) → UI/UX if frontend (loop max 2) → SDET → Final Review → Validation

Begin now." \
        --tools "Bash,Edit,Read,Write,Task" \
        ${PERMISSION_FLAG} \
        2>&1 | tee "${LOGS_DIR}/pipeline.log" || true

    log_ok "Pipeline execution complete"
}

# ============================================================================
# Post-Pipeline: Verify & enforce feature documentation
# ============================================================================
verify_and_create_docs() {
    local plan_file="$1"

    if [ ! -f "$plan_file" ]; then
        log_warn "Plan file not found for doc verification: ${plan_file}"
        return
    fi

    # Extract plan number and slug from filename (e.g., 003-feature-slug.json)
    local plan_basename
    plan_basename=$(basename "$plan_file" .json)
    local plan_number
    plan_number=$(echo "$plan_basename" | grep -oE '^[0-9]+')

    # Derive the expected feature doc path
    local feature_doc="docs/features/${plan_basename}.md"

    # Check if the pipeline manager already created the docs
    if [ -f "$feature_doc" ]; then
        log_ok "Feature documentation exists: ${feature_doc}"
        return
    fi

    log_warn "Feature documentation missing: ${feature_doc}"
    log_step "Spawning dedicated documentation agent..."

    # Create docs directory if needed
    mkdir -p docs/features docs/categories

    claude -p "Read the agent prompt at ${SHARED_AGENTS_DIR}/pipeline-manager.md — specifically the 'Step 4: Feature Documentation Update' section.

The pipeline completed all phases but SKIPPED the documentation step. You must now create the feature documentation.

PLAN FILE: ${plan_file}
Read the plan file to understand the feature, phases, and what was built.

PLAN NUMBER: ${plan_number}
PLAN BASENAME: ${plan_basename}

YOUR TASK — Create/update THREE documentation files:

1. docs/features/${plan_basename}.md — Per-feature documentation (read existing feature docs in docs/features/ for format reference)
2. docs/categories/{category}.md — Update the appropriate category file (read existing ones in docs/categories/)
3. docs/INDEX.md — Regenerate the full index (read ALL files in docs/features/ and docs/categories/)

IMPORTANT:
- Read existing docs/features/ files to match the format exactly
- Read the plan JSON to extract phase names, file lists, and what was built
- Scan the codebase (src/app/api/, src/lib/, tests/) to verify what files exist
- Do NOT invent files that don't exist — verify before listing

Begin now." \
        --tools "Bash,Edit,Read,Write,Glob,Grep" \
        ${PERMISSION_FLAG} \
        2>&1 | tee "${LOGS_DIR}/docs-verification.log" || true

    # Final check
    if [ -f "$feature_doc" ]; then
        log_ok "Feature documentation created: ${feature_doc}"

        # Commit the docs
        git add docs/
        git commit -m "docs: add feature documentation for ${plan_basename}" || true
    else
        log_error "Feature documentation still missing after dedicated run: ${feature_doc}"
    fi
}

# ============================================================================
# Utility: List all plans
# ============================================================================
list_plans() {
    echo "========================================"
    echo "  Plan History"
    echo "========================================"
    if [ ! -d "plans" ] || [ -z "$(ls plans/[0-9]*.json 2>/dev/null)" ]; then
        echo "  No plans found."
        return
    fi
    printf "  %-40s %-12s %-14s %s\n" "PLAN" "PHASES" "STATUS" "CREATED"
    printf "  %-40s %-12s %-14s %s\n" "----" "------" "------" "-------"
    for f in $(ls plans/[0-9]*.json 2>/dev/null | sort -V); do
        local name feature phases status created completed_phases
        name=$(basename "$f" .json)
        phases=$(jq '.phases | length' "$f" 2>/dev/null || echo "?")
        completed_phases=$(jq '[.phases[] | select(.status == "completed")] | length' "$f" 2>/dev/null || echo "0")
        status=$(jq -r '.metadata.status // "unknown"' "$f" 2>/dev/null)
        created=$(jq -r '.metadata.created_at // "unknown"' "$f" 2>/dev/null | cut -c1-10)

        # Color the status
        local status_display
        case $status in
            completed)   status_display="${GREEN}✅ done${NC}" ;;
            in_progress) status_display="${YELLOW}🔄 ${completed_phases}/${phases}${NC}" ;;
            paused)      status_display="${YELLOW}⏸ ${completed_phases}/${phases}${NC}" ;;
            failed)      status_display="${RED}❌ failed${NC}" ;;
            escalated)   status_display="${RED}⚠ escalated${NC}" ;;
            *)           status_display="⏳ pending" ;;
        esac

        printf "  %-40s %-12s " "$name" "${phases} phases"
        echo -e "${status_display}\t${created}"
    done
    echo "========================================"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "========================================"
    echo "  EXOD.ai Agent Pipeline Orchestrator"
    echo "========================================"

    mkdir -p "$LOGS_DIR"
    log_info "Logs directory: ${LOGS_DIR}"

    # Check required dependencies
    local missing=()
    command -v claude &> /dev/null || missing+=("claude (Claude Code CLI)")
    command -v jq &> /dev/null || missing+=("jq (brew install jq)")
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi

    # Check agent files exist (shared + framework-specific)
    for agent in architect pipeline-manager code-reviewer sdet; do
        if [ ! -f "${SHARED_AGENTS_DIR}/${agent}.md" ]; then
            log_error "Missing shared agent file: ${SHARED_AGENTS_DIR}/${agent}.md"
            exit 1
        fi
    done
    for agent in senior-engineer ui-ux-specialist; do
        if [ ! -f "${FRAMEWORK_AGENTS_DIR}/${agent}.md" ]; then
            log_error "Missing framework agent file: ${FRAMEWORK_AGENTS_DIR}/${agent}.md"
            exit 1
        fi
    done
    log_ok "All agent files found (shared + Next.js)"

    # Parse arguments
    if [ "$#" -eq 0 ]; then
        log_error "Usage: $0 \"Feature description\"         (creates plan, stops for review)"
        echo "       $0 @feature-brief.md              (read description from file)"
        echo "       $0 --plan /path/to/plan.json      (execute a reviewed plan)"
        echo "       $0 --auto \"Feature description\"    (plan + execute without stopping)"
        echo "       $0 --auto @feature-brief.md       (plan + execute without stopping)"
        echo "       $0 --resume /path/to/plan.json    (resume interrupted plan)"
        echo "       $0 --status /path/to/plan.json    (show phase status)"
        echo "       $0 --list                          (show all plans)"
        echo "       $0 --interactive \"Feature desc\"    (ask before each action)"
        exit 1
    fi

    local skip_architect=false
    local feature_desc=""
    local resume_mode=false
    local auto_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                list_plans
                exit 0
                ;;
            --status)
                show_plan_status "$2"
                exit 0
                ;;
            --resume)
                PLAN_FILE="$2"
                skip_architect=true
                resume_mode=true
                shift 2
                ;;
            --interactive)
                PERMISSION_FLAG=""
                log_info "Interactive mode: Claude will ask for permission on each action"
                shift
                ;;
            --plan)
                PLAN_FILE="$2"
                skip_architect=true
                auto_mode=true
                shift 2
                ;;
            --auto)
                auto_mode=true
                shift
                ;;
            --skip-architect)
                skip_architect=true
                shift
                ;;
            *)
                feature_desc="$1"
                # Support @file syntax — read description from file
                if [[ "$feature_desc" == @* ]]; then
                    local brief_file="${feature_desc:1}"
                    if [ ! -f "$brief_file" ]; then
                        log_error "Feature brief file not found: ${brief_file}"
                        exit 1
                    fi
                    feature_desc=$(cat "$brief_file")
                    log_ok "Read feature brief from: ${brief_file} ($(wc -l < "$brief_file") lines)"
                fi
                shift
                ;;
        esac
    done

    # Step 1: Architect (unless skipping)
    if [ "$skip_architect" = false ]; then
        if [ -z "$feature_desc" ]; then
            log_error "Feature description required (or use --plan /path/to/plan.json)"
            exit 1
        fi
        run_architect "$feature_desc"
    else
        if [ ! -f "$PLAN_FILE" ]; then
            log_error "Plan file not found: ${PLAN_FILE}"
            exit 1
        fi
        log_info "Using existing plan: ${PLAN_FILE}"
    fi

    # Default: stop after plan creation so user can review
    if [ "$auto_mode" = false ] && [ "$resume_mode" = false ]; then
        echo ""
        echo "========================================"
        log_ok "PLAN READY FOR REVIEW"
        echo "  Plan: ${PLAN_FILE}"
        echo ""
        echo "  Review the plan, then execute:"
        echo "    $0 --plan ${PLAN_FILE}"
        echo ""
        echo "  Or re-run with --auto to skip review:"
        echo "    $0 --auto @feature-brief.md"
        echo "========================================"
        exit 0
    fi

    # Step 2: Run the full pipeline
    run_pipeline "$resume_mode"

    # Step 3: Verify and enforce feature documentation
    # The pipeline manager should create docs in its Step 4, but if it runs out
    # of context (common with large plans), this safety net catches it and spawns
    # a dedicated documentation session.
    verify_and_create_docs "$PLAN_FILE"

    # Done
    echo ""
    echo "========================================"
    log_ok "PIPELINE COMPLETE"
    echo "  Plan: ${PLAN_FILE}"
    echo "  Logs: ${LOGS_DIR}/"
    if [ -d "plans" ]; then
        local total_plans
        total_plans=$(ls plans/plan-*.json 2>/dev/null | wc -l)
        echo "  Total plans in history: ${total_plans}"
    fi
    echo "========================================"
}

main "$@"
