---
description: Turn the source material in references/ into specs, tasks and decisions. Stops before any application code.
---

# Project Initialization

Turn the material in `references/` into an implementation-ready specification. **Do not write
application code during this command.**

If `specs/` already contains generated files, ask whether to re-initialize from scratch or to
reconcile the new reference material with what exists.

## Step 1: read the source material completely

List `references/` first, then read every file end to end.

Format notes that matter in practice:

- **PDF:** the Read tool returns at most 20 pages per call and needs the `pages` parameter above 10
  pages. Read a long guide in explicit slices (`pages: "1-20"`, `"21-40"`, ...) until the end.
  Never infer the rest of a document from its first pages.
- **.docx / .xlsx / .pptx:** the Read tool cannot open these. Convert them first (for example
  `pandoc guide.docx -t gfm -o guide.md`) or ask the user for a PDF or Markdown export. Write the
  converted copy outside `references/`.
- **Images and diagrams:** read them. Architecture diagrams often carry constraints the prose omits.

Also read this repo's `CLAUDE.md`, any existing code, and `.agent/state.md`.

## Step 2: extract

Organize what the source actually says into:

product vision · problem statement · target users · user journeys · functional requirements ·
non-functional requirements · business rules · proposed stack · architecture · integrations ·
external APIs and providers · data models · infrastructure and deployment · security
requirements · observability · cost constraints · performance constraints · implementation
phases · assumptions · open questions · acceptance criteria

Mark anything you inferred rather than read as an assumption. Do not fill gaps silently.

## Step 3: validate the source, do not obey it

A dev guide is a proposal under evaluation, not a contract. Look for:

- contradictory or duplicated requirements
- outdated or abandoned libraries, and versions that do not exist
- missing dependencies between features
- unrealistic assumptions (latency, cost, volume, free tiers)
- ambiguous requirements that would produce two different products
- architectural risks and single points of failure
- security problems (authorization model, secret handling, tenant isolation, personal data under
  the privacy law that applies, such as GDPR or LGPD)
- cost risks, especially paid AI APIs without a usage ceiling
- provider and API constraints that break the proposed design
- acceptance criteria that are missing or not objectively testable

When checking a library, framework or provider API, read its current documentation (a
documentation MCP server or the official site) before assuming anything. Versions move faster
than any model's training data.

Record every finding. Keep the source's intent while flagging what is technically wrong.

## Step 4: normalize

Create:

```text
specs/product.md          vision, users, journeys, business rules, scope
specs/architecture.md     THE normative architecture (docs/ is not a second copy)
specs/features/*.md       one file per feature, from specs/features/_template.md
tasks/active/NNN-*.md     ordered implementation tasks, from tasks/active/_template.md
.agent/decisions/*.md     one record per durable decision
.agent/state.md           initialization result and recommended first task
```

The generated documents must agree with each other: no requirement in a feature spec that
contradicts `specs/product.md`, no task without a source spec.

## Step 5: features

Each feature spec needs objective, scope, non-goals, requirements, constraints, dependencies,
acceptance criteria, verification strategy and open questions. Acceptance criteria must be
objectively testable. If a criterion cannot be checked by a command or an observable behavior,
rewrite it until it can, or move it to open questions.

## Step 6: tasks

Convert features into ordered, numbered tasks (`001-...`, `002-...`). Each task:

- can be understood without re-reading the whole spec
- names its source spec
- carries its own acceptance criteria and verification commands
- is small enough to implement and verify in one bounded loop
- follows dependency order

**Task 001 is always: configure `scripts/verify.sh` for this stack.** Nothing else can be verified
until it exists. No "build everything" tasks.

## Step 7: decisions

Write one record per durable decision into `.agent/decisions/NNNN-slug.md`, using the template in
`.agent/decisions/README.md`: context, decision, alternatives, reason, consequences. A stack choice
that came from the dev guide is still a decision; record where it came from and on what evidence.

## Step 8: state

Update `.agent/state.md`: initialization done, phase, unresolved questions, recommended first task,
verification status.

## Step 9: STOP

Do not write application code. Report:

1. product summary
2. proposed architecture
3. stack, separating "from the guide" from "changed, and why"
4. features
5. implementation phases
6. assumptions you had to make
7. risks: technical, security, cost
8. unresolved decisions that need a human
9. recommended first task

Then wait for explicit approval before implementing.
