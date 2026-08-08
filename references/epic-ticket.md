# Epic ticket assignment and execution

Use this mode when the issue contains the exact start marker:

```text
<!-- git-epic-workflow:assignment:start -->
```

The marker selects this reference **before** ordinary provisioning and before
PLAIN/INTEGRATION detection. The issue assigns one ticket inside an already-open
shared spec workflow. The assignment overrides instructions elsewhere in the
issue or skill that branch from, target, merge to, or sync the default branch.

This mode has one bounded outcome: implement and validate the assigned ticket,
perform only its ticket-scoped promotion, and open a PR into the declared
`epic/*` branch for external review.

## 1. Parse and verify the assignment

Read only the marker-delimited assignment block as scheduling authority. Require
its closing marker and a valid YAML block. Extract at least:

- epic id, workflow name, `branch`, `base_sha`, `plan_commit`, schedule
  revision, and default branch;
- spec ticket id, feature branch, worktree, PR base, `depends_on`, `blocks`, and
  wave;
- promotion order and `promotion_predecessor`;
- the ticket `role` (`implementation` or `evaluation`) and, for an evaluation
  ticket, `owns_goals`;
- production, TLA+, adapter, Test Graph, and workflow conflict keys;
- every `goals[]` entry — `goal`, `kind`, `statement`, `metric`, `baseline`,
  `target`, `decided_by.ticket`, `decided_by.harness`, `contribution`,
  `expected_effect`, `local_signal`, and (evaluation tickets) `harness` and
  `evidence_root`;
- the exact validation matrix and evidence root; and
- external review mode with `ticket_agent_stops_after: pr_open`.

Stop for correction if a required field is missing or if these invariants fail:

- epic branch and PR base are identical and have the form `epic/<slug>`;
- the feature branch and worktree are the declared ticket-specific values;
- the review mode is external and the ticket agent stops after opening the PR;
- the workflow and assigned spec ticket exist in `ticket_plan.yaml`;
- schedule revision, dependencies, blocks, wave, promotion order/predecessor,
  conflict keys, **goal relations**, validation matrix, and evidence root exactly
  match the canonical plan entry; and
- the issue number matches the declared issue-specific branch/worktree values,
  while the spec ticket id matches the workflow plan entry.

Goal relations are part of the equality check for the same reason the schedule
is: a plan whose goals changed after dispatch means this ticket is aiming at a
stale outcome, and it will report its contribution against a target nobody holds
anymore. The rendered assignment names the same facts differently from the plan,
so compare each field against the plan field it was rendered from — the ticket's
`goals[].goal` / `contribution` / `expected_effect` / `local_signal` against that
ticket's plan entry, and `kind` / `statement` / `metric` / `baseline` / `target`
/ `decided_by` against the root `epic_goals[]` entry with that id
(`decided_by.ticket` ↔ `evaluation_ticket`, `decided_by.harness` ↔ the goal's
`harness`, `baseline` ↔ `baseline.value` + `baseline.measured_at`). A mismatch
returns the ticket to the epic owner; do not reconcile it locally. Field-by-field
meanings are in `references/goal-signal.md`.

A ticket carrying `role: evaluation` additionally requires that `owns_goals` is
non-empty, that every goal it lists names this ticket as its deciding ticket, and
that each such goal declares a `harness` and an `evidence_root`. Its execution
differs from §3 onward — read "The evaluation ticket" in
`references/goal-signal.md` before provisioning it.

Do not silently infer replacement values from the default branch or from ordinary
`git-issue-workflow` naming rules.

Fetch remote state before changing the checkout:

```bash
git fetch origin
git show-ref --verify refs/remotes/origin/epic/<slug>
git merge-base --is-ancestor <base-sha> origin/epic/<slug>
git merge-base --is-ancestor <plan-commit> origin/epic/<slug>
```

Both ancestry commands must succeed. `base_sha` is an ancestry floor, not the
commit to branch from; a new ticket worktree starts at the **latest** declared
epic tip.

Resolve every `depends_on` entry to its ticket PR. For each dependency, verify
both that the PR is merged into the declared epic branch and that its merge
commit is reachable from `origin/epic/<slug>`. A locally closed spec ticket, a
green dependency branch, a closed GitHub issue, or an open PR does not satisfy a
dependency. Wait when any dependency is not on the remote epic tip.

Also verify that the declared feature branch is not already merged and is not
owned by a different worktree. If the exact branch/worktree already represents
this assignment, resume it; do not create a duplicate.

## 2. Create or resume the declared epic-based worktree

For a new assignment, use the exact values from the assignment. Apply the
index-base pinning conventions from `provision.md` §3 (clean tree, resolve the
epic branch to `commit_oid`/`tree_oid` once, create-only
`refs/index-bases/<repo-id>/<tree_oid>` retention ref, branch from the pinned
commit — never re-resolve `origin/epic/<slug>` afterwards):

In a home carrying the `skt` plugin, the whole block below is one command —
declared path, pinned base, retention ref, and the worktree's own home, rolled
back together on bootstrap failure:

```bash
git fetch origin
commit_oid=$(git rev-parse origin/epic/<slug>)
skt ticket new <issue-number>-<slug> --base "$commit_oid" --path ../wt-<issue-number>-<slug>
cd ../wt-<issue-number>-<slug>
```

Without skt, the same conventions by hand:

```bash
git fetch origin
test -z "$(git status --porcelain)" || { echo "dirty tree — reconcile first"; exit 1; }
commit_oid=$(git rev-parse origin/epic/<slug>)
tree_oid=$(git rev-parse "origin/epic/<slug>^{tree}")
git update-ref "refs/index-bases/$(basename "$(git rev-parse --show-toplevel)")/${tree_oid}" "$commit_oid" ""
# ONE chained command, deliberately. `git worktree add` alone creates a checkout
# with NO Skill Manager home — an agent launched there reads and writes the
# operator's global ~/.skill-manager. The W2 eval measured an agent running the
# add and stopping, so the two halves are not separable here:
git worktree add ../wt-<issue-number>-<slug> \
  -b feature/<issue-number>-<slug> "$commit_oid" \
  && "${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts/bootstrap-home.sh" \
       --root ../wt-<issue-number>-<slug>

cd ../wt-<issue-number>-<slug>
```

**Why this is the one place that still branches by hand.** Ordinary tickets use
`wt new <ticket> "$commit_oid"`, which creates the worktree *and* its home in one
step — but it puts the worktree at `<parent>/<repo>-<ticket>`, and an epic
assignment **declares** the worktree path and the branch. The assignment wins, so
the worktree is created by hand at the declared path and the home is bootstrapped
as its own second step. That is the only difference — the home the two routes
produce is identical, and **teardown is the same one command**, because
`wt close` resolves a ticket by searching for `<parent>/*-<ticket>` rather than
by the name `wt new` would have chosen:
`"$WT" close <issue-number>-<slug>` (verified against a hand-made
`../wt-<issue-number>-<slug>`).

If the feature branch already exists legitimately, attach or enter its declared
worktree and reconcile it with the latest `origin/epic/<slug>` instead of running
the creation command again. Preserve any assigned work already present.

Never start an epic ticket from `origin/main`, another default branch, the stale
`base_sha`, or a sibling ticket branch. Do not use the ordinary `wt new` flow or
create per-constituent branches: the epic assignment owns the branch topology for
this ticket.

## 3. Open only the assigned spec ticket

The epic workflow already exists. If the declared branch already contains the
assigned ticket workspace, verify it and resume it. Otherwise open exactly the
assigned ticket:

```bash
tla-spec-dev --spec-root specs open ticket <stable-ticket-id>
```

Never run `scaffold workflow`, create a second workflow, open sibling tickets,
reorder the plan, change another ticket's status, or rewrite workflow-wide
dependencies from this branch.

### Read the goal relations before you implement

Before the first edit, read this ticket's `goals[]` entries and treat each
`expected_effect` as the result the change is aiming at. The relation exists to
weight your work toward the measured outcome; an agent who implements the slice
and reads the goal afterwards has already made every design choice without it.
`contribution` tells you what is being asked — `direct` should move the metric,
`enabling` should unblock the ticket that does, `guard` should leave it flat.

Reading the goal never widens the assignment: the semantic delta and conflict
keys still bound the work, and the goal decides which way you lean inside them.
Full field reference and per-kind guidance: `references/goal-signal.md`.

Treat ticket-local `desired/` as the whole-program state after this ticket. Edit
it first. Advance ticket-local `current/` to the whole-program behavior that the
implementation actually provides, preserving every baseline behavior outside the
assigned delta.

Implement every assigned surface, including when applicable:

- production code and repository tests;
- Internal/External TLA+ state, actions, invariants, and model configs;
- spec-unit adapters, generated cases, strategies, and conformance tests;
- Test Graph adapters, bindings, nodes, graph composition, and context contracts;
  and
- structured validation evidence beneath the declared evidence root.

Do not narrow the work to production code when the assignment names spec,
adapter, or Test Graph effects.

## 4. Run the assigned validation loop

Run every validation matrix entry marked REQUIRED, using the exact command from
the issue. At minimum for a spec ticket, record the assigned-ticket spec unit
result and discover each affected graph before running it:

```bash
tla-spec-dev --spec-root specs run spec-unit-tests --ticket <stable-ticket-id>
<test-graph-skill>/scripts/discover.py <affected-graph>
<test-graph-skill>/scripts/run.py <affected-graph>
```

Run the issue's TLC command, repository unit command, affected repository
graphs, assigned spec-conformance graph, and adapter checks when required.
`specWorkflow` is tla-spec-dev's own CLI-lifecycle graph; run it only when the
assignment explicitly targets that repository. Use Test Graph's saved-context
failure loop for isolated failures, then rerun each complete graph from a fresh
start. Store reports and other results under the declared evidence root; command
output without a durable result path is not close-out evidence.

### 4a. Record the goal signal

Once the REQUIRED matrix is green, run each declared `local_signal` in the ticket
worktree and store its output under the declared evidence root, beside the
validation reports. `N/A: <reason>` means there is nothing to run — record the
reason rather than substituting a command of your own. Then compare the result
with `expected_effect` and record exactly one classification: **moved as
expected**, **moved less than expected**, **no measurable movement**, or **moved
the wrong way**. All four are reportable; "no measurable movement" omitted reads
as a signal nobody ran.

An evaluation ticket does something different here — it runs its owned `harness`
on the reconciled epic tip after §5 and records baseline → measured → target per
goal. See "The evaluation ticket" in `references/goal-signal.md`.

The precedence is not negotiable: the REQUIRED validation matrix decides this
ticket's pass/fail, the local signal decides nothing, and the named evaluation
ticket decides the goal. So a signal that moved the wrong way does not fail the
ticket, and a signal that moved beautifully does not excuse a red matrix entry.
Do not tune the implementation to the metric, re-run the signal selectively until
a better number appears, report the best of several runs, or widen scope past the
conflict keys to chase it. Report the run that happened.

If the signal shows the goal is unreachable from this slice, finish the assigned
semantic delta and file a **deferred finding** describing what the goal would
actually require — the surfaces a real fix would touch, the measurement that
showed it, and what you did instead. That is plan feedback for the epic owner,
not ticket work, and a ticket that quietly grows to chase a metric is exactly
what the deferment policy exists to stop.

At this stage parallel implementation may finish, but the ticket is not yet
allowed into the promotion lane.

## 5. Wait for and reconcile the promotion predecessor

`promotion_predecessor` serializes ticket-scoped promotion even when tickets were
implemented in parallel. When it is non-null, do not close the assigned ticket
until the predecessor's PR is merged into the declared epic branch and its merge
commit is reachable from the latest remote epic tip.

Fetch again and rebase or merge the latest `origin/epic/<slug>` into the ticket
branch before closing. Re-read the canonical plan and repeat the complete assignment
equality check. A changed schedule revision or field mismatch returns the issue
to the epic owner; do not promote from stale assignment metadata.

Then reconcile semantic state deliberately:

- preserve predecessor close-history entries and closed plan statuses;
- use the latest epic `specs/current` as the whole-program base;
- reapply only this ticket's semantic delta to its ticket-local desired/current;
- retain sibling Test Graph artifacts, bindings, and context contracts; and
- rerun the complete assigned validation matrix, writing fresh evidence.

An **evaluation ticket** runs its owned harnesses here, not in §4: this
reconciled tip — every contributor merged, the ticket branch caught up — is the
only tree its measurement is about. Run each owned `harness` from a fresh start
and write the results under that goal's `evidence_root`
(`references/goal-signal.md`).

Do not resolve promotion conflicts by discarding predecessor history, reopening
or editing sibling tickets, or silently broadening this ticket. If reconciliation
changes scope or reveals a semantic conflict, stop and request an explicit
amendment or reconciliation ticket.

## 6. Close and promote only the assigned ticket

When ticket-local current semantically equals desired and all required validation
is green, mark only the assigned entry in `ticket_plan.yaml` closed/done and
record its run ids and evidence paths. Leave every sibling entry and all
workflow-wide dependency/order metadata unchanged. Then close exactly the
assigned ticket with every durable evidence path:

```bash
tla-spec-dev --spec-root specs close ticket <stable-ticket-id> \
  --summary "<what landed>" \
  --result <evidence-path> \
  --result <another-evidence-path>
```

This command's ticket-scoped promotion into project `specs/current` is the only
promotion this agent performs. The default equality gate must pass.

Pass the goal-signal output (an evaluation ticket: each owned harness result)
among the `--result` paths. It is durable evidence the ticket produced, and the
close record is where a reader looks for it later. It is **not** part of the
equality gate and never affects whether close succeeds — the gate compares
ticket-local current against desired, and a signal that moved the wrong way
changes nothing about that comparison.

Never:

- use `--accept-new` to bypass semantic equality;
- use `--no-promote-current` to suppress the assigned ticket's promotion;
- close or alter any other spec ticket; or
- run `close_tickets.py` or any other whole-workflow close/promotion command.

Inspect the append-only history entry, assigned plan status, promoted project
current, merged graph artifacts, and evidence paths. Commit the implementation,
specs, adapters, Test Graph changes, close history, and evidence together.

## 7. Open the ticket PR into the epic branch and stop

Push the declared feature branch and explicitly target the declared epic branch:

```bash
git push -u origin feature/<issue-number>-<slug>
gh pr create --base epic/<slug> --head feature/<issue-number>-<slug> \
  --title "<ticket-id>: <title>" --body-file <pr-body.md>
```

The PR body must contain:

- `Refs #<issue-number>` — never `Closes #<issue-number>`;
- epic branch, workflow name, and assigned spec ticket id;
- dependency and promotion-predecessor checks;
- exact validation commands and report/evidence paths;
- a `## Goal contribution` section with one row per declared goal — goal ID,
  contribution kind, expected effect, the measured local signal with its
  classification and evidence path (or `N/A: <reason>`), and the evaluation
  ticket that decides it. Every declared goal gets a row: "no measurable
  movement" is a reportable outcome, not something to omit, and a ticket with no
  declared goal writes `None declared` so a reader can tell that apart from a
  goal that was ignored. An **evaluation ticket** carries a `## Goal verdicts`
  table instead — baseline → measured → target and a `met` / `missed` /
  `unmeasured` verdict per owned goal, split one row per clause where a target
  has several. Both formats are in
  `references/goal-signal.md`;
- the append-only close-history path; and
- the resulting ticket commit SHA.

Stop for external review immediately after confirming that the PR base is the
declared epic branch and the body contains the evidence. Do not:

- target, merge, pull, or sync the default branch;
- run `gh pr merge` or otherwise self-merge the ticket PR;
- close the GitHub issue with `gh issue close` or via a `Closes` keyword;
- run whole-workflow close/promotion;
- run ordinary integration fan-out; or
- clean up by moving the primary checkout to the default branch.

The closed ticket head represents sealed evidence. Semantic changes requested in
review require an explicit amendment ticket rather than rewriting the recorded
close history.

### Your worktree survives, so its home has to be dealt with here

An ordinary ticket runs `home close-out` and then removes its worktree
(`references/complete.md` step 6). You do not: external review owns the merge, so
you leave the worktree standing. That does **not** postpone the home question — it
makes it worse, because the person who eventually removes this worktree is the
epic finalizer, and they have no idea what is inside your home.

Your home is `<worktree>/.skill-manager`, a real copy of the project home, and it
is gitignored — so nothing you changed inside it is in the PR you just opened, in
the sealed close-history entry, or in any of the evidence you attached.

Before you stop:

```bash
# 1. Did I change a skill while working this ticket?
skill-manager home close-out --home ../wt-<issue-number>-<slug>/.skill-manager \
                             --into <repo-root>/.skill-manager --json
```

- **Clean:** say so in the PR body, one line. The finalizer needs to know the gate
  was already green, not to guess.
- **Blockers:** clear them now, not at epic close. For an improvement to a skill,
  the command that matters is `skill-manager unit publish <unit> --ticket <ticket>`
  — it puts the edit in the unit's own repository, which is the only route that
  reaches sibling projects and the only one that outlives this machine.
  `skill-manager home sync --from … --to … --merge` only lifts it into the project
  home: enough to survive the teardown, not enough to be seen anywhere else.
  Then re-run the gate and record the clean verdict in the PR body.

Do **not** remove the worktree, and do not use `--force` to make a blocker go
away. A sealed PR whose home still holds the only copy of an unpublished skill
edit is an unrecorded dependency on a directory somebody else is going to delete.

## If your assignment says `role: evaluation`

An evaluation ticket decides one or more goals instead of producing a behavioral
delta. It is still an epic ticket — §1, §2, §5, §6, and §7 all apply — but five
things change, and the full contract is "The evaluation ticket" in
`references/goal-signal.md`:

- **Its slice is the measurement.** `owns_goals` names what it decides; its
  spec ticket and close record exist for the same reasons everyone else's do.
  Open the assigned ticket at §3 exactly as usual, but expect its semantic delta
  to be small or empty — ticket-local `desired/` and `current/` normally stay at
  the whole-program state the contributors already produced, plus whatever the
  measurement itself adds. Do not invent a behavioral delta to make the ticket
  look like the others; a ticket whose evaluation changes the thing it evaluates
  has no measurement left to report.
- **Its dependencies are the contributors.** Verify §1 dependency reachability
  for every ticket contributing to an owned goal — merged into the epic branch
  and reachable from the remote tip, not merely green.
- **It measures at §5, not §4.** Each owned `harness` runs unmodified on the
  reconciled epic tip, from a fresh start — no warm cache, no resumed run, no
  node re-run in isolation — writing under that goal's `evidence_root`.
- **It reports verdicts.** `## Goal verdicts` with baseline → measured → target
  and exactly `met`, `missed`, or `unmeasured` (with a reason) — **per clause**,
  not per goal, wherever a target has more than one, since one token cannot
  carry a goal that settled met on one clause and missed on another. A harness
  that could not run is `unmeasured`, never a zero and never omitted.
- **It never repairs what it measures.** No editing a target to match a result,
  no selective re-runs until a number passes, no fixing the regressions it
  finds — those are deferred findings with the measurement attached. A missed
  goal is a decision for the epic owner at finalization, not a failed epic and
  not this ticket's to patch. Fixing it here would leave the epic with no
  unbiased measurement at all.

## Epic ticket checklist

- [ ] Epic marker selected before ordinary/integration provisioning
- [ ] Assignment complete; branch/PR-base and canonical-plan equality verified,
      goal relations included
- [ ] `base_sha` and every dependency reachable from latest `origin/epic/*`
- [ ] Declared worktree created or resumed from the epic branch
- [ ] Only the assigned existing spec ticket opened; no workflow scaffolded
- [ ] Goal relations read **before** implementing; `expected_effect` treated as
      the result the change aims at
- [ ] Production, TLA+, spec-unit adapters, and Test Graph surfaces implemented
- [ ] Full assigned validation matrix green with durable evidence
- [ ] Each `local_signal` run, stored under the evidence root, and classified;
      nothing tuned, re-run selectively, or widened to chase it
- [ ] `role: evaluation` only: every owned `harness` run fresh on the reconciled
      tip, results under the goal's `evidence_root`, verdict per goal
- [ ] Promotion predecessor merged and latest epic tip reconciled
- [ ] Only the assigned ticket closed/promoted; no bypass or whole close used
- [ ] PR opened with `Refs #<issue>` and base `epic/*`
- [ ] `home close-out` verdict clean and stated in the PR body; any skill edit
      published with `unit publish`; worktree left standing
- [ ] Work stopped for external review; issue and default branch untouched
