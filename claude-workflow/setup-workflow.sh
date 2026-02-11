#!/bin/bash
# ============================================================================
# Setup Claude Agent Workflow for a project
# ============================================================================
# Usage:
#   ./setup-workflow.sh nextjs
#   ./setup-workflow.sh react-native
#   CLAUDE_WORKFLOW_HOME=/custom/path ./setup-workflow.sh nextjs
# ============================================================================

set -euo pipefail

WORKFLOW_HOME="${CLAUDE_WORKFLOW_HOME:-$HOME/ai-code-config/claude-workflow}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FRAMEWORK="${1:-}"

if [ -z "$FRAMEWORK" ]; then
    echo -e "${RED}Error: Framework required${NC}"
    echo ""
    echo "Usage: $0 <framework>"
    echo ""
    echo "Available frameworks:"
    for dir in "$WORKFLOW_HOME"/*/; do
        dirname=$(basename "$dir")
        if [ "$dirname" != "agents" ] && [ "$dirname" != "templates" ]; then
            echo "  - $dirname"
        fi
    done
    exit 1
fi

if [ ! -d "$WORKFLOW_HOME" ]; then
    echo -e "${RED}Error: Workflow not found at $WORKFLOW_HOME${NC}"
    echo "Either:"
    echo "  1. Clone the workflow repo to ~/ai-code-config/claude-workflow/"
    echo "  2. Set CLAUDE_WORKFLOW_HOME to the correct path"
    exit 1
fi

if [ ! -d "$WORKFLOW_HOME/$FRAMEWORK" ]; then
    echo -e "${RED}Error: Framework '$FRAMEWORK' not found at $WORKFLOW_HOME/$FRAMEWORK${NC}"
    echo ""
    echo "Available frameworks:"
    for dir in "$WORKFLOW_HOME"/*/; do
        dirname=$(basename "$dir")
        if [ "$dirname" != "agents" ] && [ "$dirname" != "templates" ]; then
            echo "  - $dirname"
        fi
    done
    exit 1
fi

# Verify shared agents exist
for agent in architect pipeline-manager code-reviewer sdet; do
    if [ ! -f "$WORKFLOW_HOME/agents/$agent.md" ]; then
        echo -e "${RED}Error: Missing shared agent $WORKFLOW_HOME/agents/$agent.md${NC}"
        exit 1
    fi
done

# Verify framework agents exist
for agent in senior-engineer ui-ux-specialist; do
    if [ ! -f "$WORKFLOW_HOME/$FRAMEWORK/agents/$agent.md" ]; then
        echo -e "${RED}Error: Missing $FRAMEWORK agent $WORKFLOW_HOME/$FRAMEWORK/agents/$agent.md${NC}"
        exit 1
    fi
done

# Verify framework templates exist
if [ ! -d "$WORKFLOW_HOME/$FRAMEWORK/templates" ]; then
    echo -e "${RED}Error: Missing $WORKFLOW_HOME/$FRAMEWORK/templates${NC}"
    exit 1
fi

# Create directories
mkdir -p .claude docs/features docs/categories

# Symlink shared agents, framework agents, framework scripts, and framework templates
ln -sf "$WORKFLOW_HOME/agents" .claude/shared-agents
ln -sf "$WORKFLOW_HOME/$FRAMEWORK/agents" .claude/agents
ln -sf "$WORKFLOW_HOME/$FRAMEWORK/scripts" .claude/scripts
ln -sf "$WORKFLOW_HOME/$FRAMEWORK/templates" .claude/templates

# Copy docs template if INDEX.md doesn't exist yet
if [ ! -f "docs/INDEX.md" ]; then
    cp "$WORKFLOW_HOME/$FRAMEWORK/templates/docs/INDEX.md" docs/INDEX.md
    echo -e "${GREEN}✅ Created docs/INDEX.md from template${NC}"
fi

echo ""
echo -e "${GREEN}✅ Workflow linked — framework: ${FRAMEWORK}${NC}"
echo ""
echo "  Symlinks:"
echo "    .claude/shared-agents/ → $WORKFLOW_HOME/agents/"
echo "    .claude/agents/        → $WORKFLOW_HOME/$FRAMEWORK/agents/"
echo "    .claude/scripts/       → $WORKFLOW_HOME/$FRAMEWORK/scripts/"
echo "    .claude/templates/     → $WORKFLOW_HOME/$FRAMEWORK/templates/"
echo ""
echo "  Project-specific (not symlinked):"
echo "    docs/INDEX.md         — auto-generated feature index"
echo "    docs/features/        — per-feature documentation"
echo "    docs/categories/      — features grouped by category"
echo "    plans/                — created on first pipeline run"
echo ""
echo "  Get started:"
echo "    .claude/scripts/orchestrate.sh \"Your feature description\""
echo ""
