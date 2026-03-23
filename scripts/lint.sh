#!/usr/bin/env bash
set -euo pipefail

# Lint Python files with Ruff (auto-fix safe issues, then report)
# Usage: scripts/lint.sh [paths...]
# Defaults to src/ and tests/ if no paths given

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v ruff &>/dev/null; then
    echo "ruff not found. Installing into active environment..."
    pip install ruff
fi

if [ $# -gt 0 ]; then
    PATHS=("$@")
else
    PATHS=("src/" "tests/")
fi

# Filter to paths that actually exist
EXISTING=()
for p in "${PATHS[@]}"; do
    if [ -e "$p" ]; then
        EXISTING+=("$p")
    fi
done

if [ ${#EXISTING[@]} -eq 0 ]; then
    echo "No target paths found. Nothing to lint."
    exit 0
fi

echo "Linting: ${EXISTING[*]}"
echo "--- Auto-fixing safe issues ---"
ruff check --fix "${EXISTING[@]}" || true
echo "--- Remaining issues ---"
ruff check "${EXISTING[@]}"
echo "Done. No remaining issues."
