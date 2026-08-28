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

- [x] **Localhost composition**: was ~half dead space. *(It2: zoned interior +
  camera bounds; content now spans full width. Follow-up: verify at 1440p,
  add foreground occlusion.)*
- [x] **Stamped floor**: was grass-tile field. *(It2: wood plank interior floor,
  de-tiled with jitter/grime; knot repetition removed.)*
- [ ] **Player art**: still crude; needs coherent character with readable
  silhouette + animation set. *(Hoodie coder is okay but low-res; revisit.)*
- [~] **Enemy identity**: distinct silhouettes done for bug (beetle),
  rate_limiter (barrier), memory_leak (dripping blob), merge_conflict
  (split red/blue), scope_creep (expanding arrows), dependency_demon (spider
  knot), hallucination (multi-eyed ghost). Remaining: per-type **telegraphs /
  behaviors / death effects**, and boss visuals (enterprise_architect,
  legacy_monolith, infinite_context).
- [~] **Gameplay depth**: added combat abilities, model selection, technical-debt
  consequences, the reset cycle, a deployable-agent system, and Dream App
  architecture tradeoffs. Still open: more branching quests with multiple endings,
  NPC memory/personality, running-gag callbacks.
- [~] **Comedy as mechanics**: staged storyline engine shipped; **Just One Tiny
  Change** implemented end-to-end. Still to do: Free Tier, The Autonomous Agent,
  and more branching scenarios with consequences.

## Composition / resolution

- [x] **1080p & 1440p composition**: removed the hard 1920×1080 window override
  that black-barred the game at higher resolutions; window is now resizable and
  content scales (stretch canvas_items/expand). Verified Localhost at 1920×1080
  and 2560×1440. *(It13.5)*

## P2 — Depth & polish

- [ ] Multi-stage/branching quests with consequences, failure states, callbacks.
- [x] Technical-debt systemic consequences: costs rise, stability drains, bugs
  spawn on dependency-break incidents (safe below threshold). *(It7)*
- [x] Ship-before-reset cycle system: timed cycles with quota refill, debt
  reckoning, vendor price shifts, reset warning + HUD readout. *(It8)*
- [~] NPC personalities with memory and evolving dialogue: **Claude** is now
  fully reactive with memory + a backups running-gag callback. Other archetype
  NPCs still use static dialogue.
- [~] Combat abilities beyond Prompt Blast/Cache/Dash: added **Rubber Duck**
  (AoE stun) and **Stack Trace** (piercing); **HUD ability bar** now shows all
  5 slots with keys/costs and dims when on cooldown/unaffordable. Still open:
  Rollback, Ctrl+Z, Agent Swarm.
- [x] Enemy behaviours: signature per-type behaviours + telegraphs (split, grow,
  429 pulse, blink), plus **boss** art + telegraphed slam + summons. *(It6, It17)*
- [ ] Environmental interactables with readable comedy (monitors, fridge, plant,
  whiteboard, router, terminal `npm audit`).
- [ ] HUD to polished indie quality.
- [x] Conservative, validated, normalized audio: silent-by-default, conservative
  volumes, **Master hard limiter**, verified no near-full-scale samples. *(It16)*

## P3 — Nice to have

- [x] Achievements tied to running gags: **IT WAS DNS** (production incident) and
  **Boring Responsible Adult** (backups) both implemented + tested. *(It14–15)*
- [ ] Post-game content.
- [~] Additional regions polished: all 9 now themed compositions (It10). Could
  still be raised toward Localhost's hand-crafted density.

## Iteration protocol

1. Fresh-save playtest (1/5/15/30 min lenses). Capture screenshots/video.
2. Inspect the actual output; identify the single largest player-facing weakness.
3. Fix it. Re-test. Capture evidence.
4. Update this backlog + `AUTONOMOUS_STATUS.md`. Commit + push. Repeat.
