# Manual Apply UX Scenario Index

This folder tracks manual-apply UX behavior by hunk shape instead of by implementation detail.

The goal is simple:

- keep one document per scenario
- record what currently works
- record what still feels awkward
- make regressions and improvements easy to compare over time

## Scenario Set

- [Pure Insert](/home/neepo/.config/nvim/doc/manual_apply_ux_insert.md)
- [Pure Delete](/home/neepo/.config/nvim/doc/manual_apply_ux_delete.md)
- [Equal-Size Replace](/home/neepo/.config/nvim/doc/manual_apply_ux_replace_equal.md)
- [Shrinking Replace](/home/neepo/.config/nvim/doc/manual_apply_ux_replace_shrink.md)
- [Expanding Replace](/home/neepo/.config/nvim/doc/manual_apply_ux_replace_expand.md)
- [Multi-Hunk Session](/home/neepo/.config/nvim/doc/manual_apply_ux_multi_hunk.md)

## How To Use These Docs

For each scenario, track:

- what the current UI shows
- whether the next edit action is obvious
- whether real buffer text remains visible when needed
- whether the user can complete the hunk without fighting the overlay
- whether completion state is understandable

## Suggested Review Loop

1. Trigger a real payload with one clear example of the scenario.
2. Note first-impression friction before adapting to the UI.
3. Note the minimal key sequence that successfully completes it.
4. Record whether the friction is a training problem or a design problem.
5. Capture the next UX change only if it improves that scenario without harming the others.
