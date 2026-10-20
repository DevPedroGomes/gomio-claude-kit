# Agent State

Execution state and durable engineering decisions. This is what survives context compaction: a
SessionStart hook injects `state.md` into every new, resumed, cleared and compacted session.

- `state.md`: current task, phase, status, blockers, next action, last verification
- `progress.md`: short iteration history
- `decisions/`: one record per durable decision

A Stop hook blocks the end of a turn when project files changed after the last `state.md` update.

Do not use `.agent/` in place of specifications or tests. It records where the work is, not what
the work should be.
