#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE=$HOME/.scrap/scrap.db

if [[ ! -f "$DB_FILE" ]]; then
    echo "Database file not found: $DB_FILE"
    exit 1
fi

# Find scrap binary: installed path, then zig-out dev path, then PATH
if [[ -f "$SCRIPT_DIR/../../bin/scrap" ]]; then
    SCRAP_BIN="$SCRIPT_DIR/../../bin/scrap"
elif [[ -f "$SCRIPT_DIR/../../zig-out/bin/scrap" ]]; then
    SCRAP_BIN="$SCRIPT_DIR/../../zig-out/bin/scrap"
elif command -v scrap &>/dev/null; then
    SCRAP_BIN="$(command -v scrap)"
else
    echo "Scrap binary not found"
    exit 1
fi

# Select a todo and choose an action
SELECTED_TODO=$(sqlite3 -separator $'\t' "$DB_FILE" \
    "SELECT title, priority, tags, CASE WHEN notify_at IS NOT NULL AND notify_at <= datetime('now') THEN '🔴' ELSE '' END as alert FROM todos WHERE status='open' ORDER BY CASE priority WHEN 'high' THEN 1 WHEN 'med' THEN 2 WHEN 'low' THEN 3 END;" | \
    fzf --delimiter=$'\t' \
        --with-nth=1,2,3,4 \
        --prompt="Select a todo: " \
        --header="Title | Priority | Tags | Alert" \
        --height=100% \
        --preview="echo 'Actions: Enter=Done, Ctrl-D=Delete, Ctrl-E=Edit'" \
        --expect="ctrl-d,ctrl-e"
)

if [[ -z "$SELECTED_TODO" ]]; then
    exit 0
fi

KEY=$(echo "$SELECTED_TODO" | head -1)
TITLE=$(echo "$SELECTED_TODO" | tail -1 | cut -f1)

case "$KEY" in
    "ctrl-d")
        "$SCRAP_BIN" todo rm "$TITLE"
        echo "Deleted: $TITLE"
        ;;
    "ctrl-e")
        echo "Edit todo: $TITLE"
        echo "Use: scrap todo edit \"$TITLE\" --priority <low|med|high> --tags <tag1 tag2>"
        ;;
    *)
        "$SCRAP_BIN" todo done "$TITLE"
        echo "Marked done: $TITLE"
        ;;
esac
