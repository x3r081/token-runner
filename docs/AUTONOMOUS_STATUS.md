# Autonomous Development Status

Living status log for the ongoing effort to turn **Token Runner** into a
competitive, polished hackathon PC game. Updated every iteration.

> Checked-off items are **not** a completion signal. Completion is defined by
> repeated critical playtesting finding no high-severity player-facing issue.
> See `QUALITY_BACKLOG.md` for the prioritized problem list.

## Current focus

Iteration 49 — clean confirmation playtest (combat now fair) + early-economy tune.
Next: hand-crafted per-region furniture; more quest categories; keep playtesting.

### Iteration 49 — Confirmation playtest: combat fair, no high-severity issues
- Live confirmation playtest after the aim-assist fix: **combat is now fair and
  winnable** ("went from impossible to winnable and accessible" — killed enemies,
  survived at full HP, aim-assist visibly hits). **No high-severity issues** (no
  crashes/soft-locks/stuck/unplayable). Core loop fully functional end-to-end;
  pause/resume works. Rated a competitive 7/10.
- This gives us **repeated critical playtests (It47 + It49) finding no
  high-severity player-facing issue**, with combat now accessible.
- Addressed the tester's one nit (early token economy slightly tight): starting
  tokens 50 -> 65 (tension preserved; tokens are both ammo and upgrade currency).
  Full suite: **27 suites green**.

### Iteration 48 — Aim-assist (the real fix for punishing combat)
- A confirmation playtest of the It47 count reduction still failed combat ("couldn't
  kill even ONE enemy, died repeatedly") — which finally exposed the ROOT cause:
  attacks fired only in the player's 8-direction **facing** (last movement), so a
  real player's shots mostly **missed** the moving enemies. (My earlier headless
  "winnable" checks cheated by aiming perfectly each shot.)
- Fix: `_fire_projectile` now **auto-targets the nearest living enemy** within 640px
  (falls back to facing when none near). For an accessible comedy game the challenge
  is kiting/resources, not twitch-aiming.
- Verified headless: `region_winnable_test` rewritten to face the WRONG way and rely
  solely on aim-assist — player clears the first region and survives, 3/3 stable.
  Verified live (video review): projectiles fire toward enemies from all angles,
  hit/knockback/pop; the stationary, wrong-facing player clears threats from every
  side, no glitches. Full suite: **27 suites green**.

### Iteration 47 — Critical playtest (no soft-locks) + fair first combat region
- Ran a harsh QA playtest. **No soft-locks, crashes, or unplayable states.** Core
  loop verified end-to-end: move -> collect (counter rises) -> Claude dialogue
  (quest completes) -> Dream App upgrade -> map fast-travel -> death/respawn ->
  pause. Onboarding clear, [E] prompts work, comedy "excellent", UI clean. Rated
  7/10, held back only by combat difficulty.
- Two playtests now flag Dependency District combat as punishing. Ground truth
  (headless, current build): a stationary player in the middle of all 7 enemies
  survives **14.4s** (the "2s" claim is 7x exaggerated; i-frames work) -- but
  clearing 7 enemies takes ~11s, so a new player loses the race. Localhost has 2;
  jumping to 7 in the first combat region is a spike.
- Fix (evidence-based, not a blanket nerf): first combat region reduced to **4
  enemies**. Verified winnable end-to-end -- a button-masher clears it in ~6.3s
  taking zero damage. Later regions keep higher counts. New `region_winnable_test`.
  Full suite: **27 suites green**.

### Iteration 46 — Ctrl+Z ability (panic undo)
- Added a 6th, tactically-distinct ability from the brief's list. **Ctrl+Z** ([5],
  4 context, 10s cd) restores the HP you had ~2.6s ago — an emergency "undo that
  hit" button, distinct from Cache (i-frames) and Dash (escape), reinforcing the
  never-soft-locked design. Rolling HP history; won't over-heal or refund on cd.
- Wired into input, the HUD **6-slot ability bar** (widened; verified rendering at
  1440p: `[1] Prompt Blast [2] Cache [3] Rubber Duck [4] Stack Trace [5] Ctrl+Z
  [Q] Dash/Push`), and the onboarding controls list. `combat_test` covers
  restore/cost/cooldown (15 checks). Full suite: **26 suites green**.

### Iteration 45 — Composition re-verification (1080p + 1440p)
- Re-verified the explicit requirement "looks good at 1920x1080 AND 2560x1440" now
  that bloom, props, animation, and combat juice have landed. Captured Localhost at
  2560x1440 (forced the window to fill the display): the apartment fills the whole
  frame with **no dead space / no black bars**, the HUD scales correctly (full-width
  top bar, quest panel with live objectives, and the ability bar showing all 5
  abilities with keys/costs), and the bloom renders at 1440p (tokens glow). 1080p
  verified via the glow capture. No regressions; no code change required.

### Iteration 44 — Subtle bloom/glow (visual pop)
- Reviews called the look "slightly blocky/flat (7/10)." Added a `WorldEnvironment`
  bloom (SCREEN blend, intensity 0.75, hdr_threshold 0.9) + enabled HDR 2D so the
  emissive elements (tokens, monitor screens, neon signs, projectiles, point
  lights) glow.
- Verified on the opengl3 (Compatibility) backend the env runs on: first cranked
  the glow to confirm the pipeline renders at all, then tuned down. Result: tokens
  sparkle with a soft halo and screens/signs bloom gently, while floor/walls/UI
  stay un-washed-out. Applies to all regions.
- Rendering-only change; headless suites unaffected. Full suite: **26 green**.

### Iteration 43 — Session review + menu no-trap exits
- Recorded an end-to-end session and had it critically reviewed. Confirmed the game
  reads as competitive: visuals 7/10 ("intentional, inhabited, cohesive indie pixel
  art, effective lighting"), humor "a strong point / spot-on," HUD "clean and
  readable." No real game bug found.
- The review's "freeze" was the driver getting stuck in the multi-stage Architecture
  menu — which surfaced a genuine UX gap: the repeatable terminal menus forced a
  decision with no way out. Added **"Decide later (close)"** to each architecture
  decision and **"Not now (close)"** to the agent deploy menu, so the player can
  always back out (menus are reopenable). `architecture_test` asserts every stage
  has a non-committing exit that closes cleanly. Full suite: **26 suites green**.

### Iteration 42 — Combat impact/juice
- Playtest called combat "flat projectile spam." Gave every hit weight:
  - **Hit knockback**: projectiles shove the enemy along the shot (320 prompt-blast
    / 430 stack-trace; bosses flinch at 0.25x).
  - **Death pop**: enemies flash white, punch up in scale, and emit a burst of
    reddish debris before fading (was: instant silent vanish).
- Caught and fixed a tween bug (queue_free fired immediately → instant vanish) and
  guarded the idle-animation `_process` from fighting the death tween. First video
  review flagged both features as absent (the tween bug); after the fix, review
  confirmed "much more impactful and satisfying," no glitches.
- `combat_test` asserts hit-knockback (11 checks). Full suite: **26 suites green**.

### Iteration 41 — Onboarding: controls + goal card
- A fresh full playtest's #1 complaint was "no clear goal / didn't know what to do
  or how to interact" — the boot sequence is comedy, not a tutorial. (Its other
  claims — props/Claude/model-toast "broken" — were verified FALSE this session:
  `flavor_try.png`, `npc_reactive.png`, and `_on_model_changed`'s toast all work;
  the agent simply failed to navigate to props.)
- Added a **one-time onboarding card** shown when control is first granted in
  Localhost: states the GOAL (ship the Dream App before the reset) and the loop
  (tokens -> Dream App [B] -> ship requirements -> Deploy), lists all controls, and
  points to the first step (talk to Claude, grab tokens). Dismisses on E/click.
- Verified live (card renders with goal + controls) + `ui_overlay_test` (9 checks:
  shown once, states goal, lists controls, no duplicate). Full suite: **26 green**.
- Also verified the victory "get roasted" climax live — "YOU SHIPPED IT / Beautiful
  Disaster" with a fully personalized roast from the run's choices. Looks
  competitive; no change needed.

### Iteration 40 — "The All-Hands Demo" (branching quest + failure state)
- New quest category (high-stakes live performance), triggered on first entering
  Corporate Enterprise. Three branches with distinct endings:
  - **Stable happy path** → modest reputation + tokens.
  - **Go big (experimental feature LIVE)** → an `ai_gamble` keyed on your selected
    MODEL: a reliable model earns a standing ovation (+16 rep, +220 tk, *Shipped
    Live*); an unreliable one hallucinates on stage and the app 500s in front of
    847 people (−rep/−stability/−WTL + debt, *Live On Main*). Model choice matters.
  - **Fake it** (pre-recorded demo) → works until the SVP asks you to click a live
    button (−rep/−WTL).
- Verified live (event triggers + renders in Corporate Enterprise) and via
  `story_test` (branches, both gamble outcomes reachable by model, rep loss on the
  fake path). Full suite: **26 suites green**.

### Iteration 39 — De-stamped, denser region visuals (all 9 regions)
- Regions read as a bare tinted floor with props in the corners. For every region:
  - **Floor de-stamping** to match Localhost: grime/scorch + lighter wear tiles,
    plus ~46 scattered debris decals (specks, hairline cracks, faint themed
    glow-chips) so tiling never reads as a stamped grid.
  - **Depth + ambient clutter**: a wall-base shadow band, faint cable/pipe runs,
    and 14 small pieces of the region's OWN pixel-art structure vocabulary
    (crates/towers/consoles/orbs) scaled down and scattered around the perimeter
    (central spawn lane kept clear; all non-colliding) — reads as intentional
    set-dressing, not programmer-art squares.
  - Verified via capture (Dependency District: grimier floor + scattered packages).
- Also fixed `animation_test` flakiness (disable EventManager; compare hop depth).
  Full suite: **26 suites green**.

### Iteration 38 — Procedural idle/move animation (the "animation" requirement)
- Enemies and NPCs were static sprites — dormant enemies and NPCs looked painted
  onto the floor. Added per-frame procedural animation:
  - **Enemies** breathe (bob + squash) when idle and do a **springy scuttle-hop**
    with squash-and-stretch + waddle when moving (dizzy wobble when stunned);
    phases randomized so a group doesn't bob in lockstep.
  - **NPCs** breathe (bob + subtle scale); the quest indicator floats.
  - The **player** now breathes while standing idle (its special idles only fire on
    an 8-18s timer, so it otherwise looked frozen).
- Verified via video review ("absolutely makes the scene feel alive", lively but
  not jittery/nauseating, no glitches) and a new `animation_test` (sprites provably
  move; scuttle range > idle range). Full suite: **26 suites green**.

### Iteration 37 — Reactive dialogue for all archetype NPCs
- The 9 regional NPCs were static; now each prepends an in-character, state-aware
  quip to its greeting and evolves via a per-NPC talk counter — matching Claude's
  aliveness across the roster. They react to technical debt, stability, deaths,
  the cycle, tokens, deployed agents, and architecture choices. Examples: the
  Maintainer ("You reek of technical debt. It's a bold cologne."); the Cloud
  Salesperson gloats about your invoice iff you chose cloud hosting; the On-Call
  Engineer reads your stability off the pager; the Junior Agent formed a Slack with
  your other agents.
- Verified live (Dependency District Maintainer reacting to high debt) + unit
  tests (`dialogue_test` now 14 checks: reactive intro, correct speaker,
  state-specific reaction, safe no-op for unknown NPCs). Full suite: **25 green**.

### Iteration 36 — Environmental comedy props in every region
- Extended the FlavorPopup system beyond Localhost to **all 9 regions** (brief:
  "every major environment should reward exploration"). 19 new theme-specific
  props: node_modules ("its own gravity now"), left-pad, the package-lock
  folklore, API reseller stall + cached status page, Stack Overflow question
  gravestones, cloud invoices ("successful adoption", €4,207), mining rigs +
  cooling fan, the $7/month open-source sponsor button + a 3-year-old "URGENT:
  doesn't work" issue, corporate mission statement + kanban, the on-call pager,
  the incident runbook ("Step 3: Blame DNS. Step 4: It was DNS"), and the token
  vault.
- Verified live: the region popup renders in-context (captured `node_modules/` in
  Dependency District). `flavor_test` extended to check region props (10 checks).
  Full suite: **25 suites green**.

### Iteration 35 — Mid-game combat: verified balance, fixed arrival pacing
- A mid-game playtest (Dependency District via map fast-travel) claimed combat was
  "unplayable — die in 1-2s, invisible projectiles, no damage numbers." **Verified
  each claim against evidence and rejected the false ones**: headless repro shows a
  stationary player survives **15s+** (balance is fine, not nerfed); a controlled
  combat preview shows **projectiles render clearly** (cyan blasts + trails) and
  **damage numbers appear** (yellow pop). Discipline held: no enemy nerf on an
  unreliable report.
- The one real, defensible issue: enemies were placed only 200px from the region
  spawn (inside the 340 aggro radius), so fast-travel/respawn dropped the player
  straight into combat. **Enemies now spawn >=420px from spawn** (beyond aggro), so
  you arrive safe and choose to engage — consistent with the Localhost opening.
- Made damage numbers more readable (26px + quick pop-scale) since two reviewers
  had missed them.
- New `region_arrival_test` (8 regions, all min-enemy-dist > aggro) wired into CI.
  Full suite: **25 suites green**.

### Iteration 34 — Environmental interactable comedy props
- Implemented the brief's "ENVIRONMENTAL HUMOR DENSITY": **10 interactable props**
  in Localhost — fridge, coffee machine, deprecated plant, bed, server rack,
  whiteboard, terminal (`npm audit`: 847 vulns / 0 addressed), router (it's always
  DNS), battlestation monitors (−€713/mo AI savings), sticker-covered laptop.
- New **FlavorPopup** UI: screen-space (via HUD), styled dark panel with teal
  border + dimmed backdrop, closes on interact/click/esc (short arm-delay so the
  opening [E] doesn't insta-close it). Subtle prop markers; the floating [E]
  prompt points them out.
- Verified live (video review): player approaches props, styled popups open/close
  cleanly with readable jokes, no flicker/leftovers; scene reads polished.
- Regression test `flavor_test` (6 checks: all 10 ids placed, interaction spawns
  popup with correct title/body) wired into CI. Full suite: **24 suites green**.

### Iteration 33 — Rug redesign + movement investigation
- **Ruled out a reported "player can't move right / dies on input" bug.** A GUI
  capture showed the player stalling near Claude, but a deterministic headless
  sweep proved movement is free (660px) at every Y row across Localhost with no
  collider — the live stall was an xdotool held-key artifact, not a game defect.
  (An earlier headless "freeze" was also a test artifact: `EventManager.cooldown`
  defaults to 0, but the real `start_new_game()` resets it to 60s, so no event
  fires during the opening.)
- **Fixed a real visual defect: the centerpiece rug rendered as a hard
  checkerboard** (looked like a missing texture) in every opening screenshot.
  Redesigned into a proper woven rug — guard/teal/rust border bands, a central
  concentric-diamond medallion, low-contrast diagonal weave, and end fringe.
  Verified in-scene: it now reads as intentional décor anchoring the
  battlestation zone.

### Iteration 32 — P0: opening death-loop (broken respawn + spawn-camp)
A fresh-save GUI playtest exposed a release-blocking first-minutes failure: the
player kept dying and getting stuck. Three real defects, each reproduced and
fixed with regression tests:
- **Respawn was completely broken.** `player._die()` emits `died` AND calls
  `GameManager.handle_player_death()` (emits `player_died`); `world._ready` wired
  BOTH to `_on_player_died`, so death stacked TWO death screens — the Respawn
  button freed only the top one, leaving an identical screen behind. Fixed:
  connect only `player_died`, make `_on_player_died` idempotent, and guard
  `handle_player_death` re-entry.
- **Respawn dropped the player back into the enemy pile.** Now respawns at the
  region's safe spawn point (`GameManager.region_spawn`) with 3s i-frames, and
  sends all enemies home (`reset_to_home`) so it's never an instant re-swarm.
- **Enemies swarmed across the whole room.** Added an aggro radius: enemies stay
  dormant at their home post until the player comes within `aggro_radius` (340px;
  bosses 900px), and de-aggro/leash home past 1.8x. The Localhost opening now
  keeps its 2 bugs on the far-right, away from the spawn/Claude/token path, so a
  new player can explore, collect, and meet Claude before combat.
- Verified live (computer-use + video review): a new player explores the opening
  for 30s at full HP, bugs never chase across the room, respawn lands safely,
  pause works. New tests: `death_respawn_test` (11 checks), `opening_safety_test`
  (no spawn-camp); both wired into CI. Full suite: **23 suites green**.

### Iteration 31 — Live boss verification + physics/particle bug fixes + slam weight
- **Live boss combat verified** (Enterprise Architect, corporate_enterprise) via a
  faithful throwaway 1v1 capture + video review: boss telegraphs RED, lunges/slams
  with knockback, and summons green scope-creep adds; player kites fluidly and
  **never soft-locks**. This closes the last major gameplay element that had only
  unit-test coverage.
- **Fixed real in-game error spam found in the capture logs** (fired on *every*
  enemy death caused by a hit):
  - `take_damage` now defers `_die()` behind a `_dying` guard, so token/add spawns
    and Area2D shape toggles no longer execute while the physics server is flushing
    queries (kills `Can't change this state while flushing queries`).
  - `_hit_spark` parents its burst to the region and self-frees via `finished`,
    eliminating `Lambda capture ... was freed` from a SceneTree-timer lambda that
    captured a particle freed with the enemy.
  - Verified clean: combat scenario logs now show zero physics-flush / freed-lambda
    errors.
- **Boss slam now has weight**: camera shake + reddish dust-ring burst on impact
  (video-confirmed at the slam frames; shake is short and non-nauseating).
- Full suite green: **21 suites / 233 tests**.

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

### Iteration 6 — Combat depth
- **Enemy signature behaviours + telegraphs** in `enemy_base.gd`:
  - **merge_conflict** splits into two smaller conflicts on death (once).
  - **scope_creep** grows and speeds up over time.
  - **memory_leak** slowly bloats.
  - **rate_limiter** telegraphs (flashes), then emits a 429 pulse that shoves
    the player back (temporary, decaying — never a trap).
  - **hallucination** blinks/teleports to stay evasive.
  - Generic **stun** state (frozen but still shoveable).
- **New player abilities**:
  - **Rubber Duck** (`3`): AoE that freezes nearby enemies (you found the bug).
  - **Stack Trace** (`4`): a piercing magenta beam that chains through a whole
    line of enemies.
  - Safe decaying **external knockback** on the player (used by rate_limiter);
    the player can always walk against it, so it can't trap.
- Regression test `tests/combat_test.tscn` (10/10): merge split, scope growth,
  Rubber Duck stun, Stack Trace pierce (and non-pierce consumption), and that a
  rate-limiter pulse never traps the player. Wired into CI.

### Iteration 7 — Technical-debt consequences
- Debt now **matters mechanically** (above a safe threshold of 20; below it debt
  is strategically fine):
  - **Upgrade costs scale with debt** (`DreamAppManager.get_effective_cost`,
    +0.4%/point — 100 debt ⇒ +40%).
  - **Debt drains stability** on a periodic tick (`GameManager.apply_debt_consequences`).
  - **Debt breaks dependencies**: a `debt_incident` spawns a fresh bug near the
    player in the world (`world._on_debt_incident`).
- This ties the comedy rewards (which dump large debt, e.g. +43 from Just One
  Tiny Change) to real strategic stakes.
- Regression test `tests/debt_test.tscn` (6/6): cost scaling, stability drain
  above threshold, no effect below threshold, and dependency-break incidents at
  high debt. Wired into CI.

### Iteration 8 — Ship-Before-Reset cycle system
- New `CycleManager` autoload implements the title mechanic. Development runs in
  timed **cycles**; at each **RESET**:
  - volatile quotas refill (compute, context, focus, a little will to live),
  - a **debt reckoning** drains stability proportional to accumulated debt,
  - the **vendor price index shifts**, which flows into upgrade costs
    (`DreamAppManager.get_effective_cost`).
- A **reset warning** fires as the deadline approaches; the HUD shows a live
  `◉ Cycle N   ⏱ reset in Xs` readout (turns orange during the warning window)
  plus reset/warning toasts. Creates strategic "ship it BEFORE RESET" pressure
  without a single stressful whole-game timer.
- Cycle resets on new game; the timer only ticks while PLAYING and unpaused.
- Regression test `tests/cycle_test.tscn` (12/12). Wired into CI.

### Iteration 10 — Themed regions (all 9 beyond Localhost)
- Replaced the flat single-tile **noise field** builder (`region_builder.gd`)
  with **intentional themed compositions**. Added tintable structure primitives
  to the generator: `tech_floor`, `struct_slab` (monolith/pillar/cubicle),
  `struct_crate` (package), `struct_console` (API kiosk), `struct_tower`
  (server/GPU rig), `struct_orb` (cloud/token), `struct_arch` (ruin/gateway).
- Each region now has a palette (tinted floor + glow), themed set-dressing
  clusters, point lights, and comedic signage. Examples:
  - **Production**: dark-red server room, central monolith "PRODUCTION — DO NOT
    TOUCH", server towers, "Observability: vibes".
  - **Token Vault**: golden hall of glowing token-reserve orbs.
  - **Cloud District**: floating data orbs + towers. **Corporate**: a grid of
    cubicle slabs. **Stack Overflow Ruins**: broken arches. **API Bazaar**:
    console stalls. **GPU Mines**: rig towers. **Dependency District**: piles of
    broken package crates. **Open Source Wildlands**: a lone gateway arch.
- Regression test `tests/region_test.tscn` (59/59): every region builds, returns
  a valid spawn/size, and produces themed structures + gameplay containers.
  Wired into CI.

### Iteration 11 — Model selection
- New `ModelManager` autoload: the player chooses which model powers **Prompt
  Blast**, a real trade-off between token cost, damage, and reliability:
  - **Local 7B** — cheap, weak, unreliable (may hallucinate/misfire).
  - **Fast** — balanced (default).
  - **Frontier** — powerful and reliable, but expensive.
  - **Experimental** — high damage, low reliability (brilliant or catastrophic).
- Wired into combat: Prompt Blast cost scales (`player.prompt_cost()`), damage
  scales, and low-reliability models can hallucinate and fizzle. Cycle with `[T]`;
  HUD shows `⚙ Model: <name> ([T], N tk/blast)` and a change toast.
- Regression test `tests/model_test.tscn` (7/7): defaults, cycling wrap,
  distinct trade-offs, and cost scaling (Local 3 → Frontier 11). Wired into CI.

### Iteration 12 — Deployable agents
- New `AgentManager` autoload: deploy autonomous coding agents that resolve at
  the next cycle **RESET**. Archetypes trade cost vs power vs reliability:
  - **Junior** (15 tk): cheap, chaotic — overengineers and hallucinates often.
  - **Senior** (40 tk): steady.
  - **Frontier** (90 tk): powerful, and occasionally spawns ANOTHER agent.
- On resolve, each agent may **gather tokens**, **overengineer** (technical
  debt), **hallucinate** (wasted work + debt), or **spawn another agent** — real
  strategic comedy tied to the debt system.
- Deployed from the Localhost **agent terminal** (after the cautionary
  "Autonomous Agent" storyline it becomes a repeatable deploy console; the event
  popup now supports repeatable menus and a `deploy_agent` choice). HUD toasts on
  deploy and resolve.
- Regression test `tests/agent_test.tscn` (12/12): deploy cost, unaffordable
  guard, resolution yields tokens, junior traits (hallucinate/overengineer/debt),
  and automatic resolution at cycle reset. Wired into CI.

### Iteration 13 — Dream App architecture tradeoffs
- New `ArchitectureManager` autoload: five binary decisions (Structure
  Monolith/Microservices, Database SQL/NoSQL, Testing now/later, Security
  right/velocity, Hosting Cloud/self-host), each with an **immediate** effect and
  a **delayed consequence** that emerges at later cycle RESETs (microservice
  flakiness, cloud invoices, NoSQL data loss, security breaches).
- "Ridiculous" choices raise the app's **ridiculousness**, surfaced in the ship
  results. Decisions made at the Localhost **Dream App terminal** (a repeatable
  console listing pending decisions); HUD toasts on delayed consequences.
- Regression test `tests/architecture_test.tscn` (11/11): immediate effects,
  ridiculousness, delayed consequences (direct + at cycle reset), and the
  pending-decision menu. Wired into CI.

### Iteration 14 — Claude: reactive personality, memory & callbacks
- Claude (`roommate_ai`) is now **alive**: his dialogue is generated from the
  live game state instead of static JSON. He reacts to technical debt, low will
  to live, low stability, deaths ("works on my machine"), deployed agents, and
  every architecture decision (microservices, tests-later, velocity, cloud), and
  escalates by cycle. He **remembers** how many times you've talked.
- **Backups running gag**: Claude nags about the `TODO: BACKUPS` sticky note and
  offers to set them up (30 tokens → `GameManager` flag). Later, a NoSQL data
  loss or a security breach (architecture delayed consequences) becomes **trivial
  if you have backups**, unlocking **Boring Responsible Adult** — otherwise it's
  a real stability hit. Dialogue choices now support `action` handlers.
- Added generic persistent `GameManager` story flags for callbacks.
- Regression test `tests/dialogue_test.tscn` (9/9): intro + memory, reactive
  barbs (microservices, debt), the backups offer/flag/cost, grudging pride when
  backed up, and the breach-survival achievement payoff. Wired into CI.

### Iteration 15 — Production incident + IT WAS DNS
- Entering **Production** triggers a branching incident (once): Investigate,
  Restart, **Blame DNS**, Ask the AI, or Roll back everything — each with its own
  outcome. Added `dns_gamble` support to the scripted-event engine
  (`next_success`/`next_fail`).
- **Blame DNS** is almost always a joke ("It's never DNS")... except ~12% of the
  time it really **is** DNS, restoring stability and unlocking **IT WAS DNS**.
- Regression test `tests/production_test.tscn` (5/5): investigate restores
  stability, the incident resolves, and blaming DNS eventually unlocks the
  achievement. Wired into CI.

### Iteration 16 — Audio safety hardening
- Added a **hard limiter** on the Master bus (ceiling −3 dB) so nothing can ever
  blast the player regardless of stacked SFX or future streams. Audio remains
  silent-by-default with conservative volumes and enveloped tones.
- Regression test `tests/audio_test.tscn` (13/13): music off by default, won't
  play until enabled, conservative volumes, limiter present, and no generated
  sample approaches full-scale (peak deviation 20/127).

### Iteration 17 — Boss visuals + behaviour
- The "boss" enemies were only high-HP normals (`is_boss` was never set). Now the
  region builder marks bosses (merge_conflict, cloud_bill, enterprise_architect,
  legacy_monolith, infinite_context), so boss scaling actually applies (2× size,
  4× HP, 2× damage, 5× drops).
- Distinct boss art: **Enterprise Architect** (suit + power tie inside a
  governance-square aura), **Legacy Monolith** (cracked brick with glowing COBOL
  runes + moss), **Infinite Context** (nested rings around an unblinking eye).
- **Telegraphed boss slam**: bosses flash a wind-up, then unleash an AoE
  shockwave that knocks the player back (temporary — never a trap) and chips
  damage. The **Enterprise Architect convenes a governance council** (summons
  scope-creep adds).
- Regression test `tests/boss_test.tscn` (6/6): boss scaling, slam knockback,
  and architect-only summoning. Wired into CI.

### Iteration 18 — Player character art
- Rewrote the procedural vibe-coder spritesheet: **3-tone hoodie shading**, hair,
  a face with eyes, **headphones** with neon accents, white sneakers, and a
  proper walk cycle (leg stride + arm swing + head bob).
- Added a **silhouette outline** pass — the single biggest readability upgrade
  for small pixel characters — so the player pops against any background.
- Verified in-game at scale (2.2×): clear, distinct, polished character replacing
  the previous dark blob.

### Iteration 19 — NPC sprites
- NPCs were **textureless** (invisible bodies with only a label). Parametrized
  the character drawer with a palette and generated distinct NPC sprites:
  **Claude** (teal hoodie + headphones), **suit** (corporate: navy + red tie),
  **maintainer** (grey, greying hair), **foreman** (hi-vis orange).
- `npc.gd` assigns a sprite per archetype (roommate/cloud/svp/reseller/foreman/…)
  plus a soft shadow, matching the player's scale. Claude now renders as a clear,
  distinct character in-game.

### Iteration 20 — Branching Debugging Investigation quest
- A genuinely branching quest (Localhost "/checkout is DOWN" console): read logs
  / blame the intern / restart, then trace it yourself **or ask the AI**, then
  choose a **proper fix** (stability + reward + I-CAN-EXPLAIN achievement) or a
  **quick hotfix** (technical debt) — plus a weak restart ending and a
  **hallucination failure path**.
- The **AI-diagnosis branch reliability depends on the selected model** (new
  `ai_gamble`): Frontier diagnoses reliably; a cheap Local model often
  hallucinates a confident wrong answer and sends you down the failure path —
  making model selection matter inside a quest.
- Regression test `tests/debug_quest_test.tscn` (9/9): both fix endings, the
  achievement, and model-dependent AI routing (frontier reliable, local
  hallucinates). Wired into CI.

### Iteration 21 — Personalized ship-results roast
- The victory screen now assembles a **personalized roast** from the choices you
  actually made (`GameManager.get_ship_roast`): technical debt tier, each
  architecture decision (microservices/NoSQL/tests-later/velocity/cloud),
  backups (grudging respect vs cliff-edge), death count, whether it was ever
  really DNS, and architecture ridiculousness. Ridiculousness is also shown in
  the results stats.
- Regression test `tests/results_test.tscn` (11/11) verifies the roast reflects
  the run's state (and flips when you have backups). Wired into CI.

### Iteration 22 — P0 intro soft-lock (found by interactive playtest)
- An interactive computer-use playtest revealed a **game-breaking soft-lock**:
  if the boot-sequence "press any key" prompt's finishing input was missed, the
  intro never emitted `sequence_finished`, so `world` never set `can_move = true`.
  Result: abilities/model-cycle worked (they don't gate on `can_move`) but
  **movement, dash, and interact were dead** — the game was unplayable.
- Fix: the opening sequence now **auto-finishes** with hard caps (whole intro
  ≤ 16s; auto-continue ≤ 6s after the prompt shows) so control is ALWAYS handed
  back, plus a `world` **18s safety net** that force-restores control. Verified
  end-to-end: with zero advance input the player regains control and moves.
- Regression test `tests/opening_test.tscn` (2/2): the intro auto-finishes and
  frees itself with no input. Wired into CI.
- Lesson: scripted screenshot captures used movement keys that incidentally
  finished the intro, hiding the bug — interactive playtesting caught it.

### Iteration 23 — Interaction range + prompt (playtest finding)
- Re-playtest confirmed the intro fix (movement works). It flagged **interaction
  range as too tight** — pressing E near NPCs/consoles required pixel-perfect
  positioning, which was frustrating.
- Widened the player's interact area (56 → 82) and added a floating **"[E] <what>"
  prompt** above the nearest interactable so players always know when and what
  they can interact with. Verified: Claude dialogue now triggers from a
  comfortable distance.

### Iteration 24 — P0 progression dead-end
- Investigation (prompted by playtesting) found a **game-ending progression
  blocker**: no quest ever unlocked `dependency_district`, and Localhost's exit
  portal only spawns when it's unlocked — so the player was **stranded in
  Localhost forever** after the opening quests.
- Fix: `dependency_district` is unlocked from the start (later regions still gate
  behind quest rewards), added an EXIT signpost, and made portals more forgiving
  (larger trigger + `[E] Enter <region>` prompt).
- Regression test `tests/progression_test.tscn` (4/4): first region unlocked, the
  exit portal spawns, travel works, and quest rewards keep unlocking later
  regions. Wired into CI.

### Iteration 25 — Completability guard (game is winnable)
- Audited the win path: a sensible upgrade loadout costs ~485 tokens, far below
  what quest rewards alone provide, and the `deploy_button` triggers victory when
  `can_ship`. So the game is completable end-to-end (given the progression fix).
- Regression test `tests/win_test.tscn` (9/9): buying two tiers across the core
  branches meets every ship requirement (features 18, stability 18, ai/infra
  tiers), `can_ship` is true, deploying reaches VICTORY with results + the Ship
  It achievement. Guards against an unwinnable game. Wired into CI.

### Iteration 26 — P0 off-screen overlays + Dream App cost display
- Interactive playtest flagged "pause (Esc) does nothing." Instrumentation showed
  Esc reached the handler and `_open_pause()` ran — but the pause menu (a Control)
  was added as a child of the **world Node2D**, so it rendered in **world space at
  (0,0)** and was off-screen wherever the camera was. The **death and victory
  screens had the same bug** — so you couldn't see that you died or won.
- Fix: route all full-screen overlays (pause, death, victory) through the **HUD
  CanvasLayer** (`world.show_overlay`). Pause also moved to `_input` (Esc doubles
  as `ui_cancel`, which focused Controls can swallow before `_unhandled_input`);
  the pause menu owns Esc-to-resume. Verified the pause menu renders centered.
- **Dream App panel** now shows the **effective** cost (debt + vendor price index)
  that's actually charged, nicely formatted (e.g. `Buy · 50 tk, 5 API`), and the
  ship status shows the AI/Infra tier requirements.
- Regression test `tests/ui_overlay_test.tscn` (4/4): pause + show_overlay land
  under a CanvasLayer, not the world Node2D. Wired into CI.

### Iteration 27 — Victory/death screen verification + polish
- Confirmed the overlay fix by rendering both climax screens: the **victory
  screen now displays** on-screen with the **personalized roast** ("47
  microservices. For this. Chef's kiss.", "Your cloud bill has achieved sentience
  and unionized", "it really was DNS", "Architecture Ridiculousness: MAXIMUM") —
  exactly the brief's "get roasted by the results screen." The death screen also
  renders.
- Polished both panels: neon-teal (victory) / red (death) bordered panels,
  colored titles, readable stats, styled buttons — a finished payoff.

### Iteration 28 — Combat juice
- Added combat feedback ("juice") so hits read clearly: **floating yellow damage
  numbers** over enemies, **hit-spark particle bursts** at impact, and brighter/
  bigger **projectiles with a glow halo + fading trail** (cyan Prompt Blast,
  magenta Stack Trace beam). Enemies already flash white on hit.
- Verified via video review: projectiles, trails, the magenta beam, damage
  numbers, sparks, enemy flash/death all render; combat now has clear feedback.
  (Also confirmed the death screen renders live.) Combat tests still 10/10.

### Iteration 29 — Fast-travel + live multi-region verification
- The World Map (M) is now **fast-travel**: unlocked, non-current regions are
  clickable "→ travel" buttons (locked ones shown greyed). Traversing 10 regions
  on foot was tedious and blocked mid-game playtesting.
- Verified in-game: fast-traveled to **Dependency District**, which renders its
  full theme live — node_modules crate piles, a server tower, pink spider-knot
  dependency-demon enemies, a null-reference orb, the Package Maintainer NPC, and
  a return portal — no errors. Confirms multi-region gameplay works end-to-end.
- Per-region HUD subtitles (was "Region under construction" for all non-Localhost).
- Regression test `tests/map_travel_test.tscn` (4/4): travel buttons for unlocked
  regions, travel changes region + closes the map, locked travel refused.

### Iteration 30 — Input robustness
- A computer-use playtest reported "pause/fast-travel don't work," but direct
  `xdotool` captures prove both DO work (pause menu renders on Esc; clicking a map
  button traveled to Dependency District live). The subagent's desktop appears to
  intercept Escape and mis-target clicks — an environment quirk, not a game bug.
- Regardless, added robustness that helps real players: a **visible HUD pause
  button** (top-right, not everyone knows Esc) and **ASCII travel labels** on the
  map ("Travel to <region>", no reliance on unicode arrows). Core Esc/click paths
  unchanged and verified working.

## Verified test commands

```bash
godot --headless --path . --script scripts/tools/run_generate.gd
godot --headless --path . --import
godot --headless --path . --scene tests/smoke_test.tscn        # 8/8
godot --headless --path . --scene tests/soft_lock_test.tscn    # 4/4
godot --headless --path . --scene tests/story_test.tscn        # 19/19
godot --headless --path . --scene tests/combat_test.tscn       # 10/10
godot --headless --path . --scene tests/debt_test.tscn         # 6/6
godot --headless --path . --scene tests/cycle_test.tscn        # 12/12
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
