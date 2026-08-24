# Ticketed changes with worktrees

Every ticket is made in its own worktree, on its own feature branch, with its own
Skill Manager home — in a plain repo, in a constituent, and in an integration
repo alike. `wt` detects which it is standing in; the extra thing an integration
repo gets is one key, `PROPAGATE`, naming the fan-out shipped by
`git-integration-repo`. A cross-repo change is made once, in one parent worktree,
against one ticket, and then fanned out: **multi-repo changes need a ticket and a
worktree, but no submodules** — the worktree is just files.

## If you are here to create a worktree, you do not need this page

```bash
S="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts"

"$S/wt" new   TICKET-123
"$S/wt" close TICKET-123
```

`wt` **is not on `PATH`** — but `skt ticket new|close` is, in any home carrying the skt plugin, and it drives this same script underneath. Where skt is absent, invoke `wt` by a path that resolves, which is how every
command in this repo prints itself, including the `CLOSE` key. An installed
unit's files live at `$SKILL_MANAGER_HOME/skills/<unit>/`; the `:-` fallback
makes the same line work from a bare shell. Run `new` from anywhere inside the
repo you want branched. It resolves the repo, creates the
worktree, gives it its own Skill Manager home, and answers in **one line**:

```
created worktree /repos/deploy-helm-TICKET-123
closed worktree /repos/deploy-helm-TICKET-123 (branch feature/TICKET-123 kept; home work went no further than /repos/deploy-helm/.skill-manager — push skill edits from there)
```

That is the whole successful output, on stdout. Nothing is on stderr unless the
run is slow enough to need waiting on — see *How long it takes* below.

`close` and `info` run from **anywhere at all**, including a completely
different repository: a bare ticket is first tried as
`<parent>/<this repo>-<TICKET>` and, failing that, resolved against the
worktrees that actually exist in the directory ticket worktrees go in. Both used
to compose the path out of whatever repo `$PWD` was in and refuse with
`not a directory: /repos/some-other-repo-TICKET-123` — which reads as "no such
ticket" when what was wrong was the directory. One resolver serves both verbs,
so `wt info T` and `wt close T` cannot answer about different worktrees. Two
worktrees sharing a ticket id are **named, never guessed between**.

### Why one line, and where the rest went

The path is the only fact on it that an agent cannot work out for itself.
Everything else follows from the path *by construction*, or is a key:

| What you might want | Where it comes from |
|---|---|
| where to edit | the path |
| what it was branched from, and the commit that resolved to | the `BASE` key on the creating run — **not** on this line; see *The branch point* |
| the launcher | `<worktree>/.skill-manager/bin/launch/claude` |
| the drift-gate remedy, if `LAUNCH` refuses with **exit 8** | `<worktree>/.skill-manager/bin/cli/skill-manager home drift --ack` |
| the teardown | `"$S/wt" close TICKET-123` — the other half of what you just typed |
| the branch | `feature/TICKET-123`, and `wt close` names it when it differs |
| where the worktree's HOME work ended up, and what it still owes | the `HOME-WORK` key, and the clause `wt close` puts on its one line |
| the constituent fan-out (integration repos only) | the `PROPAGATE` key, resolved into `git-integration-repo`'s `propagate.sh` — or, when that unit is not installed, the `skill-manager install` that provides it |

`HOME-WORK` is the one key that is *not* derivable, which is why it is on the
one line rather than on demand. `skill-manager home sync` — the remedy the close
gate names — moves a worktree's unit work **one tier up**, into this checkout's
own home, and stops there. It does not push a skill edit back to that skill's
repository, and `propagate.sh` does not either (it fans out the parent's
*tracked* files; a home is gitignored). So after a close the edit exists in one
place, a later `install`/`upgrade`/`sync` of that unit can overwrite it, and no
other checkout will ever see it. Push it from the **main checkout** — from a
worktree the skill's upstream is the wrong target anyway, since the copy holding
the edit lived in the home that was just deleted. See
`references/skill-homes.md`, and git-integration-skill#8.

**Nothing is ever added to that line.** `BASE` was briefly a `(base …)` clause on
it, and that is why the rule is written down rather than assumed: three parsers
in two other repositories read the summary — an anchored
`^created worktree (\S+)$` in skill-manager's onboarding graph and two
`line[len("created worktree "):]` slices in the skt evals — and a single extra
word broke all three. One of them then scored a path that could not exist as a
**pass**. The summary is *prose*; anything a caller must act on is a **key**,
matched generically as `^KEY<space>`, which costs nothing to add anywhere. A
caller reading this line was always unsupported, and putting load-bearing data on
it does not merely risk such callers — it rewards them.

`wt new` and `wt close` run constantly, and four long absolute paths restating
the fifth is a cost paid on every one of them. `IF-EXIT-8` was the clearest
case: a remedy for a gate that has not fired, printed on every run in which it
never fires.

### The branch point

```
error creating worktree: base epic/subtract-to-measure is 21 commit(s) behind origin/epic/subtract-to-measure — branching it would start from a superseded tree (--stale-base-ok to do it anyway)
fix: /…/skills/git-issue-workflow/scripts/wt new SM-07 origin/epic/subtract-to-measure
log: /tmp/wt-9fK2aQ-run.log
```

`git worktree add -b F <path> <BASE>` resolves a **bare** `<BASE>` to the
**local** ref, and nothing in this skill ever fetched. That is fine until
something other than your checkout is advancing the branch — which is the normal
case for an epic whose ticket PRs are merged server-side. `gh pr merge` advances
`origin/epic/<slug>`; your local `epic/<slug>` never moves, and neither does your
local *copy* of the remote ref, because only a fetch moves that. A ticket then
branches from a superseded tree, edits a file that has been replaced, and reports
a true sentence about the wrong tree. Measured once at 21 commits.

So `new` measures the branch point before creating anything:

- If the base is a **local branch** with an upstream, or with a matching
  `origin/<base>`, that ref is **refreshed first** — exactly
  `+refs/heads/<base>:refs/remotes/<remote>/<base>`, `--no-tags`, one ref from
  one remote. Without the refresh the check is close to vacuous for the case
  that motivates it, since both sides of the comparison would be equally stale
  local refs. `WT_FETCH=0` skips it (offline, or a slow link);
  `WT_FETCH_TIMEOUT` (default 10 s) bounds a stalled transfer, and credential
  prompts are disabled so the fetch cannot block on one. **A failed fetch is not
  a refusal** — the comparison still runs against the ref as it stood, and the
  log says so.
- If the local ref is then **behind**, the run refuses, as above.
- **Ahead**, **equal**, and **no remote counterpart at all** proceed untouched.
  A base that is not a local branch — a tag, a SHA, or a base already spelled
  `origin/<x>` — is exactly what you asked for and is never gated.

It is **not** silently redirected to `origin/<base>`. Branching from a
deliberately local state is a legitimate thing to want, and quietly retargeting
it would be the same defect facing the other way. `--stale-base-ok` is the one
flag for that case, it is named in the refusal, and a run that uses it says so —
in one line on **stderr**, leaving stdout byte-identical to any other run:

```
$ "$S/wt" new SM-07 epic/subtract-to-measure --stale-base-ok
created worktree /repos/proj-SM-07                              # stdout, unchanged
note: branched from a stale base — 21 behind origin/epic/subtract-to-measure, taken anyway via --stale-base-ok
```

That is the same trade `close --force` makes: the run that deliberately overrode
a gate is the one run that owes an acknowledgement, and it is paid on stderr so
that stdout stays a contract. As a key it is `STALE-BASE`, present only on the
overridden run, so "was this branched from a stale point" is answerable by
presence rather than by matching a substring.

**Where the commit itself is.** The `BASE` key, on the creating run —
`new-change.sh` stdout, `wt new --verbose`. Not on `wt info`, which answers about
a worktree some other run made and measured no branch point; `None` there means
"not measured", never "branched from nothing".

**What this still cannot catch.** The base is compared once, before the worktree
exists. Nothing re-checks it afterwards, so a merge landing on the epic branch a
minute later is invisible until the ticket rebases — the `BASE` key is what makes
that answerable. And with `WT_FETCH=0`, or when the fetch fails, staleness is
only visible if some *earlier* fetch already recorded it.

**The keys are not gone, they are on demand.** All six are still printed, as the
same `KEY  value` contract as before, by any of:

```bash
S="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts"

"$S/wt" info TICKET-123              # a worktree that exists; creates and removes nothing
"$S/wt" new TICKET-123 --verbose     # on the run that creates it
"$S/wt" close TICKET-123 --dry-run   # CLEAN / CLOSE — would this close cleanly?
"$S/wt" close TICKET-123 --force     # CLOSED / BRANCH / DELETE / HOME-WORK, plus what it discarded
```

`info` prints no `BASE`: it answers about a worktree some other run created and
does not know what that run branched from. A key there would be a fact this
skill did not measure.

### How long it takes, and how to wait for it

`new` is dominated by copying the Skill Manager home, so its cost tracks the
**source home**, not the repo. Measured on one machine against an 18-unit /
852 MB project home:

| phase | before | after |
|---|---|---|
| `skill-manager home clone`, end to end (40307 files, 852 MB) | 33.6 s | 33.7 s |
| the other CLI calls (policy, shims, descriptor, drift, `exec --print-env`) | ~14 s | ~14 s |
| **`descriptor_env_dirs` called from inside per-unit shell loops** | **~109 s** | **~0 s** (asked once, in the row above) |
| **total (`bootstrap-home.sh` on the same home)** | **158.7 s** | **49.6 s** |
| **total (`wt new`, worktree + home)** | **151.7 s** | **48.0 s** |

That third row was the whole problem. The agent-home directories are read from
the descriptor by starting the CLI (a JVM, ~1.4 s), and `unprojected_pairs` and
`projected_unit_count` each expanded `$(projection_dirs)` **once per unit** —
18 units × 1.4 s per call, four such calls in a bootstrap. It is a pure function
of the home and the root, so it is now asked once per run. Nothing about what is
checked changed: `verified: N skill(s) servable` still means every store unit is
reachable from every declared agent home by a link that resolves inside the
checkout.

What is left is not reducible **from here**. Two thirds of it is
`skill-manager home clone`, whose code is in that repo. Measured on the same
696 MB subtree of the same home, `cp -Rc` (APFS `clonefile`) takes **11.2 s**
and `cp -R` takes **26.0 s**, and `home clone` runs at the second speed. The
remaining ~14 s is nine CLI starts, each of which is asked exactly one question
that only the CLI can answer.

> **CORRECTION, 2026-08-24.** This paragraph used to read the timing above as
> evidence that `home clone` "is copying rather than cloning", and to claim that
> copy-on-write "would take ~17 s per worktree off every `wt new`". **Both are
> wrong. `home clone` is already copy-on-write**, and the error was inferring
> space from wall clock.
>
> Measured by free-space delta on the same volume, with a positive control for
> copy-on-write *and* a positive control for a true copy, never with `du` —
> twice, by two people, on two different homes (skill-manager#251, DEF-098):
>
> | arm | home A | home B |
> | --- | --- | --- |
> | `cp -Rc` (clonefile), control | 1.2 MB | 39.7 MB |
> | `cp -R` (true copy), control | 526.4 MB | — |
> | **`skill-manager home clone`** | **31.0 MB** | **22.2 MB** |
> | `cp -R` of exactly what `home clone` produced | 511.3 MB | 498.0 MB |
>
> The last row is the one that settles it: it copies the **same bytes**
> `home clone` wrote, so nothing about which files are skipped can explain the
> gap. `home clone` lands at clonefile's magnitude and 17–22× below a true copy.
>
> **The timings above stand; only the inference from them did not.** `home clone`
> runs at `cp -R`'s wall clock while consuming `clonefile`'s blocks, because it
> walks ~30k files, stats them, rewrites descriptors and verifies the copy — work
> that costs seconds without costing space. So the ~17 s is still on the table as
> a performance question, but it is **not** available by "switching to
> copy-on-write", which is already what happens.
>
> **Consequence for planning: "a worktree home is nearly free" is justified for
> DISK and not for WALL CLOCK.** A home per ticket costs roughly 4–6% of its
> parent in real blocks and tens of seconds of setup. Budget the seconds; do not
> budget the gigabytes. And measure either one with free space, never with `du`,
> which over-reports a copy-on-write tree by roughly 30×.

**Nothing is printed until the run finishes** — the contract is emitted
atomically at the end, which is what makes the one-line summary possible. So if
a run may outlast a caller's timeout, do not background it and poll: polling
re-reads the whole transcript every time, while

```
still running after 25s (new TICKET-123) — watch: tail -f /tmp/wt-a1b2c3-run.log
```

is printed once, on **stderr**, by any run that passes `WT_PROGRESS_AFTER`
seconds (default 25, `0` silences it). A fast run prints nothing on stderr, as
before — the line exists only for the runs that created the problem it solves.

`new-change.sh` and `close-change.sh` emit that contract unchanged; `wt`
summarises it. **The keys are still the interface, not the path.**
git-issue-skill#4 asks whether worktree provisioning should live in `git-issue`
or in `skill-manager` rather than here; a caller that reads these keys keeps
working across such a move, and one that parses the one-line summary never
could — read `wt info` instead. If you add a key, add it to this table.

### A refusal

Three lines, because when nothing happened the next move is not derivable from
anything:

```
error closing worktree: `home close-out` exited 1: this worktree holds work that removing it would destroy.
fix: skill-manager home sync --from /repos/deploy-helm-TICKET-123/.skill-manager --to /repos/deploy-helm/.skill-manager
log: /tmp/wt-9fK2aQ.log
```

`fix:` is the **first blocker's own remedy**, not `--force`: `--force` is always
available and is the one that throws the work away, so a refusal that leads with
it teaches the operator to discard. The reasoning — the gate's full transcript,
every blocking unit and every conflicted file — is in the file `log:` names and
is never printed. Read it when the `fix:` line is not enough.

**The two outcomes are exclusive.** A run reports success or refusal, never
both, and the exit code agrees. `wt close <T> --force` is a *success*: it prints
`CLOSED` / `BRANCH` / `DELETE` and exits 0. The gate's refusal — the list of
work being discarded — is still printed in full, on stderr, without `--verbose`,
for exactly this one case, because a teardown that destroys work and says
nothing anywhere would be a worse defect than the one this rule fixes. It is
also why `--force` is the one flag that does *not* get the one-line summary:
what was thrown away is the only thing worth printing.

The rest of this page is the *explanation*: which repo gets branched and why,
where the worktree may live, and what the gates are for. It is worth reading
once. It is not worth reading before every ticket, and the whole point of `wt`
is that you do not have to.

## Which repo `new-change.sh` acts on, and where the worktree goes

Both of these were wrong in ways that produced no error message, so they are
stated before the flow rather than after it.

**The repo is the nearest enclosing git toplevel**, and the script prints it.
A constituent has its own real `.git`, so run from `constituents/deploy-helm`
the answer is deploy-helm — not the integration parent that tracks its files.
Three shapes, all supported:

| Where you run it | `kind` | What is branched | `propagate.sh` after? |
|---|---|---|---|
| A checkout holding `integration.toml` | `integration` | that repo; constituent files are plain files in the worktree | yes |
| A **nested** integration repo (`constituents/meta-orchestrator`) | `integration` | the nested repo — it is one in its own right | yes, within it |
| An ordinary constituent (`constituents/deploy-helm`) | `constituent` | the constituent | **no** — nothing beneath it to fan out to |
| A repo outside any integration repo | `standalone` | that repo | no |

Standing in a constituent and wanting the *parent* is a real case:
`new-change.sh TICKET --integration` targets the enclosing integration repo
without a `cd`.

**The worktree is placed beside the OUTERMOST enclosing integration repo**,
never inside one. For a top-level repo that is its own parent directory, which
is where worktrees have always gone. For anything living inside an integration
repo it is the difference between a clean parent and a broken one:

```
constituents/meta-orchestrator  ->  ../meta-orchestrator-TICKET-123
constituents/deploy-helm        ->  ../deploy-helm-TICKET-123
```

A worktree under `constituents/` is not merely untracked noise in the parent's
`git status`. A worktree's `.git` is a **file**, so a parent `git add -A` stages
the whole directory as a gitlink (mode `160000`) — exactly the submodule
`INTEGRATION.md` rule 1 forbids. Nor can the parent's `.gitignore` fix it: any
glob wide enough to match `constituents/meta-orchestrator-CO2` also matches real
constituents named `deploy-helm` or `hyper-experiments`. So the worktree goes
where the parent cannot see it, and `new-change.sh` refuses outright if a
worktree path would land inside an integration repo's working tree.

`close-change.sh` derives the path from the same helper, so it closes exactly
what `new-change.sh` opened, from either repo.

## Why a worktree

- The parent worktree checks out constituent files as **plain files** — no
  constituent `.git` inside it (verified; see `references/git-model.md`). You can
  edit `constituents/service-a/...` and `constituents/shared-lib/...` in one
  place and commit them together.
- It isolates the change on `feature/<TICKET>` without disturbing the main
  integration tree (where each constituent's real `.git` lives).
- It maps cleanly to the fan-out: one parent feature branch → one feature branch
  per affected constituent, all named `feature/<TICKET>`.

## Flow

Written out in full, with the prose kept. `wt new TICKET-123` is steps 1 and 1b
in one command with the narration suppressed, and `wt close TICKET-123` is 4b.

```bash
S="${SKILL_MANAGER_HOME:-$HOME/.skill-manager}/skills/git-issue-workflow/scripts"

# 1. Start the change. Requires a clean tree in the repo it picks — and it
#    prints which repo that is, and of what kind, before doing anything.
$S/new-change.sh TICKET-123
#    -> creates <repo>-TICKET-123 on branch feature/TICKET-123, beside the
#       outermost enclosing integration repo (plain files)
#    -> and gives it its OWN skill-manager home before returning
#    -> add --integration to target the parent from inside a constituent

WT=../<repo>-TICKET-123

# 1b. Launch agents through the worktree's own home, not the global one:
$WT/.skill-manager/bin/launch/claude
#    See references/skill-homes.md. Nothing to export; the shim applies the
#    whole launch contract.
#
#    That first launch may still be REFUSED with exit 8: a home whose units
#    changed gates the next launch until the change has been read. It is a
#    working home, not a broken one. Read and clear it, then launch again —
#    through the home's OWN cli entrypoint, since a bare `skill-manager` may be
#    an older release:
$WT/.skill-manager/bin/cli/skill-manager home drift
$WT/.skill-manager/bin/cli/skill-manager home drift --ack

# 2. Make the change across constituents in the worktree. Use the composed
#    skills here: write/adjust tla-spec-dev specs, spec unit tests, and
#    test_graph nodes alongside the code (see references/composition.md).

# 3. Commit once to the parent feature branch.
git -C "$WT" add -A
git -C "$WT" commit -m "TICKET-123: <cross-repo change summary>"

# 4. Bring it back into the integration main tree.
git merge --no-ff feature/TICKET-123

# 4b. Close the worktree THROUGH THE GATE, not with a bare `git worktree remove`.
#     close-change.sh runs `skill-manager home close-out` first and refuses
#     (exit 4) while the worktree's own home still holds unit work, printing
#     each blocking unit and the command that clears it.
$S/close-change.sh TICKET-123
#     -> blocked? run the remedy it prints, then re-run.
#     -> really want to throw the work away? $S/close-change.sh TICKET-123 --force

# 5. Fan out to the constituents.
$S/propagate.sh TICKET-123 --push --mr
```

## Tickets

Every change is tied to a ticket id (`TICKET-123`), which becomes:

- the parent branch `feature/TICKET-123`,
- each constituent branch `feature/TICKET-123`,
- the MR title prefix, and
- the tracking issue title.

This keeps a single change traceable across the parent and every constituent.
Create the ticket in your tracker first; `[integration].tracker` in
`integration.toml` is where `propagate.sh` files the coordinating issue.

## Notes

- **Keep the tree clean between changes.** `new-change.sh` refuses to start if
  the repo it picked is dirty — commit or stash first. The refusal names that
  repo, because "not clean" printed against files you did not expect is the
  first sign it picked one you did not mean.
- **Read the `repo:`/`kind:` lines it prints.** They are the whole defence
  against a wrong target: the failure this replaced was silent and exited 0.
- **One ticket per worktree.** Parallel tickets get separate worktrees and
  separate branches; they never share a worktree.
- **Do not run git inside an integration worktree's constituent directories** —
  there is no `.git` there, and you do not want one. Constituent-level git
  happens later in the main tree during propagation. (A `constituent` worktree
  is an ordinary checkout of one repo and has no such rule.)
- **The worktree's home dies with the worktree.** `git worktree remove` deletes
  `<wt>/.skill-manager` too, including any skill edit an agent made in it that
  was never pushed back. `close-change.sh` is the reason you no longer have to
  remember this: it asks `home close-out` first and refuses while there is
  anything to lose. Reconciling into the project home is a different flow from
  `propagate.sh`; see `references/skill-homes.md`.
- **`--no-home` exists but costs you the isolation.** A worktree created with it
  runs agents against the global home, which is what the per-worktree home is
  there to prevent. Use it only for a worktree no agent will run in.
