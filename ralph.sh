#!/bin/bash
# Ralph_ML - Autonomous ML pipeline agent loop
# Usage: ./ralph.sh [--prd <path>] [--model <model>] [--max-turns <n>] [max_iterations]

set -e

# Parse arguments
MAX_ITERATIONS=10
MAX_FAILURES=3
PRD_PATH=""
MODEL="opus"
MAX_TURNS=50

# Allowed tools — whitelist what Claude can use (replaces --dangerously-skip-permissions)
# Each entry is a separate tool or Bash pattern. Bash(git *) is intentionally avoided
# because it would permit destructive commands like git clean/git rm. Instead we
# whitelist each safe git subcommand individually.
ALLOWED_TOOLS=(
  "Read" "Write" "Edit" "MultiEdit" "Glob" "Grep" "Task" "TodoWrite"
  "WebFetch" "WebSearch" "NotebookEdit"
  "Bash(git add *)" "Bash(git commit *)" "Bash(git diff *)"
  "Bash(git log *)" "Bash(git status)" "Bash(git status *)"
  "Bash(git push *)" "Bash(git pull *)" "Bash(git fetch *)"
  "Bash(git checkout *)" "Bash(git branch *)" "Bash(git stash *)"
  "Bash(git merge *)" "Bash(git tag *)"
  "Bash(pytest)" "Bash(python *)" "Bash(pip install *)" "Bash(uv *)"
)

show_help() {
  echo "Ralph_ML - Autonomous ML pipeline agent loop"
  echo ""
  echo "Usage: ./ralph.sh [OPTIONS] [max_iterations]"
  echo ""
  echo "Options:"
  echo "  --prd <path>        Path to PRD JSON file (default: prd.json in script directory)"
  echo "  --model <model>     Claude model to use (default: opus)"
  echo "  --max-turns <n>     Max agentic turns per story (default: 50)"
  echo "  --help              Show this help message"
  echo ""
  echo "Each story in the PRD specifies a test_file. ralph.sh selects the story,"
  echo "spawns Claude to implement code, then runs pytest to verify. On pass,"
  echo "ralph.sh updates the PRD programmatically."
  echo ""
  echo "Examples:"
  echo "  ./ralph.sh                              # Default: 10 iterations, prd.json"
  echo "  ./ralph.sh 20                           # 20 iterations"
  echo "  ./ralph.sh --prd tasks/method_a/prd.json 15"
  echo "  ./ralph.sh --model sonnet                    # Use sonnet model"
  echo "  ./ralph.sh --model sonnet --max-turns 80     # Sonnet with 80 turns per story"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --help)
      show_help
      ;;
    --prd)
      PRD_PATH="$2"
      shift 2
      ;;
    --prd=*)
      PRD_PATH="${1#*=}"
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#*=}"
      shift
      ;;
    --max-turns)
      MAX_TURNS="$2"
      shift 2
      ;;
    --max-turns=*)
      MAX_TURNS="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set PRD file path (default: prd.json in script directory)
if [ -n "$PRD_PATH" ]; then
  # If relative path, resolve relative to current working directory
  if [[ "$PRD_PATH" != /* ]]; then
    PRD_FILE="$(cd "$(dirname "$PRD_PATH")" 2>/dev/null && pwd)/$(basename "$PRD_PATH")"
  else
    PRD_FILE="$PRD_PATH"
  fi
else
  PRD_FILE="$SCRIPT_DIR/prd.json"
fi

PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
LEARNINGS_FILE="$SCRIPT_DIR/learnings.md"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph-ml/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph-ml/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$LEARNINGS_FILE" ] && cp "$LEARNINGS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph_ML Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"

    # Reset learnings file for new run
    echo "# Learnings" > "$LEARNINGS_FILE"
    echo "" >> "$LEARNINGS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph_ML Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Initialize learnings file if it doesn't exist
if [ ! -f "$LEARNINGS_FILE" ]; then
  echo "# Learnings" > "$LEARNINGS_FILE"
  echo "" >> "$LEARNINGS_FILE"
fi

echo "Starting Ralph_ML - Max iterations: $MAX_ITERATIONS"
echo "PRD: $PRD_FILE"
echo "Model: $MODEL"
echo "Max turns per story: $MAX_TURNS"

ITERATION=0
CONSECUTIVE_FAILURES=0

while true; do
  ITERATION=$((ITERATION + 1))

  # --- Safety cap: stop if we exceed max iterations ---
  if [ "$ITERATION" -gt "$MAX_ITERATIONS" ]; then
    echo ""
    echo "Ralph_ML reached max iterations ($MAX_ITERATIONS) without completing all tasks."
    echo "Check $PROGRESS_FILE for status."
    exit 1
  fi

  echo ""
  echo "==============================================================="
  echo "  Ralph_ML Iteration $ITERATION of $MAX_ITERATIONS"
  echo "==============================================================="

  # --- Step 1: Select the next story (by implementation_order) where passes == false ---
  STORY_JSON=$(jq -r '
    [.userStories[] | select(.passes == false)]
    | sort_by(.implementation_order)
    | first // empty
  ' "$PRD_FILE")

  if [ -z "$STORY_JSON" ]; then
    echo ""
    echo "All stories pass! Ralph_ML completed all tasks."
    exit 0
  fi

  STORY_ID=$(echo "$STORY_JSON" | jq -r '.id')
  STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title')
  TEST_FILE=$(echo "$STORY_JSON" | jq -r '.test_file')
  BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE")

  echo "Story:     $STORY_ID - $STORY_TITLE"
  echo "Test file: $TEST_FILE"
  echo "Branch:    $BRANCH_NAME"

  # --- Step 2: Snapshot git state before Claude runs ---
  GIT_SHA_BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "")

  # --- Step 3: Build prompt and run Claude ---
  PROMPT="$(cat "$SCRIPT_DIR/prompt.md")

## Current Story
- **ID:** $STORY_ID
- **Title:** $STORY_TITLE
- **Test file:** $TEST_FILE
- **Branch:** $BRANCH_NAME
- **PRD file:** $PRD_FILE

Read the test file and implement code to pass all tests. Commit your code when done."

  echo ""
  echo "--- Spawning Claude for $STORY_ID ---"
  CLAUDE_CMD=(claude --model "$MODEL" --max-turns "$MAX_TURNS" --print --allowedTools "${ALLOWED_TOOLS[@]}")
  echo "$PROMPT" | "${CLAUDE_CMD[@]}" 2>&1 | tee /dev/stderr || true

  # --- Step 4: Run pytest to verify ---
  echo ""
  echo "--- Running pytest for $STORY_ID: $TEST_FILE ---"
  if pytest "$TEST_FILE" -v; then
    echo ""
    echo "PASS: $STORY_ID - $STORY_TITLE"
    CONSECUTIVE_FAILURES=0

    # --- Step 5: Update PRD to set passes: true ---
    jq --arg sid "$STORY_ID" '
      .userStories |= map(
        if .id == $sid then .passes = true else . end
      )
    ' "$PRD_FILE" > "${PRD_FILE}.tmp" && mv "${PRD_FILE}.tmp" "$PRD_FILE"

    # --- Step 6: Commit PRD update ---
    git add "$PRD_FILE"
    git commit -m "prd: mark $STORY_ID as passing"

    echo "PRD updated: $STORY_ID passes = true"
  else
    echo ""
    echo "FAIL: $STORY_ID - $STORY_TITLE"

    # --- Circuit breaker: detect no-progress iterations ---
    GIT_SHA_AFTER=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [ "$GIT_SHA_BEFORE" = "$GIT_SHA_AFTER" ] && git diff --quiet 2>/dev/null; then
      # No commits and no uncommitted changes — no progress at all
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      echo "No progress detected ($CONSECUTIVE_FAILURES/$MAX_FAILURES)"
      if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_FAILURES" ]; then
        echo ""
        echo "Circuit breaker: $MAX_FAILURES consecutive iterations with no progress."
        echo "The agent may be stuck on $STORY_ID. Check $PROGRESS_FILE for details."
        exit 1
      fi
    else
      # Files were changed or committed — progress was made, just tests didn't pass yet
      CONSECUTIVE_FAILURES=0
      echo "Tests failed but progress was made. Retrying..."
    fi
  fi

  # --- Step 7: Check if all stories now pass ---
  REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
  if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "All stories pass! Ralph_ML completed all tasks."
    exit 0
  fi

  echo "Remaining stories: $REMAINING"
  echo "Iteration $ITERATION complete. Continuing..."
  sleep 2
done
