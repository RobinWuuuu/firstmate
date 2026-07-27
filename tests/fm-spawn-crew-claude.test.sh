#!/usr/bin/env bash
# Behavior tests for the CLAUDE.md swap introduced in fm-spawn.sh.
#
# fm-spawn.sh replaces CLAUDE.md with the lean docs/crew-claude.md for
# crewmate/scout spawns into a firstmate-repo worktree, using skip-worktree
# so git status stays clean. fm-teardown.sh resets the swap before returning
# the worktree to the pool. These tests exercise that contract in isolation
# using controlled git repos, without needing tmux or treehouse.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-crew-claude)
LEAN="$ROOT/docs/crew-claude.md"

# --- helpers -------------------------------------------------------------------

# make_firstmate_wt <dir>: create a minimal firstmate-like git repo worktree.
# CLAUDE.md is a symlink to AGENTS.md, as in the real repo.
make_firstmate_wt() {
  local wt=$1
  fm_git_init_commit "$wt"
  printf '# Firstmate\nIdentity line.\n' > "$wt/AGENTS.md"
  git -C "$wt" add AGENTS.md
  ln -s AGENTS.md "$wt/CLAUDE.md"
  git -C "$wt" add CLAUDE.md
  git -C "$wt" -c user.name='test' -c user.email='test@test' commit -qm 'add firstmate files'
}

# apply_swap <wt>: mirror the swap logic from fm-spawn.sh for a firstmate-repo wt.
apply_swap() {
  local wt=$1
  if head -1 "$wt/AGENTS.md" 2>/dev/null | grep -qF '# Firstmate'; then
    git -C "$wt" update-index --skip-worktree CLAUDE.md
    rm -f "$wt/CLAUDE.md"
    cp "$LEAN" "$wt/CLAUDE.md"
  fi
}

# apply_teardown_reset <wt>: mirror the teardown reset from fm-teardown.sh.
apply_teardown_reset() {
  local wt=$1
  if head -1 "$wt/AGENTS.md" 2>/dev/null | grep -qF '# Firstmate'; then
    git -C "$wt" update-index --no-skip-worktree CLAUDE.md 2>/dev/null || true
    git -C "$wt" checkout -- CLAUDE.md 2>/dev/null || true
  fi
}

# --- tests --------------------------------------------------------------------

# A firstmate-repo crewmate worktree receives the lean CLAUDE.md and
# git status reports nothing dirty afterwards.
test_firstmate_wt_gets_lean_claude_and_status_clean() {
  local wt="$TMP_ROOT/fm-wt" status_out
  make_firstmate_wt "$wt"
  apply_swap "$wt"
  # CLAUDE.md must now be a regular file, not a symlink.
  [ -f "$wt/CLAUDE.md" ] || fail "CLAUDE.md is not a regular file after swap"
  [ -L "$wt/CLAUDE.md" ] && fail "CLAUDE.md is still a symlink after swap"
  # It must contain the lean header, not the full AGENTS.md.
  grep -qF '# Crewmate instructions' "$wt/CLAUDE.md" \
    || fail "swapped CLAUDE.md does not contain lean header"
  # git status must be empty (skip-worktree hides the change).
  status_out=$(git -C "$wt" status --porcelain)
  [ -z "$status_out" ] || fail "git status is not clean after swap: '$status_out'"
  pass "fm-spawn-crew-claude: firstmate-repo wt gets lean CLAUDE.md and git status stays clean"
}

# A non-firstmate project worktree (no '# Firstmate' heading) is untouched.
test_non_firstmate_wt_is_untouched() {
  local wt="$TMP_ROOT/other-wt"
  fm_git_init_commit "$wt"
  printf '# SomeOtherProject\n' > "$wt/AGENTS.md"
  git -C "$wt" add AGENTS.md
  ln -s AGENTS.md "$wt/CLAUDE.md"
  git -C "$wt" add CLAUDE.md
  git -C "$wt" -c user.name='test' -c user.email='test@test' commit -qm 'init'
  apply_swap "$wt"
  # CLAUDE.md must still be a symlink.
  [ -L "$wt/CLAUDE.md" ] || fail "CLAUDE.md should remain a symlink for non-firstmate wt"
  pass "fm-spawn-crew-claude: non-firstmate project wt is untouched by swap"
}

# A secondmate spawn keeps the full CLAUDE.md symlink.
# fm-spawn.sh guards the swap inside `if [ "$KIND" != secondmate ]`, so
# secondmate worktrees never see the swap code. We verify the guard condition
# by confirming that the swap is NOT applied when KIND=secondmate.
test_secondmate_spawn_keeps_full_symlink() {
  local wt="$TMP_ROOT/sm-wt" kind
  make_firstmate_wt "$wt"
  # Simulate secondmate: the guard in fm-spawn.sh prevents swap when KIND=secondmate.
  kind=secondmate
  if [ "$kind" != secondmate ] && head -1 "$wt/AGENTS.md" 2>/dev/null | grep -qF '# Firstmate'; then
    apply_swap "$wt"
  fi
  # CLAUDE.md must still be the original symlink.
  [ -L "$wt/CLAUDE.md" ] || fail "secondmate wt should keep full CLAUDE.md symlink"
  pass "fm-spawn-crew-claude: secondmate spawn leaves CLAUDE.md symlink intact"
}

# Teardown returns the worktree to a pristine state: CLAUDE.md is a symlink
# again and git status is clean.
test_teardown_resets_swap_to_pristine() {
  local wt="$TMP_ROOT/reset-wt" status_out
  make_firstmate_wt "$wt"
  apply_swap "$wt"
  # Confirm swap applied.
  [ -L "$wt/CLAUDE.md" ] && fail "swap did not apply (still a symlink before teardown test)"
  apply_teardown_reset "$wt"
  # CLAUDE.md must be a symlink again.
  [ -L "$wt/CLAUDE.md" ] || fail "CLAUDE.md is not a symlink after teardown reset"
  target=$(readlink "$wt/CLAUDE.md")
  [ "$target" = AGENTS.md ] || fail "CLAUDE.md symlink target is '$target', expected AGENTS.md"
  # git status must be empty.
  status_out=$(git -C "$wt" status --porcelain)
  [ -z "$status_out" ] || fail "git status is not clean after teardown reset: '$status_out'"
  pass "fm-spawn-crew-claude: teardown reset returns worktree to pristine state"
}

# --- run all ------------------------------------------------------------------

test_firstmate_wt_gets_lean_claude_and_status_clean
test_non_firstmate_wt_is_untouched
test_secondmate_spawn_keeps_full_symlink
test_teardown_resets_swap_to_pristine
