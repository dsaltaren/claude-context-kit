# claude-context-kit

Six hooks and a statusline that keep a long Claude Code session from quietly
getting expensive.

In Claude Code the whole context is resent on every call, so the cost of a
session grows with the square of its length. A single screenshot is not
expensive because of the one call that requests it, but because of the four
hundred calls that resend it afterwards.

This kit does three things: it shows the numbers that actually matter, it says
when to compact, and it blocks the one action that is never worth taking.

## Why it exists

Measured on one real design session before any of this was in place:

| | |
|---|---|
| Tool calls | 973 |
| Screenshots | 157 |
| **Screenshots of an unchanged node** | **87 (55%)** |
| Worst single node | captured 20 times |
| Transcript on disk | 51 MB |

Those 87 repeats returned an image identical to one already in the context. The
rules against it were written down and were being read. They did not survive
contact with a task in progress.

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

```
myproject  Opus 5 1M  15% ctx  alice max  30% wk  ~$50
myproject  Opus 5 1M  55% ctx -> /handoff and /compact  alice max  30% wk  ~$50
myproject  Opus 5 1M  85% ctx -> /handoff + /compact NOW  ...  70 shots  38 MB res
```

Every number comes from the JSON Claude Code already passes on stdin:
`context_window.used_percentage`, `rate_limits.seven_day`, `cost.total_cost_usd`.
Nothing is estimated. Screenshot and byte counters only appear once they are a
problem, so a clean session stays quiet.

Two details worth knowing:

**The dollar figure is a shadow price on a subscription.** Claude Code reports
what the work would have cost on the API. On Max, Pro or a Team seat you are not
billed per token, so the kit dims it and prefixes `~`. On a flat plan the number
that can actually stop you is the quota, which is why `% wk` sits ahead of it.

**The account label follows `/login`.** If you switch between a work and a
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

## Install

```bash
git clone https://github.com/<you>/claude-context-kit
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
