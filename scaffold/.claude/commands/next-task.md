---
description: Run one full engineering loop on the next task in tasks/active/. Implement, test, verify, record state.
---

# Engineering Loop: one task

Argument (optional): a task file or name. Without it, pick the lowest-numbered unblocked task in
`tasks/active/`.

## 1. Orient

Read, in this order: `.agent/state.md`, the task file, the feature spec it points to, and the
existing code it touches.

If the task contradicts its spec, stop and report the contradiction. Do not reconcile it silently.

If `scripts/verify.sh` is still unconfigured, configure it first. It is the only thing between
"verified" and "asserted".

## 2. Plan in the open

Put the task's steps into the session todo list. The task file is the durable plan across
sessions; the todo list is execution inside this session. The todos come from the file, and the
file's checkboxes are updated when the todos complete.

## 3. Implement

When the change has testable behavior, write the failing test first, then the smallest
implementation that passes.

- smallest coherent change that satisfies one acceptance criterion
- search for existing patterns before introducing an abstraction
- no unrelated refactors, no new dependency without a decision record
- fix root causes, never silence a symptom
- never weaken auth, validation or a security check to make a test pass

## 4. Verify, with evidence

Run the targeted tests, then `./scripts/verify.sh`.

On failure: form a hypothesis, test it, fix the cause, verify again. Never rerun an identical
failing command without a new hypothesis.

Paste the actual command output into the task's **Completion Evidence** section. Never write a
result you did not observe. A skipped step is reported as skipped, not as passed.

## 5. Close the loop

- tick the acceptance criteria that are actually satisfied
- move the file to `tasks/completed/` only when all of them are
- update `.agent/state.md`: current task, phase, blockers, next action, last verification
- append one line to `.agent/progress.md`
- add a record to `.agent/decisions/` if a durable decision was made
- update `specs/` if the implementation showed the spec was wrong; the spec is the source of
  truth, so it has to stay true

## 6. Report

State what was implemented, what was verified with which command, what is still open, and the next
task. If blocked: the blocker, the evidence, what you tried, and the exact decision you need.
