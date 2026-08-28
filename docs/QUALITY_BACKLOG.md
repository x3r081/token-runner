# Quality Backlog

Prioritized, player-experience-focused defect and improvement list. Reassessed
every iteration by fresh playtesting. Priorities:

- **P0** release-blocking (crashes, soft-locks, unplayable)
- **P1** major player-facing quality gap (looks like programmer art, shallow gameplay)
- **P2** meaningful polish / depth
- **P3** nice-to-have

## P0 — Release blocking

- [x] Enemies can soft-lock player movement via collision. *(Iteration 1: masks
  fixed, steering + separation, dash/Force Push escape, regression test.)*

## P1 — Major player-facing gaps

- [ ] **Localhost composition**: ~half the viewport is dead/black space; camera
  framing and world bounds not intentional. Fix camera zoom/bounds; design a
  full, framed interior at 1920x1080 and 2560x1440.
- [ ] **Stamped floor**: repeated 2-tile checker reads as procedurally stamped.
  Replace with a designed interior (zones: desk battlestation, server corner,
  kitchen/energy-drink area, sleeping area, node_modules "trash").
- [ ] **Player art**: still crude; needs coherent character with readable
  silhouette + animation set.
- [ ] **Enemy identity**: red blobs don't communicate what they are. Each enemy
  type needs a distinct silhouette, telegraph, behavior, death.
- [ ] **Gameplay depth**: currently walk + collect + shoot. Needs decisions,
  branching quests, model selection, agent system, architecture tradeoffs.
- [ ] **Comedy as mechanics**: jokes are mostly static labels. Build event- and
  quest-driven comedy (Just One Tiny Change, Free Tier, The Autonomous Agent).

## P2 — Depth & polish

- [ ] Multi-stage/branching quests with consequences, failure states, callbacks.
- [ ] Technical-debt systemic consequences (bugs spawn, costs rise, incidents).
- [ ] Ship-before-reset cycle system (quotas reset, prices shift, expectations).
- [ ] NPC personalities with memory and evolving dialogue (Claude + archetypes).
- [ ] Combat abilities beyond Prompt Blast/Cache/Dash (Rollback, Rubber Duck,
  Stack Trace, Ctrl+Z, Agent Swarm...).
- [ ] Environmental interactables with readable comedy (monitors, fridge, plant,
  whiteboard, router, terminal `npm audit`).
- [ ] HUD to polished indie quality.
- [ ] Conservative, validated, normalized audio (no harsh noise, nothing before
  init).

## P3 — Nice to have

- [ ] Achievements tied to running gags (IT WAS DNS, BORING RESPONSIBLE ADULT).
- [ ] Post-game content.
- [ ] Additional regions polished to Localhost quality.

## Iteration protocol

1. Fresh-save playtest (1/5/15/30 min lenses). Capture screenshots/video.
2. Inspect the actual output; identify the single largest player-facing weakness.
3. Fix it. Re-test. Capture evidence.
4. Update this backlog + `AUTONOMOUS_STATUS.md`. Commit + push. Repeat.
