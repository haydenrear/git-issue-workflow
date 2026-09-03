#!/usr/bin/env bash
# wt_smoke.sh — prove the worktree front door on a runner with nothing installed.
#
# WHY A SECOND SUITE, WHEN scripts/selftest.sh EXISTS
# ---------------------------------------------------
# selftest.sh is the thorough one and it is NOT what this is. It needs a
# skill-manager CLI with `home clone`, it builds real per-checkout homes, and it
# takes minutes — all of which is correct for the thing it measures (which home
# a worktree's home was cloned FROM) and all of which makes it unrunnable on a
# hosted runner that has no skill-manager.
#
# What that leaves unmeasured is the half every ticket in every repo touches
# first: does `wt new` create a worktree, does `wt close` remove it, and is the
# ONE LINE each prints still the path a caller parses. Those are properties of
# git and of these scripts, not of a home — so they can be measured from a BARE
# SHELL, in seconds, and that is exactly what has never run in CI.
#
# HERMETIC, and every clause of that is load-bearing:
#
#   * $HOME is redirected into the scratch tree, so the default home rung
#     (`${SKILL_MANAGER_HOME:-$HOME/.skill-manager}`) resolves to a directory
#     that does not exist rather than to whatever the runner image ships.
#   * SKILL_MANAGER_HOME is UNSET, which is the shape a human running these by
#     hand is in and the shape issue #50 lived in.
#   * --no-home, so nothing tries to clone a home that is not there.
#   * the fixture repo has NO remote, which is the "no counterpart" base case
#     the staleness gate must allow rather than refuse.
#
# It creates and removes only paths under its own mktemp directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WT="$REPO_ROOT/scripts/wt"

[ -x "$WT" ] || { printf 'error: %s is not executable\n' "$WT" >&2; exit 1; }

PASS=0
FAIL=0
check() {
  local got="$1" want="$2" name="$3" detail="${4:-}"
  if [ "$got" = "$want" ]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n        want=%s got=%s %s\n' "$name" "$want" "$got" "$detail"
    FAIL=$((FAIL + 1))
  fi
}
yesno() { if [ "$1" = "-d" ] && [ -d "$2" ]; then echo yes; elif [ "$1" = "-e" ] && [ -e "$2" ]; then echo yes; else echo no; fi; }
has()   { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

# PHYSICAL path. lib.sh derives every worktree path with `pwd -P`, so on a host
# where the temp root is a symlink (macOS: /var -> /private/var) a scratch dir
# spelled logically would make the expected path differ from the emitted one by
# a symlink and nothing else — a failure about mktemp, reported as a failure
# about the contract.
SCRATCH="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wt-smoke-XXXXXX")" && pwd -P)"
trap 'rm -rf "$SCRATCH"' EXIT

FAKE_HOME="$SCRATCH/home"
REPO="$SCRATCH/proj"
mkdir -p "$FAKE_HOME" "$REPO"

git init -q -b main "$REPO"
git -C "$REPO" config user.email "ci@wt-smoke.invalid"
git -C "$REPO" config user.name "wt smoke"
printf 'fixture\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm 'fixture'

# Every invocation goes through this: bare shell, redirected HOME, no
# SKILL_MANAGER_HOME. `env -u` rather than `unset` so an exported value in the
# calling environment cannot leak into the child.
bare() { env -u SKILL_MANAGER_HOME HOME="$FAKE_HOME" "$@"; }

WORKTREE="$SCRATCH/proj-SMOKE-1"

printf '\n== wt new creates the worktree and says so in one line ==\n'
NEW_OUT="$(cd "$REPO" && bare "$WT" new SMOKE-1 --no-home 2>"$SCRATCH/new.err")"
NEW_RC=$?
check "$NEW_RC" 0 "wt_new_succeeds_from_a_bare_shell_with_no_skill_manager" "stderr=$(tail -3 "$SCRATCH/new.err" | tr '\n' ' ')"
check "$(yesno -d "$WORKTREE")" yes "the_worktree_exists_at_the_derived_path" "$WORKTREE"
check "$(printf '%s' "$NEW_OUT" | wc -l | tr -d ' ')" 0 "stdout_is_exactly_one_line" "got: $NEW_OUT"
check "$NEW_OUT" "created worktree $WORKTREE" "the_one_line_carries_the_path_a_caller_parses"
check "$(git -C "$REPO" branch --list feature/SMOKE-1 | wc -l | tr -d ' ')" 1 "the_branch_is_feature_slash_the_ticket"
check "$(yesno -e "$WORKTREE/.skill-manager")" no "no_home_really_skipped_the_home"
check "$(yesno -e "$FAKE_HOME/.skill-manager")" no "nothing_was_written_to_the_operators_home"
check "$(yesno -e "$WORKTREE/README.md")" yes "the_worktree_carries_the_repos_files"

printf '\n== wt info answers the key set for an existing worktree ==\n'
INFO_OUT="$(cd "$REPO" && bare "$WT" info SMOKE-1 2>/dev/null)"
check "$?" 0 "wt_info_succeeds_for_a_worktree_that_exists"
for key in WORKTREE BRANCH CLOSE; do
  case "$INFO_OUT" in
    *"$key"*) check yes yes "wt_info_reports_$key" ;;
    *)        check no  yes "wt_info_reports_$key" "output: $INFO_OUT" ;;
  esac
done

printf '\n== wt close removes the worktree and keeps the branch ==\n'
CLOSE_OUT="$(cd "$REPO" && bare "$WT" close SMOKE-1 2>"$SCRATCH/close.err")"
CLOSE_RC=$?
check "$CLOSE_RC" 0 "wt_close_succeeds" "stderr=$(tail -3 "$SCRATCH/close.err" | tr '\n' ' ')"
check "$(yesno -d "$WORKTREE")" no "the_worktree_directory_is_gone"
check "$(printf '%s' "$CLOSE_OUT" | wc -l | tr -d ' ')" 0 "close_stdout_is_exactly_one_line" "got: $CLOSE_OUT"
# The branch surviving the close is the whole reason `close` is not
# `git worktree remove`: the work is on it and the PR is not merged yet.
check "$(git -C "$REPO" branch --list feature/SMOKE-1 | wc -l | tr -d ' ')" 1 "the_branch_survives_the_close"
check "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" 1 "git_no_longer_lists_the_worktree"

printf '\n== a worktree that does not exist is refused, not invented ==\n'
(cd "$REPO" && bare "$WT" info SMOKE-1 >/dev/null 2>&1)
check "$?" 1 "wt_info_fails_after_the_close"

# ...AND THE REFUSAL NAMES ITS SUBJECT. The exit code was all this asserted, and
# an exit code is not what a caller reads. #27: closing a ticket that resolved to
# nothing printed
#
#   error: either. Check the ticket id, or name the worktree by path.
#
# `either.` is the tail of a five-line refusal whose subject was on the FIRST
# line, because `wt` quoted the LAST NON-EMPTY line of its child's stderr. What
# arrived named neither what was searched for nor where, and sent the reader to
# `--verbose` for a search that fails identically the second time.
CLOSED_OUT="$(cd "$REPO" && bare "$WT" close SMOKE-1 2>/dev/null)"
check "$?" 1 "wt_close_of_a_closed_ticket_fails_rather_than_succeeding_vacuously"
GONE_REASON="$(printf '%s\n' "$CLOSED_OUT" | sed -n 's/^error closing worktree: //p' | sed -n 1p)"
GONE_FIX="$(printf '%s\n' "$CLOSED_OUT" | sed -n 's/^fix: //p' | sed -n 1p)"
check "$(has "SMOKE-1" "$GONE_REASON")" yes \
  "the_refusal_names_the_ticket_that_resolved_to_nothing" "reason: ${GONE_REASON:-<none>}"
# $SCRATCH is where ticket worktrees for this fixture go, and it is the half the
# truncated sentence had lost: "no such ticket" and "you are in the wrong
# directory" are different failures with the same exit code.
check "$(has "$SCRATCH" "$GONE_REASON")" yes \
  "the_refusal_names_where_it_looked" "reason: ${GONE_REASON:-<none>}"
check "$(has "--verbose" "$GONE_FIX")" no \
  "the_fix_is_a_command_not_a_rerun_of_the_search_that_just_failed" "fix: ${GONE_FIX:-<none>}"

# The general half of the same defect, measured on a refusal `wt` gets NO
# contract for: `<path> is not a worktree of <root>` is a plain `die` with an
# indented `git … worktree list` remedy under it, so quoting the last line handed
# the caller a runnable COMMAND where the reason belongs — which reads as an
# answer. A different refusal on purpose: it cannot pass on the strength of the
# one above.
mkdir -p "$REPO/not-a-worktree"
SUBJ_OUT="$(cd "$REPO" && bare "$WT" close "$REPO/not-a-worktree" 2>/dev/null)"
check "$?" 1 "closing_a_directory_that_is_not_a_worktree_is_refused"
SUBJ_REASON="$(printf '%s\n' "$SUBJ_OUT" | sed -n 's/^error closing worktree: //p' | sed -n 1p)"
check "$(has "is not a worktree of" "$SUBJ_REASON")" yes \
  "the_reason_is_the_refusals_own_subject_line" "reason: ${SUBJ_REASON:-<none>}"
check "$(has "worktree list" "$SUBJ_REASON")" no \
  "the_reason_is_not_the_remedy_indented_beneath_it" "reason: ${SUBJ_REASON:-<none>}"
rmdir "$REPO/not-a-worktree"

printf '\n== Result ==\n  passed: %s   failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
