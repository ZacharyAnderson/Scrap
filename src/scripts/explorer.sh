#!/bin/bash

# Get the directory of this script and find the scrap binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRAP_BIN="$SCRIPT_DIR/../../bin/scrap"

DB_FILE=$HOME/.scrap/scrap.db

if [[ ! -f "$DB_FILE" ]]; then
    echo "Database file not found: $DB_FILE"
    exit 1
fi

if [[ ! -f "$SCRAP_BIN" ]]; then
    echo "Scrap binary not found: $SCRAP_BIN"
    echo "Make sure you've built the project with 'zig build'"
    exit 1
fi

# Check if a search query was provided as an argument
SEARCH_QUERY="$1"
FZF_ARGS=""

if [[ -n "$SEARCH_QUERY" ]]; then
    FZF_ARGS="--query=$SEARCH_QUERY"
fi

# Select a note from the database and preview its content
SELECTED_NOTE=$(sqlite3 -separator $'\t' "$DB_FILE" "SELECT title, tags FROM notes ORDER BY updated_at DESC;" | \
    fzf --delimiter=$'\t' \
        --with-nth=1,2 \
        --prompt="Select a note: " \
        --preview="sqlite3 \"$DB_FILE\" \"SELECT note FROM notes WHERE title = {1} LIMIT 1;\" | bat --style=plain --language=markdown --color=always -" \
        --preview-window="right:60%:wrap" \
        --header="Title | Tags" \
        --height=100% \
        $FZF_ARGS
)

if [[ -n "$SELECTED_NOTE" ]]; then
    TITLE=$(echo "$SELECTED_NOTE" | cut -f1)
    echo "Opening note: $TITLE"
    "$SCRAP_BIN" open "$TITLE"
fi
