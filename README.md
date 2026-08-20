# claude-context-kit

The expensive thing in a long Claude Code session is not what you ask, it is how
long you have been asking.

The whole conversation is resent on every single call. A session that runs for
900 calls pays for everything accumulated so far, 900 times over. The cost grows
with the square of the length, and nothing in the interface tells you this is
happening until the bill does.

This kit puts it in the status bar and tells you when to act.

```
myproject  Opus 5  22% ctx  30% wk  ~$18
myproject  Opus 5  55% ctx -> /handoff and /compact  30% wk  ~$18
myproject  Opus 5  85% ctx -> /handoff + /compact NOW  70% wk  38 MB res
```

At 55% of the context window it suggests writing your notes to disk and
compacting. At 85% it stops suggesting and starts insisting. It never compacts
for you: it puts the decision where you will see it.

It also blocks one specific thing: taking a screenshot of something you have not
edited since the last one. That image is byte-for-byte identical to one already
in the context, and it will be resent on every call for the rest of the session.

## Why it exists

Measured on one real session before any of this was in place:

| | |
|---|---|
| **Tool calls in a single conversation** | **973** |
| Transcript on disk | 51 MB |
| Screenshots | 157 |
| Screenshots of a node that had not changed | 87 (55%) |
| Worst single node | captured 20 times |

The length is the headline. The screenshots are what made the slope steeper:
each one leaves roughly 112 KB in the context permanently, so a session heavy on
images gets there faster. A long session with no images at all still gets there.

The rules against all of this were already written down, in the config file that
gets loaded every session. They were being read. They did not survive contact
with a task in progress, which is why most of this kit reports rather than
reminds, and why exactly one part of it blocks.

## What each piece does

| File | Event | What it does |
|---|---|---|
| `statusline-context.sh` | statusLine | Context %, quota, cost, active account |
| `stop-compact-nudge.sh` | Stop | Says out loud, once per tier, that it is time to compact |
| `paper-shot-guard.sh` | PreToolUse | **Blocks** a 4th screenshot of an unedited node |
| `session-size-warn.sh` | PostToolUse | Counts calls, screenshots and per-node captures |
| `context-weight.sh` | PostToolUse | Real bytes per tool, so you know what filled the context |
| `compact-reset.sh` | UserPromptSubmit | Resets the counters on `/compact` |

Plus a `handoff` skill that writes decisions and dead ends to disk before you
compact.

## The statusline

Every number comes from the JSON Claude Code already passes on stdin:
`context_window.used_percentage`, `rate_limits.seven_day`, `cost.total_cost_usd`.
Nothing is estimated. Screenshot and byte counters only appear once they are a
problem, so a clean session stays quiet.

Two details worth knowing:

**The dollar figure is a shadow price on a subscription.** Claude Code reports
what the work would have cost on the API. On Max, Pro or a Team seat you are not
billed per token, so the kit dims it and prefixes `~`. On a flat plan the number
that can actually stop you is the quota, which is why `% wk` sits ahead of it.

**The account label** (`alice max`, `alice team`) appears when a credential is
readable, and **follows `/login`.** If you switch between a work and a
personal account, the statusline rereads the live credential on every redraw. If
two credential files disagree and were touched within a minute of each other, it
shows `account?` in amber rather than asserting one that might be wrong.

## The screenshot guard

This is the only piece that blocks rather than warns, and the reasoning is
narrow: taking the same screenshot of a node you have not edited is not a
judgement call the user should keep making, it is a mistake. If the node did not
change, the image is identical.

Three captures of the same node pass. The fourth is denied with a reason. Any
edit to that node resets the counter, so the normal edit-then-look loop is
untouched. Escape hatch: `PAPER_SHOT_GUARD=off`.

It matches `mcp__paper__get_screenshot`, so it is only useful with
[Paper](https://paper.design). Adapt the matcher for another MCP that returns
images.

## The compaction nudge

Warns at 55% of the context window, then every 15 points. Reads the real token
usage from the transcript rather than counting calls: one call can weigh 900
bytes or 700 KB, so counting them is a poor proxy.

It never compacts for you. It writes the suggestion where you will read it and
stops.

The order it suggests is deliberate: `/handoff` first, `/compact` second.
Compacting first destroys exactly the decisions and dead ends worth keeping.

## The handoff skill

Compacting is lossy. It keeps a summary and drops the rest, and what it drops
first is usually the reasoning: why you rejected the other approach, which three
things you already tried that did not work.

`/handoff` writes that to a file before you compact, in four sections: state,
decisions and **why**, next step, and traps. The traps section is the one that
earns its keep, because a dead end is recorded nowhere else. The code only shows
what worked.

Hence the order the kit suggests, handoff first and compact second. Doing it the
other way round destroys exactly what you were about to write down.

This is also the one part of the kit that is not really an invention. Dumping
state to markdown and starting fresh is the most widely agreed-on answer to this
problem, showing up in Anthropic's own guidance on context engineering and in
more or less every thread where people compare notes.

## Install

```bash
git clone https://github.com/dsaltaren/claude-context-kit
cd claude-context-kit
./install.sh
```

Then merge the printed snippet into `settings.json`. The installer deliberately
does not edit that file for you.

Requires bash and Python 3 (both present on macOS by default). Verified against
Claude Code 2.1.237.

## Caveats

- **Statusline thresholds are tuned for a 1M context window.** On a 200K window
  the percentages still work, but you will want to warn earlier.
- **The guard is Paper-specific** as written.
- **`context-weight.sh` is partly redundant** now that the native `%` exists. It
  is kept because it is the only piece that reports *which* tool consumed the
  context, which the native field does not.
- **Nothing here is a substitute for delegating to a subagent.** A subagent's
  screenshots live in its context, not yours. That is the only lever that
  actually breaks the drag; this kit just makes the drag visible.
- Since v2.1.198, subagents inherit the session model. `Explore` and
  `general-purpose` are no longer free Haiku. Set
  `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (or `haiku`) if you assumed otherwise.

## License

MIT
