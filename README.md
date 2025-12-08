# Scrap

A fast, interactive note-taking CLI tool written in Zig with an integrated explorer interface.

## Features

- **Interactive Explorer**: Browse notes with live markdown preview using fzf
- **Tag-based Organization**: Add, edit, and search notes by tags
- **Full-text Search**: Search through note titles and tags
- **Editor Integration**: Works with your favorite editor ($EDITOR)
- **SQLite Backend**: Reliable local storage

## Installation

### Homebrew (macOS)

```bash
brew tap zachanderson/scrap
brew install scrap
```

### Manual Installation

Download the latest release from [GitHub releases](https://github.com/zachanderson/scrap/releases) and place the binary in your PATH.

## Usage

```bash
# Open interactive explorer (default command)
scrap

# Add a new note with tags
scrap add "my-note" tag1 tag2

# Open a specific note
scrap open "my-note"

# Find notes (opens explorer)
scrap find

# Find notes with initial search
scrap find "search term"

# Edit tags on a note
scrap editTag --add "my-note" newtag
scrap editTag --delete "my-note" oldtag

# Delete a note
scrap delete "my-note"

# Show help
scrap help
```

## Requirements

- fzf (for interactive selection)
- bat (for markdown syntax highlighting)
- glow (optional, for better markdown rendering)

## Development

```bash
# Build
zig build

# Run
./zig-out/bin/scrap
```

## License

MIT License