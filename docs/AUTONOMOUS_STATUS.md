# Autonomous Development Status

Living status log for the ongoing effort to turn **Token Runner** into a
competitive, polished hackathon PC game. Updated every iteration.

> Checked-off items are **not** a completion signal. Completion is defined by
> repeated critical playtesting finding no high-severity player-facing issue.
> See `QUALITY_BACKLOG.md` for the prioritized problem list.

## Current focus

Iteration 3 complete — comedy-as-mechanics storyline system + flagship quest.
Next: more staged quests (Free Tier, The Autonomous Agent), remaining enemy
identities, model-selection/agent systems.

## Iteration log

### Iteration 1 — Soft-lock elimination + escape toolkit
- **P0 FIXED: enemy collision soft-lock.** Player (`collision_mask 34 -> 32`)
  and enemies (`collision_mask 33 -> 32`) now collide only with walls, never
  with each other. A ring of enemies can no longer physically pin the player.
- **Enemy steering.** Enemies now hold at an engage distance and repel each
  other (`_separation()`), so they surround the player readably instead of
  stacking into a wall of bodies. Knockback resolves independently of AI.
- **Dash / Force Push escape ability** (`Shift` or `Q`): a fast i-frame burst in
  the facing direction that shoves nearby enemies away — a guaranteed crowd
  escape and new combat tool. Cooldown 1.1s.
- **Automated regression test** `tests/soft_lock_test.tscn`: surrounds the
  player with 8 enemies and asserts (a) collision masks exclude the opposing
  body, (b) walking escapes the ring, (c) Force Push pushes enemies away. Wired
  into CI after the smoke test.
- Verified: soft-lock test 4/4, smoke test 8/8.

### Iteration 2 — Localhost visual redesign
- Root cause of "programmer-art field" was using **outdoor grass tiles** for the
  apartment floor. Added `scripts/tools/interior_generator.gd` producing a real
  interior art set: warm wood plank floors, rug, industrial walls, night-city
  window, and hand-drawn furniture (desk, monitors, server rack, bed, fridge,
  coffee, deprecated plant, node_modules boxes, bookshelf, chair, door,
  whiteboard).
- Rewrote `localhost_builder.gd` into a **designed, zoned apartment**: two
  battlestations (left resource monitors + right GPU-rig), server corner,
  energy-drink kitchen, unslept-in bed, couch, node_modules heap, cable
  spaghetti, wall posters.
- **Readable comedy monitors**: TOKEN BALANCE 70, AI SUBSCRIPTIONS 8, SAVINGS
  FROM AI -€713/mo, GPU TEMP 94°C, `npm audit` 847 vulns / 0 fixed.
- **Bug enemy** redrawn as a readable beetle (carapace, legs, antennae, eyes).
- **Camera bounds** clamp to the room (no off-map dead space). Warmer ambient.
- Floor de-tiled: removed repeating knot feature, added per-tile jitter + grime.
- Verified: smoke 8/8; visual confirmed via screenshots (before → v3).

### Iteration 3 — Comedy-as-mechanics storyline system
- New **staged storyline engine** in `EventManager` (`start_scripted`) that
  reuses the event popup to run multi-stage, branching narrative beats with
  escalating consequences, achievements, and quest-chain completion.
- Implemented the flagship **"Just One Tiny Change"** (`scripts/world/story_events.gd`):
  green button → component-library upgrade → 17 components render as horses →
  CI on fire → design-system migration → "actually we preferred blue" → restore
  original. Payoff: +300 Tokens, +43 Technical Debt, -12 Will To Live, **AGILE**
  achievement. Triggered by checking the client email (laptop); inbox becomes a
  running gag afterward.
- **Fixed a latent event-popup soft-lock**: popup paused the tree but its buttons
  were `PAUSABLE`, so choices could not be clicked. Popup now processes while
  paused (`process_mode = ALWAYS`). This affects all random events too.
- Popup **UI polish**: dimmed backdrop, solid neon-bordered panel, larger type,
  keyboard/controller focus (confirm with Enter).
- **Interact range** widened (40 → 56) for better feel.
- Added achievements: AGILE, IT WAS DNS, Boring Responsible Adult, Terms & Cond.
- Regression test `tests/story_test.tscn` drives the storylines to completion
  and asserts rewards, achievements, script + quest completion, and the chained
  next quest. Wired into CI.
- Added two more flagship storylines via the same engine (now 19/19 tests):
  - **Free Tier**: 10,000 "free" tokens gifted, then 9,970 reclaimed by updated
    fine print ("still technically up to 10,000"). Achievement: Terms & Cond.
  - **The Autonomous Agent**: delegate renaming a variable; the agent installs
    12 deps, rewrites auth, opens a "minor cleanup" PR (+4,812/-9), spawns a
    second agent, and holds a retro about you. Costs debt + will to live.
  - Triggered by color-coded, signposted props in Localhost.

## Verified test commands

```bash
godot --headless --path . --script scripts/tools/run_generate.gd
godot --headless --path . --import
godot --headless --path . --scene tests/smoke_test.tscn        # 8/8
godot --headless --path . --scene tests/soft_lock_test.tscn    # 4/4
godot --headless --path . --scene tests/story_test.tscn        # 11/11
godot --headless --path . --quit-after 1
```

## Next iteration (planned)

See `QUALITY_BACKLOG.md`. Candidate next largest player-facing weaknesses:
1. **Enemy identities** — only `bug` (beetle) is redesigned; rate_limiter,
   memory_leak, merge_conflict, scope_creep, rogue agent, and bosses still read
   as colored blobs. Give each a silhouette + telegraph + death.
2. **Combat depth** — add abilities beyond Prompt Blast / Cache / Dash
   (Rollback, Rubber Duck, Stack Trace, Ctrl+Z) that interact with enemy
   mechanics.
3. **Systemic technical-debt consequences** — make accumulated debt spawn bugs,
   raise costs, and trigger incidents (ties the comedy rewards to real stakes).
4. **Ship-before-reset cycle** — strategic reset periods (quotas reset, prices
   shift, expectations change).
5. **Player art** — higher-fidelity character.

Exact resume point: pick weakness #1 (enemy identities) — extend
`asset_generator_runtime._generate_enemies()` with distinct per-type art like
the beetle, then add per-type telegraphs/behaviours in `enemy_base.gd`.
