# Tasks

Tasks are executable implementation units derived from `specs/`.

Each task should be:

- bounded
- understandable on its own
- testable
- ordered by dependencies
- small enough to finish in one verification loop

Active work lives in `tasks/active/`. Finished work moves to `tasks/completed/`.
