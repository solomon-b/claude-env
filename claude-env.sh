#!/usr/bin/env bash
# claude-env: Multi-environment manager for Claude Code
# Source this file in your .zshrc/.bashrc:  source ~/claude-env.sh

CLAUDE_ENV_BASE="${HOME}/.claude"
CLAUDE_ENV_DIR="${CLAUDE_ENV_BASE}/envs"

# Shared config files/dirs that get symlinked from the root ~/.claude/
_CLAUDE_ENV_SHARED=(settings.json hooks.json commands agents)

_claude_env_validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Invalid environment name '$name'. Use only letters, numbers, hyphens, underscores." >&2
    return 1
  fi
}

claude-env() {
  local cmd="${1:-help}"
  shift 2>/dev/null

  case "$cmd" in
    create)     _claude_env_create "$@" ;;
    list|ls)    _claude_env_list "$@" ;;
    use)        _claude_env_use "$@" ;;
    deactivate) _claude_env_deactivate ;;
    link)       _claude_env_link "$@" ;;
    unlink)     _claude_env_unlink "$@" ;;
    rm)         _claude_env_rm "$@" ;;
    migrate)    _claude_env_migrate "$@" ;;
    current)    _claude_env_current ;;
    help|*)     _claude_env_help ;;
  esac
}

_claude_env_help() {
  cat <<'EOF'
claude-env — Multi-environment manager for Claude Code

Usage:
  claude-env create     <name>          Create a new environment
  claude-env list                      List environments (mark active)
  claude-env use        <name>         Activate an environment
  claude-env deactivate                Deactivate current environment
  claude-env link       <file>         Replace local file with shared symlink
  claude-env unlink     <file>         Copy shared file locally (per-env override)
  claude-env rm         <name>         Remove an environment
  claude-env migrate    [--delete] <path> <name>
                                      Import existing config dir as an env
  claude-env current                   Show active environment
  claude-env help                      Show this help
EOF
}

_claude_env_current() {
  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "No environment active (CLAUDE_CONFIG_DIR is unset)"
    return 1
  fi
  local name
  name=$(basename -- "$CLAUDE_CONFIG_DIR")
  echo "$name"
}

_claude_env_deactivate() {
  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "No environment active." >&2
    return 1
  fi
  local name
  name=$(basename -- "$CLAUDE_CONFIG_DIR")
  unset CLAUDE_CONFIG_DIR
  echo "Deactivated environment '$name' (CLAUDE_CONFIG_DIR unset)"
}

_claude_env_create() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: claude-env create <name>" >&2
    return 1
  fi
  _claude_env_validate_name "$name" || return 1

  local env_path="${CLAUDE_ENV_DIR}/${name}"
  if [[ -d "$env_path" ]]; then
    echo "Environment '$name' already exists at $env_path" >&2
    return 1
  fi

  mkdir -p "$env_path"

  # Symlink shared config
  local src target
  for item in "${_CLAUDE_ENV_SHARED[@]}"; do
    src="${CLAUDE_ENV_BASE}/${item}"
    target="${env_path}/${item}"
    if [[ -e "$src" ]]; then
      ln -s "$src" "$target"
      echo "  linked: $item -> $src"
    else
      echo "  skip:   $item (not found in $CLAUDE_ENV_BASE)"
    fi
  done

  echo "Created environment '$name' at $env_path"
  echo "Activate with: claude-env use $name"
  echo "Note: You'll need to authenticate on first use (claude login)"
}

_claude_env_list() {
  if [[ ! -d "$CLAUDE_ENV_DIR" ]]; then
    echo "No environments found. Create one with: claude-env create <name>"
    return 0
  fi

  local active=""
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    active=$(basename -- "$CLAUDE_CONFIG_DIR")
  fi

  local envs=()
  if [[ -n "$(find "$CLAUDE_ENV_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
    for d in "$CLAUDE_ENV_DIR"/*/; do
      [[ -d "$d" ]] && envs+=("$d")
    done
  fi

  if [[ ${#envs[@]} -eq 0 ]]; then
    echo "No environments found. Create one with: claude-env create <name>"
    return 0
  fi

  local name
  for env_path in "${envs[@]}"; do
    name=$(basename -- "$env_path")
    if [[ "$name" == "$active" ]]; then
      echo "* $name  (active)"
    else
      echo "  $name"
    fi
  done
}

_claude_env_use() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: claude-env use <name>" >&2
    return 1
  fi
  _claude_env_validate_name "$name" || return 1

  local env_path="${CLAUDE_ENV_DIR}/${name}"
  if [[ ! -d "$env_path" ]]; then
    echo "Environment '$name' not found. Run 'claude-env list' to see available environments." >&2
    return 1
  fi

  export CLAUDE_CONFIG_DIR="$env_path"
  echo "Switched to '$name' (CLAUDE_CONFIG_DIR=$env_path)"
}

_claude_env_link() {
  local file="$1"
  if [[ -z "$file" ]]; then
    echo "Usage: claude-env link <file>" >&2
    echo "Replaces a local file in the current env with a symlink to the shared version." >&2
    return 1
  fi

  if [[ "$file" == */* ]]; then
    echo "Invalid file name '$file'. Must be a plain filename, not a path." >&2
    return 1
  fi

  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "No environment active. Run 'claude-env use <name>' first." >&2
    return 1
  fi

  local src="${CLAUDE_ENV_BASE}/${file}"
  local target="${CLAUDE_CONFIG_DIR}/${file}"

  if [[ ! -e "$src" ]]; then
    echo "Shared file '$file' not found at $src" >&2
    return 1
  fi

  if [[ -L "$target" ]]; then
    echo "'$file' is already a symlink" >&2
    return 1
  fi

  if [[ -e "$target" ]]; then
    local backup="${target}.local-backup"
    if [[ -e "$backup" ]]; then
      echo "  warning: overwriting existing backup $backup" >&2
    fi
    mv "$target" "$backup"
    echo "  backed up: $target -> $backup"
  fi

  ln -s "$src" "$target"
  echo "  linked: $file -> $src"
}

_claude_env_unlink() {
  local file="$1"
  if [[ -z "$file" ]]; then
    echo "Usage: claude-env unlink <file>" >&2
    echo "Copies the shared file locally for per-env override." >&2
    return 1
  fi

  if [[ "$file" == */* ]]; then
    echo "Invalid file name '$file'. Must be a plain filename, not a path." >&2
    return 1
  fi

  if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "No environment active. Run 'claude-env use <name>' first." >&2
    return 1
  fi

  local target="${CLAUDE_CONFIG_DIR}/${file}"

  if [[ ! -L "$target" ]]; then
    echo "'$file' is not a symlink — already local" >&2
    return 1
  fi

  local source
  source=$(readlink "$target")

  if [[ ! -e "$source" ]]; then
    echo "Symlink target '$source' does not exist" >&2
    return 1
  fi

  rm "$target"
  cp -r "$source" "$target"
  echo "  unlinked: $file (copied from $source)"
}

_claude_env_rm() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: claude-env rm <name>" >&2
    return 1
  fi
  _claude_env_validate_name "$name" || return 1

  local env_path="${CLAUDE_ENV_DIR}/${name}"
  if [[ ! -d "$env_path" ]]; then
    echo "Environment '$name' not found." >&2
    return 1
  fi

  echo "This will permanently delete: $env_path"
  printf "Are you sure? [y/N] "
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    local resolved resolved_base
    resolved=$(cd "$env_path" 2>/dev/null && pwd)
    resolved_base=$(cd "$CLAUDE_ENV_DIR" 2>/dev/null && pwd)
    if [[ "$resolved" != "${resolved_base}/"* ]]; then
      echo "Refusing to delete path outside envs directory: $resolved" >&2
      return 1
    fi
    rm -rf "$resolved"
    echo "Removed environment '$name'"

    # Unset CLAUDE_CONFIG_DIR if it pointed to the removed env
    if [[ "${CLAUDE_CONFIG_DIR:-}" == "$env_path" ]]; then
      unset CLAUDE_CONFIG_DIR
      echo "Deactivated environment (CLAUDE_CONFIG_DIR unset)"
    fi
  else
    echo "Cancelled."
  fi
}

_claude_env_migrate() {
  local delete_original=0
  if [[ "${1:-}" == "--delete" ]]; then
    delete_original=1
    shift
  fi

  local source_path="$1"
  local name="$2"
  local orig_source="$source_path"

  if [[ -z "$source_path" || -z "$name" ]]; then
    echo "Usage: claude-env migrate [--delete] <path> <name>" >&2
    echo "Example: claude-env migrate ~/.claude-personal personal" >&2
    return 1
  fi
  _claude_env_validate_name "$name" || return 1

  # Resolve to absolute path
  source_path=$(cd "$source_path" 2>/dev/null && pwd)
  if [[ ! -d "$source_path" ]]; then
    echo "Source directory '$orig_source' not found." >&2
    return 1
  fi

  local env_path="${CLAUDE_ENV_DIR}/${name}"
  if [[ -d "$env_path" ]]; then
    echo "Environment '$name' already exists at $env_path" >&2
    return 1
  fi

  mkdir -p "$CLAUDE_ENV_DIR"

  # Copy the source dir (preserve original until migration succeeds)
  cp -r "$source_path" "$env_path"
  echo "Copied $source_path -> $env_path"

  # Replace shared config files with symlinks
  local migrate_failed=0
  local shared local_copy backup
  for item in "${_CLAUDE_ENV_SHARED[@]}"; do
    shared="${CLAUDE_ENV_BASE}/${item}"
    local_copy="${env_path}/${item}"

    if [[ ! -e "$shared" ]]; then
      echo "  skip: $item (not found in $CLAUDE_ENV_BASE)"
      continue
    fi

    if [[ -L "$local_copy" ]]; then
      # Already a symlink — update it to point to shared
      rm "$local_copy"
      ln -s "$shared" "$local_copy" || { migrate_failed=1; break; }
      echo "  relinked: $item -> $shared"
    elif [[ -e "$local_copy" ]]; then
      # Local copy exists — back it up and replace with symlink
      backup="${local_copy}.pre-migrate"
      mv "$local_copy" "$backup"
      ln -s "$shared" "$local_copy" || { migrate_failed=1; break; }
      echo "  linked: $item -> $shared (backup at ${item}.pre-migrate)"
    else
      # No local copy — just symlink
      ln -s "$shared" "$local_copy" || { migrate_failed=1; break; }
      echo "  linked: $item -> $shared"
    fi
  done

  if [[ $migrate_failed -ne 0 ]]; then
    echo "Migration failed during symlink setup. Cleaning up..." >&2
    rm -rf "$env_path"
    echo "Original directory at $source_path is unchanged." >&2
    return 1
  fi

  echo "Migrated '$name' successfully."
  echo "Activate with: claude-env use $name"

  if [[ $delete_original -eq 1 ]]; then
    local resolved_source
    resolved_source=$(cd "$source_path" 2>/dev/null && pwd)
    if [[ "$resolved_source" == "$HOME" || "$resolved_source" == "${CLAUDE_ENV_BASE}" || "$resolved_source" == "${CLAUDE_ENV_DIR}" ]]; then
      echo "Warning: refusing to delete critical path '$resolved_source'. Please remove the original manually." >&2
    else
      printf "Delete original directory '%s'? [y/N] " "$source_path"
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$source_path"
        echo "Removed original $source_path"
      else
        echo "Original directory preserved at $source_path"
      fi
    fi
  else
    echo "Original directory preserved at $source_path"
    echo "You can remove it manually after verifying the migration."
  fi
}
