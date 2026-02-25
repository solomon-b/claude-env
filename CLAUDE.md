# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`claude-env` is a shell utility for managing multiple isolated Claude Code configuration environments. It allows creating, switching, and managing separate config directories under `~/.claude/envs/`, with shared config files (settings.json, hooks.json, commands, agents) symlinked from `~/.claude/`.

## Architecture

The entire tool is a single Bash script (`claude-env.sh`) meant to be sourced into the user's shell (`source claude-env.sh`). It exposes one public function `claude-env` that dispatches to private `_claude_env_*` functions.

**Key paths:**
- `~/.claude/` — base config dir, holds shared files
- `~/.claude/envs/<name>/` — per-environment directories
- Shared configs are symlinked into each env; `link`/`unlink` toggle between shared symlink and local copy

**Environment activation** works by setting `CLAUDE_CONFIG_DIR` to the env's path.

## Development

Uses a Nix flake (`flake.nix`) with direnv (`.envrc` / `.envrc.local`) for the dev shell. The flake is currently a placeholder — it doesn't package `claude-env.sh` yet.

## Testing

No test framework is set up. Test changes by sourcing the script and running commands manually:

```bash
source claude-env.sh
claude-env create test-env
claude-env list
claude-env use test-env
claude-env current
```
