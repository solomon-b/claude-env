# claude-env

Multi-environment manager for [Claude Code](https://claude.ai/code). Switch between work and personal Claude accounts while keeping your settings, hooks, and commands shared across all of them.

## How it works

Each environment lives at `~/.claude/envs/<name>/` with its own credentials (`.credentials.json`). When you run `claude-env use <name>`, it sets `CLAUDE_CONFIG_DIR` to that directory, switching which account Claude Code uses.

Settings, hooks, commands, and agents are symlinked from `~/.claude/` into each environment so you only need to configure them once. If you ever need a per-env override for a specific file, `claude-env unlink <file>` replaces the symlink with a local copy.

## Quick start

```bash
# 1. Install (see Install section below)

# 2. Create environments for each account
claude-env create work
claude-env create personal

# 3. Activate and log in to each one
claude-env use work
claude login        # authenticate with your work account

claude-env use personal
claude login        # authenticate with your personal account

# 4. Now just switch whenever you need to
claude-env use work
claude               # uses your work account
```

## Usage

```bash
claude-env create  <name>          # Create a new environment
claude-env list                    # List environments (marks active)
claude-env use     <name>          # Switch to an environment
claude-env current                 # Show active environment
claude-env migrate <path> <name>   # Import existing config dir as an env
claude-env link    <file>          # Replace local file with shared symlink
claude-env unlink  <file>          # Copy shared file locally (per-env override)
claude-env rm      <name>          # Remove an environment
claude-env help                    # Show help
```

## Install

### Nix + home-manager

Add the flake input and enable the module:

```nix
{
  inputs.claude-env.url = "github:<owner>/claude-env";

  # In your home-manager config:
  imports = [ claude-env.homeManagerModules.default ];

  programs.claude-env.enable = true;
}
```

This sources `claude-env.sh` into both bash and zsh automatically.

### Manual install script

```bash
git clone https://github.com/<owner>/claude-env.git
cd claude-env
bash install.sh
```

Copies `claude-env.sh` to `~/.claude-env/` and adds a source line to your shell rc file.

### Source directly

```bash
# Add to your .bashrc or .zshrc:
source /path/to/claude-env.sh
```

## License

MIT
