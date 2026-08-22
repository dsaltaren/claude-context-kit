---
name: handoff
description: Dump the current working state to a file on disk so the context can be compacted or a fresh session started without losing the thread. Use when the user says "/handoff", "dump the state", "save the state", "handoff", or "before compacting". Writes next step, state, decisions and traps. Do NOT use to wrap up for the day. Do NOT use to turn the conversation into permanent notes or a changelog. This skill produces a disposable snapshot, not documentation.
triggers:
  - /handoff
  - handoff
  - dump the state
  - save the state
  - before compacting
version: 2.0.0
---

# Handoff

Move to disk what currently lives only in the conversation, so the context can be
thrown away without losing the work.

This is not documentation, not permanent memory, and not a changelog. It is a
SNAPSHOT: read it when you resume, delete it when the task is done.

## Where to write

`HANDOFF-<slug>.md` in the project root, where `<slug>` describes the task in two
to four kebab-case words. If a handoff for the same task already exists,
**rewrite it entirely, never append**.

Add `HANDOFF-*.md` to `.gitignore`. These files are scaffolding, not deliverables.

## Route content to its durable home FIRST

The handoff only keeps what has no better home. Before writing, pass everything
through this filter:

| What it is | Where it goes (not the handoff) |
|---|---|
| A rule or decision of the system you are building | Its docs / the project's CLAUDE.md |
| A durable trap about a tool or the stack | Your persistent memory, if you have one |
| An open question of the domain | The project's own open-questions list |
| Machine-checkable | The project's linter or check script |

What survives the filter is the handoff: ephemeral state, the next step, whys
that have no home yet, and traps specific to this task. **A healthy handoff gets
shorter over time**: each update should move something to a durable home, not
accumulate.

## What to write

```markdown
# Handoff: <task>
<ISO date>

## Next step
FIRST thing in the file. A concrete action executable as written, with its
verification: "run X from Y, it must end with Z". Never a vague intention.

## State
Where things stand, in two to four lines of fact. No achievements, no
narrative: compaction summaries already keep those.

## Decisions
Only the ones with no durable home yet. What was decided and WHY, with the
options rejected. The why is what compaction destroys.

## Traps
What was tried and failed IN THIS TASK, so it is not repeated. Durable traps
already left via the routing table.

## Open
Decisions still pending, with the options as they stand.
```

## Rules

- **Full rewrite, never append.** No "session N" sections, no "SUPERSEDED"
  markers, no strata. Git keeps the history; the handoff is only the now.
- **Cap it at ~40 lines.** If it does not fit, something skipped the routing
  table.
- **Guarantee it gets read**: leave a one-line pointer to the handoff in
  whatever your sessions always read first (the project's CLAUDE.md, a session
  notes file). A handoff nobody is pointed at is a handoff nobody resumes from.
  Remove the pointer and delete the file when the task dies.
- **Be concrete:** ids, paths, exact values, commands. A vague handoff does not
  let anyone resume, so the work gets reconstructed from scratch anyway.
- **The traps section is the most valuable one.** What failed is recorded
  nowhere else: the code only shows what worked.
- **Do not invent progress.** If something was left half done, say so. If
  something was never tested, say so.
- After writing it, report the path and note that it is now safe to compact or
  start a fresh session.

## When to suggest it

When the context indicator goes amber or red and the task is still open. The
order matters: handoff first, compact second. Compacting first destroys exactly
what needed to be written down.
