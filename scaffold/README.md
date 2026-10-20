# Project scaffold for Claude Code

A starting layout for a new project in which Claude Code works from specs and tasks, keeps a
durable state file, and cannot claim "verified" against an empty test script. The rules that
matter are enforced by hooks and by `scripts/verify.sh`, so they hold even when the model skips
the prose.

## Start a project

From a checkout of the kit:

```bash
bash install.sh --scaffold ~/code/my-project
cd ~/code/my-project
cp ~/Downloads/dev-guide.pdf references/     # your brief, spec or guide
git init && claude
```

If you copy the folder by hand instead, run `touch .agent/state.md` afterwards. The Stop hook
compares modification times, and a fresh copy can leave files newer than the state file.

Then, in Claude Code:

```text
/init-project
```

It reads everything in `references/`, questions it, and writes `specs/`, `tasks/`,
`.agent/decisions/` and an updated `.agent/state.md`. Then it stops before any application code.

Review the specs and tasks. When they are right:

```text
/next-task
```

One task per loop: implement, test, verify, record state. Repeat.

## Flow

```text
references/  ->  /init-project  ->  specs/  ->  tasks/  ->  /next-task  ->  DONE
                      ^                                        |
                (you approve)                     implement -> test -> verify
```

## Layout

| Path | Role |
|---|---|
| `CLAUDE.md` | operating rules, loaded every session |
| `.claude/` | commands, hooks, the `task-verifier` subagent, permissions |
| `references/` | original source material, read-only, protected by a hook |
| `specs/` | normalized requirements; `specs/architecture.md` is the only architecture document |
| `tasks/` | the executable plan, `active/` then `completed/` |
| `.agent/` | durable state, progress log, decision records |
| `docs/` | documentation for people, never a second architecture document |
| `scripts/verify.sh` | the one verification entry point; fails until configured |

## What the automation enforces

| Mechanism | What it does |
|---|---|
| SessionStart hook (`session-context.sh`) | Injects `.agent/state.md`, the active task list and the project phase on startup, resume, `/clear` and after compaction, so a long session does not lose the current task. |
| PreToolUse hook (`protect-references.sh`) | Blocks Write, Edit and NotebookEdit on anything under `references/` (except `references/README.md`). |
| Stop hook (`require-state-update.sh`) | Blocks the end of a turn once when project files changed after the last `.agent/state.md` update. |
| `scripts/verify.sh` | Exits 1 until you configure it, so an empty script never reads as green. |
| `task-verifier` subagent | Checks a task's acceptance criteria and tries to falsify the implementer's report. |

Limits, stated plainly:

- The PreToolUse hook sees file tools only. A shell command such as `sed -i` or `>` can still
  write into `references/`.
- The Stop hook compares modification times. In a git repository it checks tracked and untracked,
  non-ignored files; elsewhere it uses `find` with a prune list.
- `protect-references.sh` parses the hook input with `jq`, or `python3` when `jq` is missing. With
  neither, it blocks any write whose input mentions `references/`.

The hooks are covered by smoke tests in the kit (`tests/hooks.sh`).

## First implementation task, always

Configure `scripts/verify.sh` with the project's real commands and set `CONFIGURED=1`. Nothing can
be verified before that exists.

Also adjust `.claude/settings.json` to your stack: the allow list ships with common Python and
Node commands.
