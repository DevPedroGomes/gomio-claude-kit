# References

Put the original project material here before the first Claude Code session.

Typical inputs:

- development guides
- product briefs
- technical research
- architecture proposals
- API documentation
- planning documents
- PDFs

Files in this directory are source material. They are not assumed to be technically correct.

During `/init-project`, Claude Code:

1. reads the material completely
2. extracts requirements and proposed solutions
3. identifies assumptions and risks
4. normalizes the material into `specs/`
5. creates implementation tasks in `tasks/`
6. records important decisions in `.agent/decisions/`
7. stops before implementation

A PreToolUse hook blocks file-tool writes here (this README excepted), so the original stays intact.
