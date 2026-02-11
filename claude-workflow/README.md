# Claude Agent Workflow

A fully autonomous development pipeline that takes a feature from architectural plan to tested, reviewed, production-built code without human intervention.

## Architecture

```
YOU ──→ Architect Agent ──→ Plan (plans/001-feature-name.json)
                                    │
                           Pipeline Manager Agent
                                    │
                    ┌───────────────────────────────────┐
                    │    FOR EACH PHASE IN PLAN:        │
                    │                                   │
                    │  ① Senior Engineer → implement    │
                    │  ② Code Reviewer → review         │
                    │  ③ Senior Engineer → fix issues    │
                    │     ↻ loop max 3x                 │
                    │  ④ UI/UX Specialist → review UI   │
                    │     (only if has_frontend: true)   │
                    │  ⑤ Senior Engineer → fix UI issues │
                    │     ↻ loop max 2x                 │
                    │  ⑥ SDET → write tests             │
                    │  ⑦ Run Tests → execute & validate  │
                    │     ↻ fix & retry max 3x           │
                    │  ⑧ Code Reviewer → final review   │
                    │  ⑨ Phase Validation → gate check  │
                    └───────────────────────────────────┘
                                    │
                        Integration Review (all phases)
                                    │
                        Production Build (tsc + build)
                                    │
                        Feature Docs (docs/features + categories + INDEX)
                                    │
                            Final Report ──→ YOU
```

## Repository Structure

```
claude-workflow/
  agents/                          ← SHARED (framework-agnostic)
    architect.md
    pipeline-manager.md
    code-reviewer.md
    sdet.md
  nextjs/                          ← NEXT.JS SPECIFIC
    agents/
      senior-engineer.md
      ui-ux-specialist.md
    scripts/
      orchestrate.sh
    templates/
      docs/
      example-plan.json
  react-native/                    ← REACT NATIVE SPECIFIC
    agents/
      senior-engineer.md
      ui-ux-specialist.md
    scripts/
      orchestrate.sh
    templates/
      docs/
      example-plan.json
  setup-workflow.sh                ← Setup script (accepts framework flag)
```

**What's shared**: Architect, pipeline manager, code reviewer, and SDET are framework-agnostic — they work with plans, review logic, and test structure, not framework specifics.

**What's framework-specific**: Senior engineer (coding patterns, file structure, conventions) and UI/UX specialist (web vs mobile UX, platform conventions) differ meaningfully per framework. The orchestrate script also differs (build commands, type checking).

## Pipeline Output Locations

The pipeline generates files in your project. Here's what goes where:

```
your-project/
│
├── plans/                              ← EXECUTION PLANS
│   ├── 001-competitor-ad-intel.json    Created by: Architect
│   ├── 002-user-onboarding.json        Updated by: Pipeline Manager (status tracking)
│   └── ...                             Contains: phases, acceptance criteria, execution state
│
├── docs/
│   ├── INDEX.md                        ← FEATURE INDEX
│   │                                   Created by: Senior Engineer (post-pipeline)
│   │                                   Regenerated: every pipeline run
│   │                                   Contains: tables linking all features by category + chronological
│   │
│   ├── features/                       ← PER-FEATURE DOCS
│   │   ├── 001-competitor-ad-intel.md  Created by: Senior Engineer (post-pipeline)
│   │   ├── 002-user-onboarding.md      One file per plan, never modified after creation
│   │   └── ...                         Contains: full record — phases, files, endpoints, models, deps
│   │
│   └── categories/                     ← CATEGORY DOCS
│       ├── core-platform.md            Created by: Senior Engineer (post-pipeline)
│       ├── integrations.md             Updated in place when features are added/changed
│       ├── ai-automation.md            Contains: grouped feature summaries with status
│       └── ...
│
├── src/                                ← YOUR CODE
│   └── ...                             Modified by: Senior Engineer (during pipeline phases)
│
├── tests/                              ← TEST SUITES
│   └── ...                             Created by: SDET (during pipeline phases)
│
└── /tmp/                               ← TEMPORARY (not committed)
    ├── plan.json                       Working copy of current plan
    ├── codebase-snapshot.md            Generated before architect runs
    ├── test-results-phase-*.log        Test execution output per phase
    ├── typecheck-phase-*.log           TypeScript check output per phase
    ├── build-production.log            Production build output
    └── pipeline-logs/                  Full agent logs per run
```

| Folder | Created by | Committed to git? | Purpose |
|--------|-----------|-------------------|---------|
| `plans/` | Architect + Pipeline Manager | ✅ Yes | Feature plans with execution state |
| `docs/features/` | Senior Engineer | ✅ Yes | Detailed per-plan build records |
| `docs/categories/` | Senior Engineer | ✅ Yes | Features grouped by domain |
| `docs/INDEX.md` | Senior Engineer | ✅ Yes | Auto-generated feature overview |
| `src/` | Senior Engineer | ✅ Yes | Application code |
| `tests/` | SDET | ✅ Yes | Test suites |
| `/tmp/pipeline-logs/` | Orchestrate script | ❌ No | Debug logs per run |
| `/tmp/codebase-snapshot.md` | Orchestrate script | ❌ No | Pre-architect codebase scan |

## Quick Start

```bash
# 1. Clone the workflow repo
git clone git@github.com:username/ai-code-config.git ~/ai-code-config

# 2. In your Next.js project
cd /path/to/nextjs-project
~/ai-code-config/claude-workflow/setup-workflow.sh nextjs

# 3. In your React Native project
cd /path/to/rn-project
~/ai-code-config/claude-workflow/setup-workflow.sh react-native

# 4. Run the pipeline
.claude/scripts/orchestrate.sh "Your feature description"
```

## How to Use

By default, the script creates a plan and **stops for your review**. You decide when to execute.

### Step 1: Create a plan

```bash
# Simple feature — inline description
.claude/scripts/orchestrate.sh "Add a settings page with dark mode toggle"

# Complex feature — from a file (use @ prefix)
.claude/scripts/orchestrate.sh @feature-brief.md
```

The architect scans your codebase, creates the plan, saves it to `plans/`, and stops. You'll see:
```
✅ PLAN READY FOR REVIEW
  Plan: plans/003-settings-page.json

  Review the plan, then execute:
    ./orchestrate.sh --plan plans/003-settings-page.json
```

### Step 2: Review the plan

Read the plan, check that the data models, phases, and acceptance criteria look right. Optionally paste it into a Claude chat for a second opinion.

```bash
cat plans/003-settings-page.json
```

### Step 3: Execute

```bash
.claude/scripts/orchestrate.sh --plan plans/003-settings-page.json
```

The full pipeline runs autonomously: engineer → review → test → build → docs.

### Shortcut: skip review for simple features

For small, straightforward features where you trust the architect to get it right:

```bash
.claude/scripts/orchestrate.sh --auto "Add dark mode toggle to settings"
.claude/scripts/orchestrate.sh --auto @feature-brief.md
```

`--auto` creates the plan and immediately executes it in one shot.

### Resume an interrupted run

```bash
.claude/scripts/orchestrate.sh --resume plans/003-settings-page.json
```

Completed phases are skipped. Picks up from where it left off.

## Per-Project Structure After Setup

```
your-project/
  .claude/
    shared-agents/ → ~/ai-code-config/claude-workflow/agents/           (symlink)
    agents/        → ~/ai-code-config/claude-workflow/{framework}/agents/ (symlink)
    scripts/       → ~/ai-code-config/claude-workflow/{framework}/scripts/ (symlink)
    templates/     → ~/ai-code-config/claude-workflow/{framework}/templates/ (symlink)
  docs/
    INDEX.md           ← auto-generated feature index
    features/          ← one file per completed plan
    categories/        ← features grouped by category
  plans/               ← project-specific, auto-created
    001-some-feature.json
  src/
  ...
```

## Plan History & Status Tracking

Plans are automatically numbered with descriptive names and saved to `plans/`:

```bash
# List all plans with status
.claude/scripts/orchestrate.sh --list

# Detailed phase-by-phase status
.claude/scripts/orchestrate.sh --status plans/002-user-onboarding.json

# Resume an interrupted plan (skips completed phases)
.claude/scripts/orchestrate.sh --resume plans/002-user-onboarding.json
```

## Agent Files

| Agent | Location | Shared? | Role |
|-------|----------|---------|------|
| Architect | `agents/architect.md` | ✅ Shared | Creates phased implementation plans |
| Pipeline Manager | `agents/pipeline-manager.md` | ✅ Shared | Orchestrates the full pipeline |
| Code Reviewer | `agents/code-reviewer.md` | ✅ Shared | Reviews for correctness, security, quality |
| SDET | `agents/sdet.md` | ✅ Shared | Writes comprehensive test suites |
| Senior Engineer | `{framework}/agents/senior-engineer.md` | Per framework | Implements with framework-specific patterns |
| UI/UX Specialist | `{framework}/agents/ui-ux-specialist.md` | Per framework | Reviews UX with platform-specific criteria |

## Feature Documentation

The pipeline automatically maintains three documentation outputs after each completed plan:

```
docs/
  INDEX.md                                ← Auto-generated overview (regenerated each time)
  features/
    001-competitor-ad-intelligence.md      ← Detailed record of what plan 001 built
    002-user-onboarding.md                ← Detailed record of what plan 002 built
  categories/
    core-platform.md                      ← All core platform features grouped
    integrations.md                       ← All integration features grouped
    ai-automation.md                      ← All AI/automation features grouped
```

**Three views, three purposes:**
- `docs/features/` — "What exactly did plan 007 build?" Full detail: files, endpoints, models, components
- `docs/categories/` — "What can this app do?" Browsable by domain area, entries updated in place
- `docs/INDEX.md` — "Show me everything at a glance." Auto-generated table with links to both

## Adding a New Framework

1. Create a new directory: `mkdir -p myframework/agents myframework/scripts`
2. Create `myframework/agents/senior-engineer.md` with framework-specific coding conventions
3. Create `myframework/agents/ui-ux-specialist.md` with platform-specific UX review criteria
4. Copy and adapt `nextjs/scripts/orchestrate.sh` to `myframework/scripts/orchestrate.sh` (update build commands)
5. Run `setup-workflow.sh myframework` in your project

## CLI Reference

```bash
# Create plan and stop for review (DEFAULT)
.claude/scripts/orchestrate.sh "Feature description"
.claude/scripts/orchestrate.sh @feature-brief.md

# Execute a reviewed plan
.claude/scripts/orchestrate.sh --plan plans/001-feature.json

# Create plan + execute immediately (skip review)
.claude/scripts/orchestrate.sh --auto "Feature description"
.claude/scripts/orchestrate.sh --auto @feature-brief.md

# Resume interrupted plan
.claude/scripts/orchestrate.sh --resume plans/001-feature.json

# View plan status
.claude/scripts/orchestrate.sh --status plans/001-feature.json

# List all plans
.claude/scripts/orchestrate.sh --list

# Manual approval mode (combine with --plan or --auto)
.claude/scripts/orchestrate.sh --interactive --plan plans/001-feature.json
```
