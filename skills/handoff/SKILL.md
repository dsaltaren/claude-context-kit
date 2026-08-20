---
name: handoff
description: Dump the current working state to a file on disk so the context can be compacted or a fresh session started without losing the thread. Use when the user says "/handoff", "dump the state", "save the state", "handoff", or "before compacting". Writes decisions taken, current state, next step and traps encountered. Do NOT use to wrap up for the day. Do NOT use to turn the conversation into permanent notes. This skill produces a disposable working file, not documentation.
triggers:
  - /handoff
  - handoff
  - dump the state
  - save the state
  - before compacting
version: 1.0.0
---

# Handoff

Move to disk what currently lives only in the conversation, so the context can be
thrown away without losing the work.

This is not documentation and not permanent memory. It is a working file: read it
when you resume, delete it when the task is done.

## Where to write

`HANDOFF-<slug>.md` in the project root, where `<slug>` describes the task in two
to four kebab-case words. If a handoff for the same task already exists,
**update it, do not create another one**.

Add `HANDOFF-*.md` to `.gitignore`. These files are scaffolding, not deliverables.

## What to write

Only what cannot be reconstructed by reading the repo. Do not restate what the
code, the git history or CLAUDE.md already say.

```markdown
# Handoff: <task>
<ISO date>

## State
Where things stand right now, in two to four lines.

## Decisions
What was decided and WHY. The why is what compaction destroys.
Include the options rejected and the reason.

## Next step
The concrete action that was coming up, not a vague intention.

## Traps
What was already tried and failed, so it is not repeated. Tool errors,
assumptions that turned out false, dead ends.

## Open
Decisions still pending, with the options as they stand.
```

## Rules

- **Be concrete:** ids, paths, exact values. A vague handoff does not let anyone
  resume, so the work gets reconstructed from scratch anyway.
- **The traps section is the most valuable one.** What failed is recorded nowhere
  else: the code only shows what worked.
- **Do not invent progress.** If something was left half done, say so. If
  something was never tested, say so.
- After writing it, report the path and note that it is now safe to compact or
  start a fresh session.

## When to suggest it

When the context indicator goes amber or red and the task is still open. The
order matters: handoff first, compact second. Compacting first destroys exactly
what needed to be written down.
