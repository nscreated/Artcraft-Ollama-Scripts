# Kit Craft - Kit + Ollama + Artcraft Setup Scripts

One-line setup to connect [Mark3 Labs Kit](https://github.com/mark3labs/kit) with [Ollama](https://ollama.com/) and the [Artcraft](https://getartcraft.com/apps) app suite.

## What It Does

This repository contains two bash scripts that automate configuring **Kit** to use an Ollama instance (with Qwen models) as the backend for all Artcraft apps — each providing a custom MCP server attachment.

### `setup-kit-craft.sh` — Install & configure

1. Installs Kit if it is not already present (via the official install script).
2. Detects which Artcraft `*-cli` tools are installed and reachable on PATH.
3. For each detected app, writes:
   - A **headless** config (`~/.config/kit-apps/<app>.yml`) using `<app>-cli mcp`.
   - A **live** config (`~/.config/kit-apps/<app>-live.yml`) that attaches to the running app window via its control port.
   - A **launcher script** (`~/.local/bin/kit-<app>`) that starts the app, waits for the port, then invokes Kit.
4. Writes a combined config (`~/.kit.yml`) containing all detected apps (unless `--no-combined` is given).

### `uninstall-kit-craft.sh` — Clean up

Reverses everything the setup script did:

1. Removes `kit-<app>` launcher scripts.
2. Removes per-app configs in `~/.config/kit-apps/`.
3. Removes or restores `~/.kit.yml` (backed up during setup).
4. Removes `~/Documents/Artcraft-In` and `~/Documents/Artcraft-Out` **only if empty**.
5. Optionally removes the Kit binary and its saved data (`~/.kit`).

## Supported Apps

| App | Control Port | Notes |
|-----|-------------|-------|
| photocraft | 7980 | Uses `--bridge`; requires control token file + folder roots |
| vectorcraft | 7981 | Uses `--connect` |
| filmcraft | 7982 | Uses `--bridge` |
| lightcraft | 7983 | Uses `--connect` |
| effectcraft | 7984 | Uses `--bridge` |
| designcraft | 7985 | Uses `--connect` |
| figcraft | 7986 | Uses `--connect` |
| texturecraft | 7987 | Uses `--connect` |
| materialcraft | 7988 | Uses `--connect` |
| wordcraft | 7989 | Uses `--connect` |
| soundcraft | 7990 | Uses `--connect` |
| deckcraft | 7991 | Uses `--connect` |
| cadcraft | 7992 | Uses `--connect` |
| gridcraft | 7993 | Uses `--connect` |
| pdfcraft | — | Headless only (no window) |
| craft-anything | — | Headless only (no window) |

## Quick Start

### Prerequisites

- **Linux** — these scripts depend on GNU coreutils (`timeout`, `seq`) and are written for bash 4+. They will not work with macOS's default Bash (3.2).
- [Ollama](https://ollama.com/) running on your network (default port `11434`).
- At least one Artcraft CLI tool **installed as a system-level binary** (`photocraft-cli` confirmed; others follow the `<name>-cli` pattern). AppImages or portable zips will not be detected — each `*-cli` must be on your `$PATH` and executable.

### Install & configure

```bash
# Interactively — prompts for Ollama URL and model name
./setup-kit-craft.sh

# Or supply values via environment variables to skip prompts
OLLAMA_URL=http://192.168.1.10:11434 MODEL=ollama/qwen3.6:35b-a3b ./setup-kit-craft.sh
```

### Run an app through Kit

```bash
# Launches PhotoCraft window, then attaches Kit via MCP
kit-photocraft

# Force headless mode (never opens the app window)
KIT_MCP_MODE=headless kit-photocraft -- some-input.jpg

# Open a specific file
KIT_APP_ARGS="my-file.pcf" kit-photocraft
```

### Plain `kit` command

Running `kit` without an app prefix always uses the **headless** mode of all detected apps combined (`~/.kit.yml`).

## Options

Both scripts support:

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would happen without making changes |
| `--help` / `-h` | Print the script documentation and exit |

Additional options for `uninstall-kit-craft.sh`:

| Flag | Description |
|------|-------------|
| `--yes` / `--assume-yes` | Automatically answer yes to prompts |
| `--keep-kit` | Skip removing the Kit binary and its data |

## Override Variables

You can override default directories and paths by setting these environment variables before running either script:

| Variable | Default | Description |
|----------|---------|-------------|
| `READ_ROOT` | `$HOME/Documents/Artcraft-In` | Input directory (read root) |
| `WRITE_ROOT` | `$HOME/Documents/Artcraft-Out` | Output directory (write root) |
| `CONFIG_DIR` | `$HOME/.config/kit-apps` | Per-app config folder |
| `BIN_DIR` | `$HOME/.local/bin` | Launcher script folder |

## Default Configuration Generated

Each per-app config uses these Ollama settings:

```yaml
model: ollama/<MODEL>
provider-url: <OLLAMA_URL>
include-core-tools:
  - ls
  - find
thinking-level: off
max-tokens: 4096
stream: true
```

## Safety

- **No files are deleted** during setup or uninstall unless they were created by these scripts.
- The uninstall script only removes `Artcraft-In` / `Artcraft-Out` if they are empty — your personal files are never touched.
- The uninstall script asks before removing the Kit binary and its saved data (`~/.kit`).

## License

MIT (or specify your preferred license)
