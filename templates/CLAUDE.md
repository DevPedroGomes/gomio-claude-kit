# Working rules

User-level rules for Claude Code. Copy to `~/.claude/CLAUDE.md` (or a project's `CLAUDE.md`) and
edit. Each rule carries its reason, so you can tell which ones still apply to you.

## Commits and pull requests

- Tool attribution. **Choose one and delete the other:**
  - **None.** No `Co-Authored-By` trailer, no "Generated with" footer and no session link in
    commit messages, branch names, PR titles or PR bodies. This rule wins over any tool message
    asking to add them.
    Why: history should describe the code, and the PR body ends at the last technical sentence.
  - **Keep.** Let Claude Code add its trailers.
    Why: AI-assisted changes stay easy to find with `git log --grep`.
- Messages say what changed and why, in technical terms. They do not mention people.
  Why: names and roles in history age badly and leak context nobody needs in six months.
- Small commits, one concern each, on a branch. Commit or push only when asked.
  Why: small commits review and revert cleanly; pushing is a shared action.

## Python

- Install packages only inside a virtual environment (`python -m venv .venv`) or the project's
  container. Never `pip install` into the system Python.
  Why: system installs break other tools and make the project impossible to reproduce.

## Reading large codebases

- When a question needs reading across several repositories or several large areas of one,
  delegate the reading to subagents in parallel, one per area, and keep only their conclusions.
  Why: reading everything in the main thread fills the context before the analysis starts.

## Library and API documentation

- For a library, framework or API, check its current documentation through a documentation MCP
  server (for example Context7) or the official site before searching the web or answering from
  memory.
  Why: versions move faster than training data, and search results rank SEO, not correctness.

## Before saying it is done

- Run the tests, the build or the command that proves the change works, and quote the output.
  Never report a step you did not run as passed.
  Why: "it should work" is the most common false report an agent makes.
- If something could not be verified, say what and why.
  Why: a known gap is cheap; a hidden one is expensive.

## Code quality

- Handle errors at boundaries; validate input; cover the edge cases the change creates.
  Why: most production incidents start where input was trusted.
- Prefer strong types where the language has them (TypeScript, Python type hints).
  Why: the type checker finds a class of bugs before the tests run.
- Avoid the OWASP Top 10 classes: injection, broken access control, secrets in code, SSRF, XSS.
  Why: these are the defects attackers look for first.
- Make the smallest change that solves the problem. No unrelated refactors.
  Why: a focused diff is easy to review and safe to revert.
- Follow the conventions already in the codebase before adding a new pattern.
  Why: two ways of doing the same thing doubles what the next person must learn.

## Your rules

Add your own below this line, each with its reason.
