# Agent Instructions

`CLAUDE.md` is the operating manual for this repository. Read it first.

Workflow entry points:

- `/init-project`: first session. Turn `references/` into specs and tasks, then stop.
- `/next-task`: one full implementation loop on one task.

Rules that hold on every turn:

- if `references/` has material and `specs/` is empty, the project is not initialized; do not
  write application code
- follow the spec and the task; inspect before editing
- `./scripts/verify.sh` is the canonical verification; it fails while unconfigured, and that is
  intentional
- keep `.agent/state.md` current
- never claim completion without the actual command output as evidence
