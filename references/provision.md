# Role 2 — Provision the ticket workflow (kick off)

Provisioning turns a filed issue into a **ready-to-work branch**: a dedicated
worktree, the right feature branch(es), and — when the issue calls for it — an
open spec workflow, all committed spec-first before any implementation. Your job
ends when an implementing agent (role 3) can start editing code with everything
in place. Nothing here implements the change.

## 1. Read the work order

Open the issue and extract the three things `git-issue` embedded for you:

```bash
gh issue view <n>                 # or: gh issue view <n> --json title,body,labels
```

- **References** — the discovery starting point (files/symbols/specs to touch).
- **Spec workflow — REQUIRED | NOT REQUIRED** — decides whether step 4 runs.
- **Regression & close-out** — the named graphs role 3 will run; note them now.

Confirm the tracker and auth before touching git:

```bash
gh auth status
gh repo view --json nameWithOwner   # confirm you are in the right repo
```

Derive a stable ticket id and slug from the issue, e.g. `142-retry-budget`. Use
it verbatim as `<ticket>` everywhere below — it becomes every branch name.

## 2. Detect PLAIN vs INTEGRATION

```bash
test -f INTEGRATION.md && test -f integration.toml && echo INTEGRATION || echo PLAIN
```

This one check forks the rest of provisioning. For an integration repo, also read
`integration.toml` to see the constituents and the host (`gh`/`glab`) — you will
not branch them now, but the spec/graph loop runs at this parent and the fan-out
targets exactly these constituents (`references/integration-fanout.md`).

## 3. Create the worktree + feature branch

**Same branch name everywhere:** `feature/<ticket>`.

### Index-base pinning conventions (every worktree, both repo shapes)

Every worktree this workflow creates must be reproducible against an immutable
base. Apply these at creation time, before any daemon, indexer, or build tool
touches the worktree:

1. **Clean slate.** The source checkout must be fully committed —
   `git status --porcelain` empty. Never provision over staged or dirty state;
   stop and reconcile instead.
2. **Resolve the base rev to object IDs once.** Capture
   `commit_oid=$(git rev-parse <base-ref>)` and
   `tree_oid=$(git rev-parse "<base-ref>^{tree}")` at creation and record them
   in the ticket evidence (and the daemon version file where an indexing
   platform runs). Never re-resolve the branch name afterwards — a ref is a
   symbolic name, not an identity.
3. **Retention ref.** Pin the base objects with a create-only custom ref so no
   later rebase or git GC can orphan what the worktree depends on:
   `git update-ref refs/index-bases/<repo-id>/<tree_oid> <commit_oid> ""`
   (empty old-value = compare-and-swap create; an existing ref pointing at a
   different commit is a hard error). Reserved namespace — never public tags.
4. **Branch from the pinned commit.** Pass `<commit_oid>` as `wt new`'s optional
   base argument (verified: `wt new <ticket> <commit_oid>` puts the worktree's
   HEAD on exactly that object), so the worktree base stays the pinned object
   even if the source branch advances.

Repos onboarded to an index platform (e.g. commit-diff-context snapshot
branching) consume these OIDs as the immutable base-snapshot identity. The
conventions hold even where no indexer runs — worktrees stay reproducible.

### One command, both repo shapes

The worktree and its own Skill Manager home are created **together**, by one
command, whether this is a plain repo or an integration repo. `wt` detects which
it is standing in; you do not pass a flag for it.

A worktree with no home of its own runs the operator's global `~/.skill-manager`,
which every other agent and every other worktree is also writing — so a bare
`git worktree add` here is not a shorter route to the same place, it is a
different and worse outcome. `wt new` is what closes that window.

Both lines below are the front door; neither is a hand replay. If you find
yourself reading `wt` and reproducing its steps instead of calling it, stop —
that is the defect `SKILL.md` §*Reaching a by-hand route is itself a finding*
asks you to report, not a route this section offers.

```bash
# The front door. An installed unit's files live at $SKILL_MANAGER_HOME/skills/<unit>/;
# the :- fallback is what makes this line work from a bare shell too.
WT="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts/wt"

git fetch origin
test -z "$(git status --porcelain)" || { echo "dirty tree — reconcile first"; exit 1; }
commit_oid=$(git rev-parse origin/main)              # use the repo's default branch
tree_oid=$(git rev-parse "origin/main^{tree}")
git update-ref "refs/index-bases/$(basename "$(git rev-parse --show-toplevel)")/${tree_oid}" "$commit_oid" ""

skt ticket new <ticket> --base "$commit_oid"   # preferred: on PATH in skt-carrying homes
"$WT" new <ticket> "$commit_oid"               # the same door where skt is absent
# Which one: test -x "${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/bin/cli/skt".
# skt is a PLUGIN — it is never under skills/, so `ls skills/` answers wrongly.
# -> created worktree /path/to/<repo>-<ticket>
cd /path/to/<repo>-<ticket>                          # the path it just printed
```

Passing a resolved `$commit_oid` rather than a bare branch name is the point of
the three lines above it, and it is why this recipe is not subject to the stale-
base refusal in `references/worktrees.md`: a SHA has no remote counterpart to
trail, because the fetch that made it current already happened here. A bare base
name would resolve to the **local** ref, and `new` refuses that one when it is
behind its remote.

**Read the worktree path off the output.** It is
`<parent>/<repo-name>-<ticket>`, placed beside the *outermost* enclosing
integration repo so a nested repo's worktree never lands in a parent's
`constituents/`. It is not `../wt-<ticket>`; do not assume a path and `cd` into
one that does not exist.

**The one refusal to expect.** In a repository that has never been given a home,
`wt new` exits **3** with `no project home yet` and prints an absolute, already
resolved `fix:` line. Run that line verbatim, then re-run the same `wt new`. It
is a one-time step **per repository**, not per worktree — and it is why nothing
here needs an `agent-home.sh` locator copied into the repo, or any other
way of working out where a skill lives on disk.

**Ordering is not a style preference.** `install`, `sync`, `bind`, `upgrade` and
`project resolve` all write into whatever `SKILL_MANAGER_HOME` names, and before
the local home exists that is the operator's global home — `project resolve`
additionally writes a child-home record and a projection ledger into it. `wt new`
creates the home before it returns, so simply do not run any of those until it
has.

### What differs by repo shape

Not the command — only what the worktree contains and what happens at the end:

- **PLAIN:** one worktree, one feature branch, one PR.
- **INTEGRATION:** the parent worktree holds every constituent's files as **plain
  files** (no constituent `.git` inside), which is what lets you edit and validate
  across sub-repos from one place. `wt new` requires a clean parent tree. Do
  **not** create per-constituent branches now — constituent-level git happens only
  at fan-out, after the change merges back to the integration main tree.
  `"$WT" info <ticket>` additionally prints a `PROPAGATE` key here; in a plain
  repo it does not exist.

The home is a **copy** of the project home it was cloned from, not a link, so two
tickets in two worktrees cannot overwrite each other's skills. It is also
gitignored, which is what makes step 6 of `references/complete.md` a gate rather
than a courtesy: nothing you put in it appears in any diff. Launch agents through
`<worktree>/.skill-manager/bin/launch/{claude,codex,gemini}` so the whole launch
contract applies; do not export the variables by hand.

Full mechanism, the `live`/`frozen` policy, and teardown:
`${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-integration-repo/references/skill-homes.md`.

> Why "depend on the same ones": every constituent branch, the parent branch, the
> MR title prefix, and the tracking issue all key off `<ticket>`. A single id
> keeps one change traceable across the parent PR and every sub-repo PR. Never
> rename the branch per constituent.

## 4. Open the spec workflow (only if REQUIRED)

If the issue's Spec-workflow section is **REQUIRED**, open the workflow now, on the
fresh branch, so the generated spec doubles and manifests are committed spec-first.
This runs through the `tla-spec-dev` CLI from **spec-double-compiler**. Operate it
at the **parent** for an integration repo (rule 1 in `SKILL.md`).

```bash
# scaffold the desired/current workflow structure from the accepted program_model
tla-spec-dev --spec-root specs scaffold workflow <ticket> "<issue title>"

# open the ticket-local workspace (current/, desired/, results/, test-graph assets)
tla-spec-dev --spec-root specs open ticket <ticket>
```

Then, before implementation, set the plan up the way the loop expects:

- Confirm `specs/current` starts equal to the whole accepted `specs/program_model`
  (not just the slice being changed).
- Edit ticket-local `desired/` first to the whole-program **ending** state named
  by the issue's Internal.tla / External.tla / test-graph / adapter bullets.
- Leave `current/` at today's behavior; role 3 advances it toward `desired/`.

Commit the scaffold so the branch is spec-first from the start:

```bash
git add -A && git commit -m "<ticket>: open spec workflow (scaffold current/desired)"
```

If the section is **NOT REQUIRED**, skip this step — the issue states the reason;
challenge it only if you discover state-machine surface it missed
(`git-issue` references/spec-workflow.md).

## 5. Hand off

Provisioning is done when:

- [ ] Worktree exists on `feature/<ticket>` (parent worktree for integration),
      created by `wt new` at the path it printed.
- [ ] Worktree has its own `.skill-manager` home, and nothing mutating ran before
      it existed. (`wt new` does both; confirm with
      `test -d <printed-path>/.skill-manager`.)
- [ ] PLAIN vs INTEGRATION recorded; constituents/host noted if integration.
- [ ] Spec workflow opened and committed, or explicitly marked N/A with a reason.
- [ ] The issue's named regression graphs are captured for role 3.

Role 3 (`references/complete.md`) picks up here. In a single-agent session, just
continue.
