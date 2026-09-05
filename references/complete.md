# Role 3 — Perform the ticket (complete)

Provisioning left you a worktree on `feature/<ticket>` with the spec workflow
open. This is the rest: implement, run the loop to green, close the spec workflow
and the issue, verify the merge, open the PR, and — for an integration repo — fan
out to the constituents.

## 1. Implement in the worktree

Edit in the worktree only, never the primary checkout.

- **PLAIN repo:** edit the files the References section pointed at.
- **INTEGRATION repo:** edit across constituent files in the **one parent
  worktree** — `constituents/<name>/...` are plain files here. Do not run git
  inside a constituent directory; there is no `.git` there during the ticket.

If the issue carries a `## Goals & evaluation` section, read it **before** the
first edit: its expected effect is the result this change is aiming at, and
reading it afterwards means every design choice was already made without it.
`N/A: <reason>` means this issue has no measurable outcome — nothing to run,
nothing to report beyond saying so. See `references/goal-signal.md`.

## 2. Run the validation loop to green

Drive `specs/current` → `specs/desired_program_model` with all four layers green,
per `references/validation-loop.md`. For an integration repo this loop runs **at
the parent only**. Do not exit this step until the loop's definition-of-done is
fully checked.

When the issue declares a goal, also run its local signal once the four layers
are green — the loop's advisory fifth layer. Store the output under the ticket's
evidence path and classify it (moved as expected / moved less than expected / no
measurable movement / moved the wrong way). It is recorded and reported, never
green-or-red: the four layers decide whether this ticket passes, and the issue's
named evaluation decides the goal.

## 3. Close the spec workflow

The loop already closes each ticket as its slice converges. Before promoting,
confirm **every** ticket in `ticket_plan.yaml` is closed — not just the last one —
closing any stragglers with the `tla-spec-dev` CLI, then promote the workflow:

```bash
# close any ticket still open (repeat per ticket id)
tla-spec-dev --spec-root specs close ticket <ticket-id> --summary "<what landed>" --result <evidence-path>

# every ticket closed in the plan, model promoted, workflow dirs removed
python <tla-spec-dev-skill>/scripts/close_tickets.py --repo-root . \
  --summary "Promoted desired/current into program_model"
ls specs/                     # specs/current and specs/desired_program_model should be gone
```

Attach the test-graph reports to the in-repo spec ticket the workflow tracked, so
the passing evidence is tied to the ticket that closed — not only to the PR.

## 4. Commit the change

Only after the loop is green and the spec workflow is closed:

```bash
git add -A
git commit -m "<ticket>: <what changed> — specs, graph, adapters, tests"
```

## 5. Bring the branch back and verify the merge

### PLAIN repo

Push, open the PR, then land it yourself — rebase and merge via `gh` rather than
leaving it for someone else to merge later. Close-out isn't done until the change
is actually on `main`.

```bash
git push -u origin feature/<ticket>
gh pr create --fill --body "Closes #<n>

Graphs run: <named graphs incl. specWorkflow>. Reports attached to the spec ticket.

## Goal contribution

| Goal | Contribution | Expected effect | Measured local signal | Decided by |
| --- | --- | --- | --- | --- |
| <goal> | direct | <expected effect> | <value + classification> — <evidence path> | <evaluation issue, or this issue's own harness run> |"
gh pr merge --rebase
```

One row per goal the issue declared, including any whose signal was
`N/A: <reason>`; `None declared` when the issue declared none, so a reader can
tell that apart from a goal that was ignored. "No measurable movement" and "moved
the wrong way" are reported, not omitted — and neither is a reason to hold the
PR, tune the change, or re-run until the number improves
(`references/goal-signal.md`). An issue whose own slice **is** the measurement
reports `## Goal verdicts` instead: baseline → measured → target with a `met` /
`missed` / `unmeasured` verdict, **one row per clause** where the target has
more than one — a single token has to pick a clause and picks the flattering
one.

If the rebase merge is blocked (required review, branch protection, merge
conflict), stop and surface that instead of forcing it — don't bypass a real gate.

Verify it actually merged before cleanup:

```bash
gh pr view --json state,mergedAt,mergeCommit   # state MERGED, mergedAt set
git -C <repo-root> fetch origin
git -C <repo-root> branch --merged origin/main | grep feature/<ticket>   # branch is in main
```

### INTEGRATION repo

Merge the parent feature branch back into the integration **main** tree, then let
`git-integration-repo`'s verifier assert the tree is clean and every constituent is
still wired — this is how you confirm the change landed properly across the parent:

```bash
INT="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-integration-repo/scripts"
git -C <repo-root> merge --no-ff feature/<ticket>
"$INT/verify.sh"               # parent tree clean + every constituent has its .git + origin
```

A dirty tree or an unwired constituent here means the merge is not safe to fan out
— stop and reconcile before step 7.

## 6. Close out the worktree's home, then remove the worktree, then sync the root

Only once the merge is verified (PLAIN: PR merged; INTEGRATION: merged to main and
`verify.sh` clean).

### 6a. The gate — run it BEFORE anything is deleted

`git worktree remove` deletes `<worktree>/.skill-manager` without asking, and it
succeeds exactly as quietly whether that home held a week of skill edits or
nothing at all. The home is gitignored, so the loss appears in no diff, in no PR,
and in no fan-out. Everything in steps 1–5 was about the repository's files; this
step is about the units you were *using*, which live somewhere the repository
cannot see.

**Before the first command below: is this an epic ticket?** If the issue carried
the `git-epic-workflow:assignment` block, the gate is **read-only** for you — run
it for the verdict, put the verdict in the PR body, and stop. Do **not** run the
`home sync … --merge` remedy printed further down, and do **not** remove the
worktree. The project home is one shared destination that the concurrent tickets
in your wave cannot see each other writing; the epic agent reconciles every
worktree's home into it in serial at wave close and removes every worktree in one
sweep at the end of the epic. `unit publish <unit> --ticket <ticket>` is still
yours to run, and anything you cannot publish is named in the PR body under
`## Review input` → *Machinery friction*. Full sequence:
`references/epic-ticket.md` §7. This warning is here, above the commands, rather
than after them, because a remedy is acted on where it is read.

Everything from here to the end of step 6 is the **ordinary** close, where this
worktree is the only one closing.

```bash
skill-manager home close-out --home ../wt-<ticket>/.skill-manager \
                             --into <main-working-tree>/.skill-manager
```

`--into` is the **project** home — the main working tree's, the one this
worktree's home was cloned from. Not `~/.skill-manager`: the pair has to be the
one the copy was actually made from, or the verdict is about the wrong two homes.
And not `$PWD`'s nearest git toplevel either, which from inside the worktree
names the worktree's own home and compares it against itself. `<main-working-tree>`
is computable from wherever you are standing in the repository — `git worktree
list` names the main working tree first, always, which is how `project_home` in
`scripts/lib.sh` resolves it:

```bash
main_working_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
```

Elsewhere on this page the same directory is written `<repo-root>` on the plain
`git -C …` housekeeping lines, because for an ordinary ticket they are one
directory: the checkout your worktree hangs off. The home paths are written
`<main-working-tree>` deliberately — that is the term `git-issue` and
`git-epic-workflow` use for the same referent, and it is the one that stays
correct when the command is run from inside the worktree, where "the repo root"
is read as `$PWD`'s toplevel and is wrong.

Read the verdict, not the exit code alone. There are four exits and only one of
them prints blockers:

- **exit 0** — "holds nothing that removing it would destroy". Proceed.
- **exit 2** — the path you gave `--home` is **not a home**. Nothing was
  assessed, so nothing is printed. Almost always you passed the worktree
  directory rather than its `.skill-manager` — which is also the path
  `git worktree remove` takes, so this exit is the one standing between a typo
  and a silent "safe" verdict about the directory holding the only copy.
- **exit 9** — the destination home's policy is `frozen`, so the gate was
  refused and **nothing was attempted**. This is not a statement about your
  work; `9` ("refused, nothing attempted") is not `1` ("this worktree still
  holds work"). Either unfreeze the destination
  (`skill-manager home policy live --home <main-working-tree>/.skill-manager`) or pass a
  different `--into`.
- **exit 1** — the real verdict: this worktree holds work. Each blocking unit is
  printed with its `status` and the literal command that clears it. There are
  only two shapes of remedy, and they answer different questions:

  ```bash
  # ORDINARY tickets only. An epic ticket must NOT run this — see the epic note
  # at the top of 6a; its home is reconciled in serial by the epic agent.
  #
  # Move the edit UP A TIER, so closing this worktree does not take it with it.
  # Local to this machine. --merge is a three-way against the recorded baseline;
  # a conflict is reported and left for you, and a conflicted unit writes nothing.
  skill-manager home sync --from ../wt-<ticket>/.skill-manager \
                          --to <main-working-tree>/.skill-manager --merge

  # Push the edit to the UNIT'S OWN GIT REPO. This is the only path that reaches
  # a sibling project, and the only one that survives this machine.
  skill-manager unit publish <unit> --ticket <ticket>
  ```

  They are not alternatives. A sync-only chain would need the same improvement
  merged up twice and would still never reach another project. If you improved a
  skill during this ticket, `unit publish` is the one you owe; `home sync` only
  stops the worktree teardown destroying it.

  A `LINKED` blocker means the gate **cannot tell** whose bytes those are —
  resolve the symlink first. "Cannot tell" blocks on purpose; clearing it is how
  `clean: true` came to be printed for a home whose whole `skills/` directory was
  a link.

Use `--json` when you want to act on `.blockers[]` programmatically. The command
writes nothing and is safe to re-run after each remedy.

**Epic exception, restated because this is where the removal starts.** If you
skipped the note at the top of 6a: an epic ticket has already finished this step
when it has run the gate, recorded the verdict, and published what it could. It
does not `home sync` into the project home and it does not remove the worktree —
the epic agent does both, in serial, at wave close and at end of epic
(`references/epic-ticket.md` §7). Nothing below this line applies to it.

Prefer the wrapper in **both** repo shapes — it does the gate and the removal in
the right order and refuses (exit 4) on a non-zero verdict:

```bash
WT="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts/wt"
"$WT" close <ticket>                       # add --dry-run to just ask
```

`wt close` forwards to `close-change.sh`; a successful close prints one line
naming the worktree, the branch that outlives it, and the home tier its skill
work reached. `--dry-run` and `--force` print the full key set instead. It
resolves the ticket by searching where ticket worktrees live, so it runs from a
checkout other than the one that opened the worktree — but it must be run from
inside **some** git repository (from a non-repo directory it exits 1 with
`not inside a git repository`).

`close-change.sh --force` still runs the gate and still prints every blocker; it
only declines to stop, and it says the work is being discarded. It exists so that
someone throwing away a spike uses a named, loud override instead of `rm -rf`,
which skips this check and every other one. `--force` is not on
`skill-manager home close-out` itself — the CLI's job is the verdict, the script's
job is whether to obey it. Never reach for it to get past a blocker you have not
read.

### 6b. After the removal

The removal itself already happened in 6a — `skt ticket close <ticket>` (or
`"$WT" close <ticket>`, or the `close-out && git worktree remove` pair with
its `&&` intact). There is deliberately no bare `git worktree remove` step
here: run bare, it deletes the worktree's home — and every unpublished skill
edit in it — without a word, which is the exact loss the gate in 6a exists to
prevent. What remains is syncing the primary checkout:

**PLAIN:** the primary checkout never touched this ticket's commits — they only
exist on the remote until you pull. Sync it to the new `main` before you consider
the ticket closed:

```bash
git -C <repo-root> checkout main
git -C <repo-root> pull origin main
git -C <repo-root> worktree prune
git -C <repo-root> branch -d feature/<ticket>   # local branch is merged; safe to drop
```

**INTEGRATION:** step 5's `git merge --no-ff feature/<ticket>` already updated
`<repo-root>` directly, so just prune the stale worktree registration:

```bash
git -C <repo-root> worktree prune
```

## 7. Close the GitHub issue

If the PR carried `Closes #<n>`, merging closes the issue automatically — confirm
it. Otherwise close it with a summary:

```bash
gh issue view <n> --json state,closed          # confirm CLOSED after PR merge
# if still open:
gh issue close <n> --comment "Completed on feature/<ticket>. Graphs: <named graphs incl. specWorkflow>. Spec workflow promoted; reports attached to the spec ticket."
```

## 8. INTEGRATION only — fan out to constituents

For an integration repo, the parent PR is not the end. Each constituent needs its
own `feature/<ticket>` branch, PR, and **agent tag**, because each constituent runs
its *own* spec/test-graph loops downstream. Do this now via
`references/integration-fanout.md`.

## Close-out checklist — ORDINARY and INTEGRATION tickets only

**An epic ticket does not run this checklist.** Four of its lines — the
rebase-merge into `main`, the worktree removal, the project-root sync, and the
`gh issue close` — are things the epic path explicitly forbids, and a checklist
that carries an exception on one line reads as one that applies with adjustments
everywhere else. It does not apply at all: the epic ticket's checklist is the
"Epic ticket checklist" at the end of `references/epic-ticket.md`, and it stops
at PR open. Use exactly one of the two.

- [ ] Implemented in the worktree (parent worktree for integration)
- [ ] Issue's `## Goals & evaluation` section read before implementing (or `N/A`)
- [ ] Validation loop green
- [ ] Declared local signal run, stored with the evidence, and classified
- [ ] Every ticket closed via `tla-spec-dev`; spec workflow promoted and closed
- [ ] Test-graph reports attached to the in-repo spec ticket
- [ ] Committed and pushed to `feature/<ticket>`
- [ ] PLAIN: PR opened with `Closes #<n>`, rebase-merged into `main` via `gh pr merge --rebase`, merge verified
- [ ] PR body carries `## Goal contribution` (or `None declared`)
- [ ] INTEGRATION: parent merged to main and `verify.sh` clean
- [ ] `home close-out` run and clean (or every blocker cleared by `home sync --merge` / `unit publish`) **before** any removal
- [ ] Any skill improvement made inside the worktree's home published to that unit's own repo
- [ ] Worktree removed
- [ ] Main working tree — `<repo-root>`, the checkout the worktree hung off — synced to the new `main`
- [ ] GitHub issue closed via `gh`
- [ ] INTEGRATION: fan-out done (`references/integration-fanout.md`)
