# Graft — Git-based File Sync Tool

Sync specific files from source git repositories into your project. Like git submodules, but for individual files.

## Install

```bash
make install
```

Or manually:

```bash
cp graft /usr/local/bin/graft
chmod +x /usr/local/bin/graft
```

### Dependencies

- `bash` (4.0+)
- `git`
- `jq`
- `gh` CLI (for GitHub sources)

## Quick Start

```bash
# Add a file from a GitHub URL
graft add https://github.com/org/repo/blob/main/tsconfig.json

# Install files from the lockfile
graft install

# Update all grafts to latest
graft update
```

## Commands

| Command | Description |
|---------|-------------|
| `graft init` | Create a `.graft` manifest interactively |
| `graft add [--vendor] <url> [dest]` | Add a file from a GitHub blob URL |
| `graft install` | Install files from `.graft.lock` (deterministic) |
| `graft update [name] [file]` | Resolve refs, update lockfile, sync files |
| `graft status` | Show which files differ from lockfile |
| `graft diff [name]` | Show diffs between local and source |
| `graft check` | CI-friendly: exit non-zero if out of sync |

## Manifest Format (`.graft`)

```json
{
  "grafts": [
    {
      "name": "shared-configs",
      "source": "https://github.com/org/shared-configs.git",
      "ref": "main",
      "files": [
        { "src": "tsconfig.json", "vendor": true },
        { "src": ".eslintrc.js", "dest": "config/.eslintrc.js" }
      ]
    }
  ]
}
```

### File options

- `src` (required): path in the source repo
- `dest` (optional): destination path (defaults to `src`)
- `vendor` (optional): if `true`, file is committed to git; if `false` (default), file is gitignored

## Source URL Formats

| Format | Example |
|--------|---------|
| GitHub HTTPS | `https://github.com/org/repo.git` |
| GitHub SSH | `git@github.com:org/repo.git` |
| Local path | `file:///path/to/repo` |
| Other git | `git@gitlab.com:org/repo.git` |

## Makefile

| Target | Description |
|--------|-------------|
| `make install` | Copy `graft` to `/usr/local/bin` and make it executable |
| `make test` | Run all test scripts in `test/` |

## License

ISC
