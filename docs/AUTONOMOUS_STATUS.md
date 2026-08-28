# Autonomous Development Status

Living status log for the ongoing effort to turn **Token Runner** into a
competitive, polished hackathon PC game. Updated every iteration.

> Checked-off items are **not** a completion signal. Completion is defined by
> repeated critical playtesting finding no high-severity player-facing issue.
> See `QUALITY_BACKLOG.md` for the prioritized problem list.

## Current focus

Iteration 2 complete — Localhost visual redesign. Next: enemy identities +
gameplay/comedy systems depth.

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

## Verified test commands

```bash
godot --headless --path . --script scripts/tools/run_generate.gd
godot --headless --path . --import
godot --headless --path . --scene tests/smoke_test.tscn        # 8/8
godot --headless --path . --scene tests/soft_lock_test.tscn    # 4/4
godot --headless --path . --quit-after 1
```

## Next iteration (planned)

See `QUALITY_BACKLOG.md`. Next largest player-facing weakness: **Localhost
visual composition** (dead space, stamped floor, weak hierarchy) and the
**player/enemy art readability**.
