#!/usr/bin/env bash
set -euo pipefail

# Test harness for claude-env
# Runs in an isolated temp directory to avoid touching real ~/.claude

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $1"
  [[ -n "${2:-}" ]] && echo "        $2"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "--- $1 ---"
}

# Set up isolated environment
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export HOME="$TMPDIR/home"
mkdir -p "$HOME"

# Re-source to pick up the new HOME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/claude-env.sh"

# Create shared config files and directories
mkdir -p "$CLAUDE_ENV_BASE"
echo '{}' > "$CLAUDE_ENV_BASE/settings.json"
echo '{}' > "$CLAUDE_ENV_BASE/hooks.json"
mkdir -p "$CLAUDE_ENV_BASE/commands"
mkdir -p "$CLAUDE_ENV_BASE/agents"

# -------------------------------------------------------
# Name validation
# -------------------------------------------------------
run_test "name validation: rejects path traversal"
if claude-env create "../../etc" 2>/dev/null; then
  fail "should reject path traversal name"
else
  pass "rejects ../../etc"
fi

run_test "name validation: rejects slashes"
if claude-env create "foo/bar" 2>/dev/null; then
  fail "should reject name with slash"
else
  pass "rejects foo/bar"
fi

run_test "name validation: rejects dots"
if claude-env create "foo.bar" 2>/dev/null; then
  fail "should reject name with dot"
else
  pass "rejects foo.bar"
fi

run_test "name validation: rejects empty name"
if claude-env create "" 2>/dev/null; then
  fail "should reject empty name"
else
  pass "rejects empty name"
fi

run_test "name validation: accepts valid names"
claude-env create "my-env_01" >/dev/null
if [[ -d "$CLAUDE_ENV_DIR/my-env_01" ]]; then
  pass "accepts my-env_01"
else
  fail "should accept valid name"
fi

# -------------------------------------------------------
# Create
# -------------------------------------------------------
run_test "create: basic creation"
claude-env create "test-env" >/dev/null
if [[ -d "$CLAUDE_ENV_DIR/test-env" ]]; then
  pass "directory created"
else
  fail "directory not created"
fi

run_test "create: symlinks shared configs"
if [[ -L "$CLAUDE_ENV_DIR/test-env/settings.json" ]]; then
  pass "settings.json symlinked"
else
  fail "settings.json not symlinked"
fi

run_test "create: rejects duplicate name"
if claude-env create "test-env" 2>/dev/null; then
  fail "should reject duplicate"
else
  pass "rejects duplicate name"
fi

run_test "create: symlinks shared directories"
if [[ -L "$CLAUDE_ENV_DIR/test-env/commands" && -L "$CLAUDE_ENV_DIR/test-env/agents" ]]; then
  pass "commands and agents directories symlinked"
else
  fail "shared directories not symlinked"
fi

# -------------------------------------------------------
# Help
# -------------------------------------------------------
run_test "help: shows usage information"
output=$(claude-env help)
if [[ "$output" == *"Multi-environment manager"* && "$output" == *"create"* && "$output" == *"list"* ]]; then
  pass "help shows usage info"
else
  fail "help output missing expected content" "$output"
fi

run_test "help: shown for unknown command"
output=$(claude-env unknown-command)
if [[ "$output" == *"Multi-environment manager"* ]]; then
  pass "unknown command shows help"
else
  fail "unknown command did not show help" "$output"
fi

# -------------------------------------------------------
# List
# -------------------------------------------------------
run_test "list: shows environments"
output=$(claude-env list)
if [[ "$output" == *"test-env"* ]]; then
  pass "lists test-env"
else
  fail "test-env not in list" "$output"
fi

run_test "list: ls alias works"
output=$(claude-env ls)
if [[ "$output" == *"test-env"* ]]; then
  pass "ls alias works"
else
  fail "ls alias did not list envs" "$output"
fi

# -------------------------------------------------------
# Use
# -------------------------------------------------------
run_test "use: activates environment"
claude-env use "test-env" >/dev/null
if [[ "$CLAUDE_CONFIG_DIR" == "$CLAUDE_ENV_DIR/test-env" ]]; then
  pass "CLAUDE_CONFIG_DIR set correctly"
else
  fail "CLAUDE_CONFIG_DIR wrong: $CLAUDE_CONFIG_DIR"
fi

run_test "use: rejects nonexistent env"
if claude-env use "nonexistent" 2>/dev/null; then
  fail "should reject nonexistent env"
else
  pass "rejects nonexistent env"
fi

run_test "use: validates name"
if claude-env use "../bad" 2>/dev/null; then
  fail "should reject bad name"
else
  pass "rejects bad name in use"
fi

# -------------------------------------------------------
# Current
# -------------------------------------------------------
run_test "current: shows active env"
claude-env use "test-env" >/dev/null
output=$(claude-env current)
if [[ "$output" == "test-env" ]]; then
  pass "shows test-env"
else
  fail "expected test-env, got: $output"
fi

# -------------------------------------------------------
# Deactivate
# -------------------------------------------------------
run_test "deactivate: unsets CLAUDE_CONFIG_DIR"
claude-env use "test-env" >/dev/null
claude-env deactivate >/dev/null
if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  pass "CLAUDE_CONFIG_DIR unset"
else
  fail "CLAUDE_CONFIG_DIR still set: $CLAUDE_CONFIG_DIR"
fi

run_test "deactivate: fails when no env active"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
if claude-env deactivate 2>/dev/null; then
  fail "should fail when no env active"
else
  pass "fails when no env active"
fi

# -------------------------------------------------------
# List with active marker
# -------------------------------------------------------
run_test "list: marks active env"
claude-env use "test-env" >/dev/null
output=$(claude-env list)
if [[ "$output" == *"* test-env"* ]]; then
  pass "active env marked with *"
else
  fail "active marker missing" "$output"
fi

# -------------------------------------------------------
# Link / Unlink
# -------------------------------------------------------
run_test "link: rejects path traversal in file arg"
claude-env use "test-env" >/dev/null
if claude-env link "../settings.json" 2>/dev/null; then
  fail "should reject path in file arg"
else
  pass "rejects ../settings.json"
fi

run_test "unlink: converts symlink to local copy"
claude-env use "test-env" >/dev/null
# settings.json should be a symlink from create
if [[ -L "$CLAUDE_CONFIG_DIR/settings.json" ]]; then
  claude-env unlink "settings.json" >/dev/null
  if [[ ! -L "$CLAUDE_CONFIG_DIR/settings.json" && -f "$CLAUDE_CONFIG_DIR/settings.json" ]]; then
    pass "symlink replaced with local copy"
  else
    fail "unlink didn't create local copy"
  fi
else
  fail "precondition: settings.json should be a symlink"
fi

run_test "link: re-links a local file back to shared"
# settings.json is now local from the previous test
claude-env link "settings.json" >/dev/null
if [[ -L "$CLAUDE_CONFIG_DIR/settings.json" ]]; then
  pass "file re-linked as symlink"
else
  fail "link didn't create symlink"
fi

run_test "link: creates backup of local file"
# Unlink first to get a local copy, then link again
claude-env unlink "settings.json" >/dev/null
claude-env link "settings.json" >/dev/null
if [[ -f "$CLAUDE_CONFIG_DIR/settings.json.local-backup" ]]; then
  pass "backup created"
else
  fail "no backup file found"
fi

run_test "link: warns when overwriting existing backup"
claude-env use "test-env" >/dev/null
# Ensure we have a local copy to link
[[ -L "$CLAUDE_CONFIG_DIR/settings.json" ]] && claude-env unlink "settings.json" >/dev/null
output=$(claude-env link "settings.json" 2>&1)
# Now unlink and link again — should warn about overwriting backup
claude-env unlink "settings.json" >/dev/null
output=$(claude-env link "settings.json" 2>&1)
if [[ "$output" == *"warning"* && "$output" == *"overwriting"* ]]; then
  pass "warns about backup overwrite"
else
  fail "no overwrite warning" "$output"
fi

run_test "unlink: rejects path traversal in file arg"
if claude-env unlink "foo/bar" 2>/dev/null; then
  fail "should reject path in file arg"
else
  pass "rejects foo/bar"
fi

run_test "link: fails when no env active"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
if claude-env link "settings.json" 2>/dev/null; then
  fail "should fail with no env active"
else
  pass "fails with no env active"
fi

run_test "unlink: fails when no env active"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
if claude-env unlink "settings.json" 2>/dev/null; then
  fail "should fail with no env active"
else
  pass "fails with no env active"
fi

run_test "link: fails when shared file does not exist"
claude-env use "test-env" >/dev/null
if claude-env link "nonexistent.json" 2>/dev/null; then
  fail "should fail for missing shared file"
else
  pass "fails for missing shared file"
fi

run_test "link: fails when file is already a symlink"
claude-env use "test-env" >/dev/null
# settings.json should be a symlink after the earlier re-link test
if [[ -L "$CLAUDE_CONFIG_DIR/settings.json" ]]; then
  if claude-env link "settings.json" 2>/dev/null; then
    fail "should reject already-symlinked file"
  else
    pass "rejects already-symlinked file"
  fi
else
  fail "precondition: settings.json should be a symlink"
fi

run_test "unlink: fails when file is not a symlink"
claude-env use "test-env" >/dev/null
# Create a regular file that isn't a symlink
echo '{}' > "$CLAUDE_CONFIG_DIR/local-only.json"
if claude-env unlink "local-only.json" 2>/dev/null; then
  fail "should reject non-symlink file"
else
  pass "rejects non-symlink file"
fi
rm -f "$CLAUDE_CONFIG_DIR/local-only.json"

run_test "link: creates fresh symlink when file absent in env"
claude-env use "test-env" >/dev/null
# Remove hooks.json from env if present, so link creates it fresh
rm -f "$CLAUDE_CONFIG_DIR/hooks.json"
claude-env link "hooks.json" >/dev/null
if [[ -L "$CLAUDE_CONFIG_DIR/hooks.json" ]]; then
  pass "fresh symlink created for absent file"
else
  fail "symlink not created for absent file"
fi

run_test "unlink: fails on dangling symlink"
claude-env use "test-env" >/dev/null
# Create a symlink pointing to a nonexistent target
ln -sf "$TMPDIR/nonexistent-file" "$CLAUDE_CONFIG_DIR/dangling.json"
if claude-env unlink "dangling.json" 2>/dev/null; then
  fail "should fail on dangling symlink"
else
  pass "fails on dangling symlink"
fi
rm -f "$CLAUDE_CONFIG_DIR/dangling.json"

run_test "current: fails when no env active"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
if claude-env current 2>/dev/null; then
  fail "should fail with no env active"
else
  pass "returns 1 with no env active"
fi

# -------------------------------------------------------
# Migrate
# -------------------------------------------------------
run_test "migrate: imports existing directory"
migrate_src="$TMPDIR/existing-config"
mkdir -p "$migrate_src"
echo '{"custom": true}' > "$migrate_src/settings.json"
claude-env migrate "$migrate_src" "migrated-env" >/dev/null
if [[ -d "$CLAUDE_ENV_DIR/migrated-env" ]]; then
  pass "env directory created"
else
  fail "env directory not created"
fi

run_test "migrate: preserves original by default"
if [[ -d "$migrate_src" ]]; then
  pass "original preserved"
else
  fail "original was deleted"
fi
rm -rf "$migrate_src"

run_test "migrate: creates backups for existing configs"
if [[ -f "$CLAUDE_ENV_DIR/migrated-env/settings.json.pre-migrate" ]]; then
  pass "pre-migrate backup created"
else
  fail "no pre-migrate backup"
fi

run_test "migrate: symlinks shared configs"
if [[ -L "$CLAUDE_ENV_DIR/migrated-env/settings.json" ]]; then
  pass "settings.json symlinked after migration"
else
  fail "settings.json not symlinked"
fi

run_test "migrate: --delete removes original with confirmation"
migrate_del_src="$TMPDIR/delete-config"
mkdir -p "$migrate_del_src"
echo '{}' > "$migrate_del_src/settings.json"
claude-env migrate --delete "$migrate_del_src" "del-env" <<< "y" >/dev/null
if [[ ! -d "$migrate_del_src" ]]; then
  pass "original removed with --delete"
else
  fail "original still exists after --delete"
fi

run_test "migrate: --delete preserves original on cancel"
migrate_keep_src="$TMPDIR/keep-config"
mkdir -p "$migrate_keep_src"
claude-env migrate --delete "$migrate_keep_src" "keep-env" <<< "n" >/dev/null
if [[ -d "$migrate_keep_src" ]]; then
  pass "original preserved on cancel"
else
  fail "original deleted despite cancel"
fi

run_test "migrate: --delete refuses to delete critical paths"
# Create a source that resolves to HOME
mkdir -p "$TMPDIR/home-link"
ln -sf "$HOME" "$TMPDIR/home-link/target"
# We can't easily test this without making $source_path resolve to HOME,
# so we test the guard indirectly by confirming HOME still exists after
# trying to migrate from HOME itself
critical_env_name="critical-test"
output=$(claude-env migrate --delete "$HOME" "$critical_env_name" <<< "y" 2>&1 || true)
if [[ -d "$HOME" ]]; then
  pass "HOME not deleted"
else
  fail "HOME was deleted!"
fi
# Clean up the env if it was created
rm -rf "$CLAUDE_ENV_DIR/$critical_env_name"
rm -rf "$TMPDIR/home-link"

run_test "migrate: skips shared items not in base"
migrate_no_shared_src="$TMPDIR/no-shared-config"
mkdir -p "$migrate_no_shared_src"
# Temporarily remove shared configs
mv "$CLAUDE_ENV_BASE/settings.json" "$CLAUDE_ENV_BASE/settings.json.bak"
mv "$CLAUDE_ENV_BASE/hooks.json" "$CLAUDE_ENV_BASE/hooks.json.bak"
mv "$CLAUDE_ENV_BASE/commands" "$CLAUDE_ENV_BASE/commands.bak"
mv "$CLAUDE_ENV_BASE/agents" "$CLAUDE_ENV_BASE/agents.bak"
output=$(claude-env migrate "$migrate_no_shared_src" "no-shared-env" 2>&1)
if [[ "$output" == *"skip"* ]]; then
  pass "skips missing shared configs"
else
  fail "should report skipped items" "$output"
fi
# Restore shared configs
mv "$CLAUDE_ENV_BASE/settings.json.bak" "$CLAUDE_ENV_BASE/settings.json"
mv "$CLAUDE_ENV_BASE/hooks.json.bak" "$CLAUDE_ENV_BASE/hooks.json"
mv "$CLAUDE_ENV_BASE/commands.bak" "$CLAUDE_ENV_BASE/commands"
mv "$CLAUDE_ENV_BASE/agents.bak" "$CLAUDE_ENV_BASE/agents"

run_test "migrate: validates name"
mkdir -p "$TMPDIR/another-config"
if claude-env migrate "$TMPDIR/another-config" "../bad" 2>/dev/null; then
  fail "should reject bad name"
else
  pass "rejects bad name in migrate"
fi

run_test "migrate: rejects nonexistent source path"
if claude-env migrate "$TMPDIR/does-not-exist" "some-env" 2>/dev/null; then
  fail "should reject nonexistent source"
else
  pass "rejects nonexistent source"
fi

run_test "migrate: rejects duplicate destination name"
mkdir -p "$TMPDIR/dup-source"
if claude-env migrate "$TMPDIR/dup-source" "migrated-env" 2>/dev/null; then
  fail "should reject duplicate destination"
else
  pass "rejects duplicate destination name"
fi
rm -rf "$TMPDIR/dup-source"

# -------------------------------------------------------
# Rm
# -------------------------------------------------------
run_test "rm: validates name"
if claude-env rm "../bad" 2>/dev/null; then
  fail "should reject bad name"
else
  pass "rejects bad name in rm"
fi

run_test "rm: removes environment"
claude-env create "disposable" >/dev/null
if claude-env rm "disposable" <<< "y" >/dev/null; then
  if [[ ! -d "$CLAUDE_ENV_DIR/disposable" ]]; then
    pass "directory removed"
  else
    fail "directory still exists"
  fi
else
  fail "rm command failed"
fi

run_test "rm: cancelled on 'n'"
claude-env create "keep-me" >/dev/null
claude-env rm "keep-me" <<< "n" >/dev/null
if [[ -d "$CLAUDE_ENV_DIR/keep-me" ]]; then
  pass "directory preserved on cancel"
else
  fail "directory removed despite cancel"
fi

run_test "rm: deactivates if active env removed"
claude-env create "active-rm" >/dev/null
claude-env use "active-rm" >/dev/null
claude-env rm "active-rm" <<< "y" >/dev/null
if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  pass "CLAUDE_CONFIG_DIR unset after rm"
else
  fail "CLAUDE_CONFIG_DIR still set: $CLAUDE_CONFIG_DIR"
fi

# -------------------------------------------------------
# List: empty envs dir
# -------------------------------------------------------
run_test "list: handles empty envs directory"
# Clean up all envs
rm -rf "$CLAUDE_ENV_DIR"
mkdir -p "$CLAUDE_ENV_DIR"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
output=$(claude-env list)
if [[ "$output" == *"No environments found"* ]]; then
  pass "shows no-envs message"
else
  fail "unexpected output" "$output"
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "========================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  exit 1
fi
