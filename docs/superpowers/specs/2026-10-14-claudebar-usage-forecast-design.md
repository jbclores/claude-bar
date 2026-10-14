# ClaudeBar Usage Forecast, Warnings and History — Design

**Date:** 2026-10-14
**Status:** Approved in chat, awaiting spec review
**Part 1 of 3** of the new features (Usage; then Comfort: quiet hours and a shortcut; then Sessions: jump, answer, recap).

## Goal

ClaudeBar tells you where your Claude usage is heading, not only where it is: a quiet forecast line under the usage
bars, one warning when you are on track to hit a limit before it resets, today's usage as a sparkline, and the last 7
days as a small chart.

**Success criteria**

- Under the bars, a grey line always says where the pace leads ("On pace for about 55% of the 5-hour limit by
  5:40 PM"); it turns amber and says when the pace reaches a limit before its reset.
- At most one notification per usage window, the first time the forecast says a limit will be hit before it resets.
- A sparkline of today's 5-hour usage sits under the bars; clicking the usage area folds out the 7-day chart.
- Nothing new leaves the Mac; the log stays in ClaudeBar's own folder and Undo removes it.

## 1. The usage log (Core `UsageHistory`)

- **Source:** the usage ClaudeBar already reads (the status line's `rate_limits`, via `PlanUsageReader` and the
  snapshots: `UsageSummary`): 5-hour and 7-day percentages and their reset times.
- **Sample:** `{ at, fiveHourPct, fiveHourResetsAt, sevenDayPct, sevenDayResetsAt }`, added when the reading changes
  (any of the four values, or its `asOf`), at most one per minute.
- **File:** `~/.claude/claude-bar/usage-history.jsonl`, one sample per line, in ClaudeBar's own usage folder (already on
  the "What ClaudeBar changes" page and removed by "Also remove ClaudeBar"). Kept to the last 30 days: older lines are
  dropped when a sample is added. A damaged line is skipped, never fatal.
- History starts when this ships; nothing from before is reconstructed.

## 2. The forecast (Core `UsageForecast`)

For each window (5-hour, 7-day), from the samples since that window's current reset began (same `resetsAt`):

- **Pace:** the rise in percent over the last 60 minutes of samples (at least two samples at least 10 minutes apart and
  a rise); else no pace.
- **Projection:** the percentage at the reset if the pace holds, capped at 100; with no pace, the current percentage.
- **Hit time:** when the projection reaches 100 before the reset, the time it gets there.
- **The line** (always shown when there is usage):
  - The window at risk (hit before reset) wins, the 7-day one first; else the 5-hour window.
  - At risk, amber: "At this pace you'll reach the 5-hour limit around 3:40 PM" (or "the 7-day limit around Fri 2 PM").
  - Else grey: "On pace for about 55% of the 5-hour limit by 5:40 PM" (rounded to 5%; the reset time).
  - No usage reading: no line.

## 3. The warning

- A macOS notification the first time, in a given window (keyed by its `resetsAt`), the forecast says that limit is hit
  before reset: "At this pace you'll reach your 5-hour limit around 3:40 PM. It resets at 5:00 PM."
- Never twice for the same window; a new window can warn again.
- Settings → General: **Warn before I hit a usage limit** (on at first). Uses the same notification permission as
  "Notify when a cat finishes".

## 4. Today's sparkline

- A thin line (about 14 pt tall) under the two bars: today's 5-hour percentage from the log since local midnight, 0–100%
  scale, a step line (usage only changes at samples); a drop at a 5-hour reset shows as a drop.
- Hidden with fewer than two samples today.

## 5. The week chart

- Clicking the usage area (bars, sparkline, forecast line) folds out a chart under them; clicking again folds it.
- Seven bars, today and the six days before: each day's highest 5-hour percentage (0–100%), labelled by weekday, today
  last; a day with no samples shows no bar.
- Under it, each time a limit was reached in those days (a sample at 100%): "Limit reached: Fri 2:15 PM" (5-hour) or
  "7-day limit reached: …", newest first, at most three.
- Folded at every opening of the dropdown.

## Units

| Unit | Role |
|---|---|
| `UsageHistory` (Core) | Samples: add (on change, ≤ 1/min), read, trim to 30 days, today's samples, daily highs, limit hits |
| `UsageForecast` (Core) | Pace, projection, hit time, the line and its tone, the window to warn about |
| `UsageWarner` (Core) | Warn once per window (by `resetsAt`) |
| `AppState` | Records each usage reading, publishes the forecast, posts the warning |
| Usage header view | Forecast line, sparkline, click to fold the week chart |
| Settings | "Warn before I hit a usage limit" |

## Testing

- **Core:** the log (add on change only, one per minute, 30-day trim, damaged lines skipped); the forecast (steady
  pace, speeding up, no recent rise, too few samples, a reset starting a new window, 7-day at risk wins); daily highs
  and limit hits over local days; warn once per window and again in the next.
- **Renders** (sample logs through a render-only env var): the grey and the amber line, the sparkline, the week chart
  unfolded, light and dark.
- All existing tests and click tests pass.

## Out of scope

- Money costs; per-project usage (the status line reports the account's limits only).
- History from before this ships.
- Quiet hours (part 2) — the warning will respect them once they exist.
