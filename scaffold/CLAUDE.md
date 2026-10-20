# Project Operating Manual

A specification-first, verification-driven engineering loop.

This file is loaded into every session, so it holds only what changes behavior on a normal turn.
The one-time initialization lives in `/init-project`; the per-task loop lives in `/next-task`.

## 1. Session start

A SessionStart hook injects `.agent/state.md` and the active task list into context, including
after compaction. Trust that state over your memory of earlier in the session.

If `references/` has source material and `specs/` is still empty, the project is **not
initialized**: run `/init-project` and do not write application code.

## 2. Source of truth

1. `specs/`: normative product and technical requirements
2. `tasks/active/`: the executable plan derived from the specs
3. existing code and tests: implementation reality
4. `.agent/`: current state and durable decisions
5. `references/`: original source material (input, never rewritten)

`references/` is a proposal under evaluation, not a contract. Preserve its intent, question its
technical claims, and record disagreement as a decision record instead of silently obeying or
silently ignoring it. A hook blocks file-tool edits in `references/`; normalized output goes to
`specs/`.

`specs/architecture.md` is the only normative architecture document. `docs/` is narrative for
people and never a second, competing copy.

When implementation shows a spec is wrong, fix the spec in the same iteration. A source of truth
that lies is worse than none.

## 3. State discipline

- `.agent/state.md`: current task, phase, blockers, next action, last verification
- `.agent/progress.md`: one short line per iteration
- `.agent/decisions/`: one record per durable decision

Update them at the end of every iteration. A Stop hook blocks the end of a turn when project files
changed and the state did not. Unfinished work is recorded as unfinished, never skipped.

`tasks/active/*.md` is the durable plan across sessions. The session todo list is execution within
one session and is derived from the task file. Never keep two plans that disagree.

## 4. Definition of Done

DONE requires all of:

- every acceptance criterion satisfied and ticked
- new behavior covered by tests; a bug covered by a regression test written before the fix
- `./scripts/verify.sh` green (tests, lint, types, build, E2E as configured)
- no unrelated regressions
- docs and specs updated when behavior or architecture changed
- `.agent/state.md` reflecting the final state

**Never claim DONE from reading code.** Report the command you ran and what it printed. Never
invent a result, and never report a skipped step as passed. For non-trivial tasks, have the
`task-verifier` subagent check the criteria before moving the file to `tasks/completed/`.

## 5. Verification

`./scripts/verify.sh` is the canonical entry point. It **fails while unconfigured**, on purpose,
so an empty script can never look green. Configuring it for the stack is always the first
implementation task.

## 6. Engineering loop

```text
SPEC -> TASK -> INSPECT -> IMPLEMENT -> TEST -> VERIFY -+- FAIL -> diagnose -> fix -+
                                                        |          ^               |
                                                        |          +---------------+
                                                        +- PASS -> REVIEW -> RECORD -> DONE
```

Full procedure: `/next-task`.

## 7. Change discipline

- search the repo before creating an abstraction; reuse existing patterns
- smallest coherent, reversible change; no unrelated refactors
- no new dependency without a decision record
- fix root causes, not symptoms
- never weaken authentication, authorization or validation to make a test pass
- never commit secrets or real `.env` files; document configuration in `.env.example`
- feature branches for meaningful work; do not rewrite shared history

Personal conventions (commit style, tooling) belong in your user-level `CLAUDE.md`, not here.

## 8. Practices at each step

- requirements no reference document covers: brainstorm and confirm with the user before writing
  specs
- behavior change: failing test first, then the smallest implementation that passes
- bug or unexpected failure: one hypothesis at a time, tested, before changing code
- about to claim something works: run the check and quote its output

If you have a skills plugin installed that covers these steps (for example `superpowers`), use its
skills here. `/init-project` replaces brainstorming when a guide already exists in `references/`:
the requirements are on disk and need normalizing and challenging, not reinventing.

## 9. Stop conditions

Stop when the acceptance criteria pass, when a real external blocker exists, or when a decision
needs a human and cannot be safely inferred.

When blocked, report the blocker, the evidence, what you tried, and the exact decision or input you
need. Do not retry an identical failure without a new hypothesis.

## 10. Project-specific rules

Add rules for this project below this line.
