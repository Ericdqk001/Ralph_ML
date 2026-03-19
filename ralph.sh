#!/bin/bash
# Ralph_ML - Autonomous ML pipeline agent loop
# Usage: ./ralph.sh [--prd <path>] [max_iterations]

set -e

# Parse arguments
MAX_ITERATIONS=10
PRD_PATH=""

show_help() {
  echo "Ralph_ML - Autonomous ML pipeline agent loop"
  echo ""
  echo "Usage: ./ralph.sh [OPTIONS] [max_iterations]"
  echo ""
  echo "Options:"
  echo "  --prd <path>        Path to PRD JSON file (default: prd.json in script directory)"
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
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph_ML Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
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

echo "Starting Ralph_ML - Max iterations: $MAX_ITERATIONS"
echo "PRD: $PRD_FILE"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph_ML Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # --- Step 1: Select the highest-priority story where passes == false ---
  STORY_JSON=$(jq -r '
    [.userStories[] | select(.passes == false)]
    | sort_by(.priority)
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

  # --- Step 2: Build prompt and run Claude ---
  PROMPT="$(cat "$SCRIPT_DIR/CLAUDE.md")

## Current Story
- **ID:** $STORY_ID
- **Title:** $STORY_TITLE
- **Test file:** $TEST_FILE
- **Branch:** $BRANCH_NAME
- **PRD file:** $PRD_FILE

Read the test file above and implement code to pass all tests. Commit your code when done."

  echo ""
  echo "--- Spawning Claude for $STORY_ID ---"
  echo "$PROMPT" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr || true

  # --- Step 3: Run pytest to verify ---
  echo ""
  echo "--- Running pytest for $STORY_ID: $TEST_FILE ---"
  if pytest "$TEST_FILE" -v; then
    echo ""
    echo "PASS: $STORY_ID - $STORY_TITLE"

    # --- Step 4: Update PRD to set passes: true ---
    jq --arg sid "$STORY_ID" '
      .userStories |= map(
        if .id == $sid then .passes = true else . end
      )
    ' "$PRD_FILE" > "${PRD_FILE}.tmp" && mv "${PRD_FILE}.tmp" "$PRD_FILE"

    # --- Step 5: Commit PRD update ---
    git add "$PRD_FILE"
    git commit -m "prd: mark $STORY_ID as passing"

    echo "PRD updated: $STORY_ID passes = true"
  else
    echo ""
    echo "FAIL: $STORY_ID - $STORY_TITLE"
    echo "Tests did not pass. Will retry on next iteration."
  fi

  # --- Step 6: Check if all stories now pass ---
  REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
  if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "All stories pass! Ralph_ML completed all tasks."
    exit 0
  fi

  echo "Remaining stories: $REMAINING"
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph_ML reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
