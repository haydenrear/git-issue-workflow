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
- the exact validation matrix and evidence root;
- the `deferment:` block — `mode`, `blocking`, `budget`, and the `backlog` path a
  deferred finding is filed into. Those four values are *names* here and nothing
  more; what each one obliges you to do, and the shape of the entry you write
  into `backlog`, are in `<git-epic-workflow-skill>/references/deferment.md`.
  Read it now, at parse time, rather than at the moment you have a finding — a
  budget you learn about after the fifth deferral has already failed to stop
  anything, and an entry whose fields you invented is read back by epic-side
  review and finalization as if you had used theirs (§4b); and
- external review mode with `ticket_agent_stops_after: pr_open`, plus
  `merged_by: "epic-owner"` and, when present, a `cadence:`
  (`wave`, `milestone`, or `finalization-only`) and an `artifact_root:`. Read
  them and never treat one as an unknown-field failure. `mode` stays `external`
  and the stop point stays `pr_open` — `merged_by` names who merges the PR after
  you have stopped, not a change to whether you stop. It is a **role**, not a
  person: the schema requires it and pins it to `epic-owner` even when the user
  said they would merge the ticket PRs themselves, because that answer is
  recorded in the canonical plan and changes what the epic agent does, not what
  you do. A `merged_by` naming anything else — `human`, a username — is a
  dispatch error to return to the epic owner, never a licence to merge your own
  PR.

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
that each such goal declares a `harness`, an `evidence_root`, and
`contribution: "guard"`. Those three are *additions* to the ordinary goal entry,
not replacements for part of it — `kind`, `statement`, `metric`, `decided_by`,
`expected_effect` and `local_signal` are all still there, and a goal entry that
dropped `contribution` to signal "this one measures" is a missing field. Its execution
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

### 4b. File a deferred finding in the schema the epic owner reads

Every defect this ticket surfaces and does not fix goes in the assignment's
`deferment.backlog` file, and **that file has an owned schema you do not get to
approximate**: `<git-epic-workflow-skill>/references/deferment.md`. Open it
before writing the first entry. Three of its rules decide whether your entry
survives contact with the epic side:

- **Classification comes first.** A finding is in scope — ordinary ticket work,
  no backlog entry — only when every surface the fix touches is inside this
  ticket's `conflict_keys`, the fix changes no TLA+ action, invariant, or
  adapter mapping outside the declared semantic delta, and this ticket's desired
  model already implies the corrected behavior. Everything else is out of scope
  and is a deferment candidate, including latent bugs your change merely
  exposed.
- **`severity` is a fixed vocabulary — `blocking`, `major`, `minor` — and it is
  load-bearing downstream.** The epic owner must not merge a ticket PR whose
  ticket filed a still-`pending` `severity: blocking` finding, the wave review's
  "where I'd look for bugs" section is required to list pending entries at
  `severity: major`, and finalization cannot close the epic while any entry is
  still `pending`. A severity you coined yourself matches none of those reads, so
  the entry lands in a table nobody triages and stops nothing it should have
  stopped. `blocking` also has an operational meaning here, not just a rank: it
  means this ticket's REQUIRED
  validation matrix cannot pass without touching an out-of-scope surface, and it
  triggers `deferment.blocking` — under `escalate` you stop at the current
  commit, push without closing the spec ticket or opening a promotion PR, and
  return the ticket to the epic owner.
- **An entry with no reproduction is a hunch, not a finding.** The entry carries
  a sequential never-reused `id`, the ticket that found it, the commit, the
  schedule revision, the affected surfaces, a one-line summary, the exact
  reproduction command with observed versus expected, evidence paths under this
  ticket's evidence root, why it is out of scope, a suggested fix or `unknown`,
  and its blast radius. `disposition` starts `pending` and is the **epic
  owner's** field — never set it to anything else, except `fixed-inline` under
  `mode: inline`.

`mode` decides what you do after appending the entry: `batch` continue,
`ask` ask the owner now-or-batch, `inline` fix it only inside your own conflict
keys and record what you fixed. `budget` is a stop, not a quota — exceed it and
you stop implementing, file what you have, and report that the ticket's premise
looks wrong. The backlog is planning data: commit it with your ordinary commits,
never into ticket-local `desired/` or `current/`, and never as close evidence.

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
- the append-only close-history path;
- the resulting ticket commit SHA;
- the `home close-out` verdict for this worktree, naming every blocking unit and
  every unit you published with `unit publish`. The epic agent reconciles this
  home into the project home at wave close and later deletes the worktree without
  being able to see inside it, so this line and the *Machinery friction* list
  below are the only places that fact survives;
- a `## Deferred findings` section with one line per backlog ID this ticket filed
  — the ID, its `blocking` / `major` / `minor` severity, and a one-line summary —
  or `None`. This section is a summary of the backlog entries, not a substitute
  for them: the entries themselves live in `deferment.backlog` in the schema
  §4b names, and a severity here that is not one of those three tokens is a
  finding the epic owner's review will not sort; and
- a `## Review input` section, written for a human who has ten minutes and did not
  read the ticket. Four short lists, evidence-cited, no padding — the epic owner
  composes the wave review from these rather than re-deriving them from the diff:
  - **Hot spots** — what you changed that carries the most risk or the most
    meaning, with paths. Say when you wrote a file another ticket in your wave
    also touches;
  - **Decisions and overrides** — choices the assignment did not specify that
    another ticket would be needed to reverse, plus every guardrail you weakened
    (`--allow-open`, a skipped test, a matrix entry that became `N/A`, an inline
    out-of-scope fix). Report them even where they were obviously right;
  - **Where I'd look for bugs** — your own change, ranked, with the cheapest
    experiment that would settle each. Reproducible defects are backlog entries
    instead; this list is allowed to be suspicion, labelled as such;
  - **Machinery friction** — what about the skills, scripts, validators, or
    instruments cost you time, and what you changed in your own Skill Manager
    home to get around it. That home is gitignored and dies with this worktree,
    so a fix you do not name here reaches nobody.

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
(`references/complete.md` step 6). You do not: the epic agent merges this PR into
`epic/<slug>` at wave close and removes every worktree in one sweep at the end of
the epic, so you leave yours standing. That does **not** postpone the home
question. The epic agent reconciles this home into the project home at wave close,
in serial, and it acts on the close-out verdict and the *Machinery friction* list
in your PR body — which is precisely why you write them.

Your home is `<worktree>/.skill-manager`, a real copy of the project home, and it
is gitignored — so nothing you changed inside it is in the PR you just opened, in
the sealed close-history entry, or in any of the evidence you attached.

Before you stop:

```bash
# 0. Compute <main-working-tree>. Do not type it from memory and do not use
#    `git rev-parse --show-toplevel`: from inside this worktree that answers
#    THIS worktree, and the gate would then compare your home against itself.
#    `git worktree list` names the main working tree first, always — the same
#    resolution `project_home` in scripts/lib.sh performs.
main_working_tree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"

# 1. Did I change a skill while working this ticket?
"$main_working_tree"/.skill-manager/bin/cli/skill-manager home close-out \
    --home ../wt-<issue-number>-<slug>/.skill-manager \
    --into "$main_working_tree"/.skill-manager --json
```

Here the gate is **read-only**: it writes nothing, you run it for the verdict, and
the verdict is what the epic agent reads.

`--into` is the **main working tree's** home — the one yours was cloned from, not
`$PWD`'s nearest git toplevel, which from inside a worktree names that worktree's
own home and would compare yours against itself. That is why step 0 computes it
rather than leaving `<main-working-tree>` for you to substitute: it is the same
term and the same resolution `references/skill-homes.md`, `references/complete.md`,
`git-issue` and `git-epic-workflow` use. `references/skill-homes.md`
records the wrong resolution as a fixed defect; a read-only gate pointed at the wrong home
returns a confident wrong verdict, which is worse here than an error, because the
epic agent reconciles on it. Name a **resolved CLI path** rather than a bare
`skill-manager`, for the same reason that page gives: an older release first on
`PATH` exits 2.

- **Clean:** say so in the PR body, one line. The epic agent needs to know the gate
  was already green, not to guess.
- **Blockers:** for an improvement to a skill, the command that matters is
  `skill-manager unit publish <unit> --ticket <ticket>` — it puts the edit in the
  unit's own repository, the only route that reaches sibling projects and the only
  one that outlives this machine, and it contends with nothing because it writes
  that unit's own repo. That one is yours to run. Then re-run the gate and record
  the verdict in the PR body.
- Do **not** run `skill-manager home sync` into the project home. That home is one
  shared destination, concurrent tickets in your wave cannot see each other writing
  it, and races there are the bug this rule exists for; the epic agent reconciles
  every worktree's home into it in serial at wave close. Anything you cannot
  publish, name in the PR body under `## Review input` → *Machinery friction* and
  leave for that reconciliation.

Do **not** remove the worktree, and do not use `--force` to make a blocker go
away. A blocker your PR body does not name is an unrecorded dependency on a
directory the end-of-epic sweep is going to delete.

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
- [ ] Out-of-scope findings classified and appended to `deferment.backlog` in the
      schema `<git-epic-workflow-skill>/references/deferment.md` owns — sequential
      ID, `blocking` / `major` / `minor` severity, a real reproduction,
      `disposition: pending` — and `deferment.blocking` applied to any blocking one
- [ ] PR body carries `## Deferred findings` (each backlog ID with severity and a
      one-line summary, or `None`)
- [ ] PR body carries `## Review input` — hot spots, decisions and overrides,
      where I'd look for bugs, machinery friction — each evidence-cited
- [ ] `home close-out` run as a read-only gate and its verdict stated in the PR
      body; any skill edit published with `unit publish`; no `home sync` into the
      project home; worktree left standing for the epic agent to reconcile and
      later sweep
- [ ] Work stopped for external review; issue and default branch untouched
