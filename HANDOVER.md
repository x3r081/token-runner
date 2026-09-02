# HANDOVER — Token Runner

Onboarding for the next agent. Read this before touching anything; it front-loads
the traps that cost real time to discover.

---

## 1. What this is

**Token Runner: Ship Before Reset** — a Godot 4.7 / GDScript 2D top-down comedy
RPG. You play a sleep-deprived vibe coder trying to ship a "Dream App" before
your AI token quota resets. Satire of AI-assisted dev culture: you fight Scope
Creep and Dependency Demons, accumulate technical debt, and get roasted by the
results screen when you deploy.

Hackathon project. Complete and playable, not a prototype.

| | |
|---|---|
| Engine | Godot **4.7.2** (`/opt/homebrew/bin/godot` on this machine) |
| Language | GDScript, typed, **tabs** for indent |
| Size | ~40k lines GDScript, 16 shaders, 10 regions, 31 quests, 76 events, 99 achievements, 9-branch upgrade tree |
| Tests | 28 headless suites, ~297 assertions |
| Repo | `github.com/x3r081/token-runner` |
| Branch | `cursor/game-quality-overhaul-2ae1` (**~99 commits ahead of `main`**, clean fast-forward, unmerged) |

### Two checkouts exist — do not confuse them

- `/Volumes/Lexar/Project/OpenSverige Hackaton` — the **parent** dir, same repo, sitting on `main` (old code). **Never edit this.**
- `/Volumes/Lexar/Project/OpenSverige Hackaton/token-runner` — the working checkout on the overhaul branch. **All work happens here.**

---

## 2. Run it

```bash
cd "/Volumes/Lexar/Project/OpenSverige Hackaton/token-runner"
godot --headless --path . --script scripts/tools/run_generate.gd   # generate art/audio
godot --headless --path . --import                                 # import assets
godot --path .                                                     # play
```

All art and audio are **procedurally generated at build time** — there are no
committed source images beyond a Kenney set in `assets/external/`. That is why
`run_generate.gd` must run before `--import`.

### Tests

```bash
for t in tests/*.tscn; do echo "== $t"; godot --headless --path . --scene "$t" 2>&1 | tail -3; done
```

Each suite prints `N passed, M failed`. **Do not grep for the word `failed`** —
it matches `0 failed` and reports every passing suite as a failure. Match on the
count instead.

### Screenshots (the review loop that actually catches things)

```bash
godot --path . tools/quality_capture.tscn      # -> docs/screenshots/qa/
```

Captures the menu, all 10 regions, and UI surfaces. **Must run windowed** —
headless has no renderer and produces blank images. Then `Read` the PNGs and
critique them. Several defects in this project were invisible in code and
obvious in a frame.

---

## 3. Architecture

- **15 autoload singletons** (`GameManager`, `ResourceManager`, `QuestManager`, `DreamAppManager`, `CycleManager`, `ArchitectureManager`, `EventManager`, …) — signal-driven, no direct coupling between managers and scene objects.
- **Content is data**: `data/*.json` holds quests, dialogue, events, upgrades, achievements. Adding content needs no code.
- **Regions are built at runtime** by `scripts/world/region_builder.gd` (+ `localhost_builder.gd` for the apartment) — not authored as scenes.
- Entry point: `scenes/main/main_menu.tscn`.
- **Pixel-perfect pipeline (since `823a408`)**: the world renders into a fixed
  **640×360 SubViewport** (`world.tscn` › `PixelStage` › `Viewport`) at camera
  zoom 0.5, so 32px art at scale 2.0 is exactly one stage pixel and a 20-tile
  region is exactly one screen wide. `scripts/world/pixel_stage.gd` blits it at
  `K = floor(min(w/640, h/360))`, centred and letterboxed (K=2 windowed on this
  Mac, K=3 on a 1080p monitor). `window/stretch/mode` is **disabled** on
  purpose — any stretch would multiply the stage by a fraction and re-break the
  grid. HUD, dialogue and modals are positioned **inside the world rect**, not
  the window. `tools/quality_capture.gd` proves the grid on every capture by
  asserting all pixel runs through the player sprite are multiples of K.

### Docs worth reading, in order

| File | Why |
|---|---|
| `docs/VISUAL_BIBLE.md` | **Authoritative art direction.** Palette, per-region colours, the 15-shader API, HDR bloom recipes, pixel-art quality bar, lighting/particle budgets, UI tokens. Read before any visual work. |
| `docs/COMEDY_BIBLE.md` | Tone rules, NPC voices, recurring gags. Read before writing any player-facing text. |
| `docs/AUDIO_BIBLE.md` | Audio contract: identity, mixing law, loop-exactness, generator/runtime split. Audio is ON by default. Read before any sound work. |
| `docs/ARCHITECTURE.md` | System map. |
| `docs/QUALITY_BACKLOG.md` | P0–P3 defect list from 55 prior iterations. |
| `docs/AUTONOMOUS_STATUS.md` | 50KB iteration log. Skim the tail for recent history. |

---

## 4. Godot 4.7 gotchas that have already bitten this project

Each of these cost a debugging cycle. They will bite you too.

1. **Untyped array literals break type inference.** `for k in [1.0, -1.0]:` makes
   `k` a Variant, and any `var x := k * 2.0` fails to parse. Write
   `for k: float in [1.0, -1.0]:`. This broke asset generation once.

2. **You cannot tween a shader uniform that was never set.** A uniform with a
   default in the `.gdshader` does not exist on the material until you call
   `set_shader_parameter()`. Tweening `"shader_parameter/foo"` first throws
   *"property does not exist"*. Always seed it.

3. **Signal arity is silently fatal.** Connecting a 1-arg handler to a 2-arg
   signal logs an error at emit time and **skips the callable**. The handler
   simply never runs. This hid a stale-NPC bug for a long time — `npc.gd`
   connected `_on_quest_changed(qid)` to `quest_completed(quest_id, rewards)`,
   so NPC quest markers never refreshed on completion.

4. **`process_mode` inheritance + pause = frozen tweens.** Popups call
   `get_tree().paused = true`. Anything mid-tween freezes. `PostFXLayer` had a
   black fade curtain tween that froze at full opacity — a **black screen**.
   Anything that must survive pause needs `PROCESS_MODE_ALWAYS`.

5. **A passing test suite does NOT prove a script compiles.** Godot only parses
   a script when something loads it. A brand-new file no scene references can be
   broken while all 28 suites pass. Force-load every script with
   `CACHE_MODE_IGNORE` — **from inside a real scene**, not `--script`
   (SceneTree script mode doesn't register autoloads, so you get false
   *"Identifier not found: GameManager"* errors).

6. **Shader compile errors do not fail tests.** Grep the run output for them
   explicitly.

6b. **Corollary, learned the hard way:** a parse error in a *world-building*
   script does not fail tests either. Adding a reference to a non-existent
   property (`size` on a `Node2D`) broke `world_label.gd`, so every
   `WorldLabel.add()` call became a no-op and **every caption in the game
   silently disappeared** — while `region_test` still passed 59/59, because
   nothing asserts labels. Symptoms of a dead class are `Invalid call.
   Nonexistent function 'x' in base 'GDScript'` at the call sites, far from the
   real error. After editing any script, parse-check it and **look at the
   frame**.

7. **`change_scene_to_file()` frees the calling node** if that node *is*
   `current_scene`. A capture/tool script doing this kills its own coroutine
   mid-run. Fix: `get_tree().current_scene = null` first.

8. **Only one Godot process can hold the import lock.** Never run generation,
   import, tests and the game concurrently. Serialize them.

9. **`timeout` is not installed** on this macOS box. Use background tasks with
   an `until` poll loop instead.

10. **Only `run_generate.gd` generates art.** A legacy `generate_assets.gd`
    EditorScript used to write much older art into the same output dir and would
    silently clobber the pipeline; it was deleted in `97f44ff`. If it ever comes
    back, it is a landmine, not a tool.

11. **`hdr_2d=true` means the framebuffer is LINEAR — a screenshot must be
    converted to sRGB or it is ~2 stops too dark.** For several rounds every
    QA frame was captured without that conversion, and visual judgements
    (including "the world is too dark, raise the ambient") were made against a
    measurement error. `tools/quality_capture.gd` converts now. If you write a
    new capture tool, copy its method.

12. **A palette table's "BASE" is not the floor.** Writing `#0A120C` as a
    region's base colour led the tile generator to build floors *to* that
    value — nine rooms of black void at 32–41/255 luminance. Floors are a
    separate mid-value MATERIAL with visible structure; VISUAL_BIBLE_V2 LAW 6
    now carries explicit luminance windows (base 64–84) and a per-region
    material column. When you spec colours, say what each one is *for*.

13. **Aliased vector text below ~16px is illegible** with hinting off
    ("compiled on hope" rendered as "complled"). Aliased + `HINTING_NORMAL`
    at ≥16px reads as crisp pixel text; below that, keep antialiasing.

14. **This Mac cannot open a 1080-tall window** (3840×1080 ultrawide, menu
    bar), so the game opened at 1649×928 and, under `canvas_items` stretch,
    rendered everything at 0.859× — 2.75 screen px per art pixel. The pixel
    grid was broken *in play* for the entire project until the SubViewport
    pipeline. Two of the four biggest visual defects found in this effort were
    measurement/pipeline errors, not art errors. Measure before you judge.

---

## 5. State as of this handover

Committed on the branch, newest first:

- `2c07dd6` — **restraint pass 5**: stale boss HUD across regions fixed at the
  source (world.gd purged adopted layers before the tree's delete queue
  flushed); boss card gated on real engagement; waypoint no longer freezes
  under a pausing event; floors re-lit via REGION_AMBIENT (64–78 measured);
  bazaar floor rebuilt; modals opaque with the stage dimmed behind them.
  Cold critic: 5.2.
- `823a408` — **restraint pass 4**: the pixel-perfect pipeline above; boss
  card gating; placeholder quads, bunting and off-grid cables removed.
- `c56d07a` — **restraint pass 3**: readable floors — one material per region
  (ten regions had been served by four aliased textures) with a generate-time
  luminance gate.
- `a105448` — **restraint pass 2**: the stamped "lit tile" cross, portals in the
  room's own accent, unified enemy language, legible font.
- `3ce576a` — **restraint round**: `docs/VISUAL_BIBLE_V2.md` ("Restraint", ten
  laws), −11k lines of noise. Triggered by the user calling the game "AI slop".
  Scored by a **cold Fable critic** reading frames only: 3.6 → 4.75 → 4.9 → 5.0 → 5.2.

- `111f1a5` — **round 5**: deep graphics + gameplay pass (47 agents across 3
  workflows). Per-type enemy behaviours with telegraphs, multi-phase bosses,
  encounter staging (guard posts, ambush pockets, boss arenas) replacing random
  scatter, player feel (weight, recoil, perfect-dodge, low-HP state), ~950 lines
  of new content. Irregular kerbed region zones, depth planes, per-region filmic
  grade, boss art with real silhouettes.
- `ee77691` — **round 4**: full graphics + **sound** overhaul. Audio went from
  mute-by-default sine beeps to a generated musical score (menu leitmotif,
  explore/combat/boss/victory, region ambience beds) plus 30 layered SFX and a
  rebuilt AudioManager with crossfades, dialogue ducking and pitch jitter.
  `docs/AUDIO_BIBLE.md` is the contract. Menu hero scene, region composition and
  silhouette passes.
- `de60bdb` — dialogue choices overflowed off-screen; panel now grows upward
  from its anchored bottom edge, ability bar hides during conversation, and
  gameplay keys are gated while dialogue is active.
- `97f44ff` — closed the four carried findings (quest kill counts vs spawns,
  `_meets()` failing open, dialogue choices dropping `achievement`, the legacy
  art generator).
- `af6fd1a` — **round 3**: world typography system, portal vortexes, per-region
  atmosphere, focal set-pieces, combat spectacle, comedy-as-gameplay. Fixed four
  bugs no test could see, including NPCs going permanently silent after one
  conversation (`.clear()` on references into the parsed JSON was destroying the
  dialogue database) and the shop selling on credit.
- `054d8b6` — **round 2**: player guidance system, comedy expansion.
- `a3388d9` — **round 1**: art-direction contract + shader library, full
  lighting/atmosphere/art/UI/VFX overhaul.

**Verified state:** working tree clean, in sync with `origin` at `111f1a5`, all
28 suites green, JSON valid, clean boot. (`--quit-after` prints one benign
"1 resources still in use at exit" line — a shutdown-order warning, not a fault.)

### The guidance system (the player's biggest past complaint)

The user could not tell what to do and wandered. Quests said *what*, nothing said
*where*. Three pieces now answer it, and **must not regress**:

- `scripts/ui/objective_waypoint.gd` — on-screen chevron beaconing over the target, screen-edge pinned with distance/bearing when off-screen. Resolves objectives to live world nodes via groups + properties.
- `scripts/ui/guide_overlay.gd` — the **[H]** key: current objective *and where*, the 4-step loop, live ship-requirement progress, state-aware nudge.
- `QuestManager.get_current_objective()` — additive objective-routing layer.

**Design rule for all future work:** after any 5-second glance, the player must
be able to name their next physical action. Comedy rides *alongside* the
information and never replaces it — never make a label ambiguous for a joke.

---

## 6. How this project has been worked, and why

Rounds run as **parallel multi-agent workflows** with strict *disjoint file
ownership* — each agent writes only its own files and reports cross-file needs
instead of editing. That is what makes 8 agents in parallel safe.

The pattern that has repeatedly paid off:

1. **Write the contract first.** `VISUAL_BIBLE.md` exists so parallel agents
   produce one coherent look instead of eight competing ones.
2. **Feed agents real screenshots as evidence**, not descriptions.
3. **Then validate — and distrust green.** Both prior rounds were green on the
   first validation pass, and both still had silent integration bugs that no test
   could see:
   - Claude's entire guidance dialogue tree was **unreachable** (a code path
     replaced the JSON greeting that was the only door into his topics).
   - The waypoint pointed at the region where a quest was *given* rather than
     where its boss actually *spawns*.
   - A cause-of-death string was received and dropped.
   - Static comedy no-repeat pools outlived a run, so a new game inherited
     exhausted pools.

   The bug classes to hunt: **authored-but-unreachable content**, **valid-but-wrong
   values**, **data received and dropped**, **static state surviving a reset**.

---

## 7. Known open items

No carried findings are outstanding. Round 5's own frame critique closed 31
defects, including a root cause worth remembering: the Dream App console was
rendering at ~30% alpha because **two tweens were fighting over `modulate:a`** —
the style values were fine, so reading the stylebox would never have found it.

Three things to know rather than fix:

- **`tests/region_winnable_test.gd` asserts the first combat region has <= 4
  enemies.** Not arbitrary — it codifies a playtest that rejected a difficulty
  spike there. If a quest needs more kills, change the quest, not the spawn
  table. (I tried it the other way; the guard caught me.)
- **`--quit-after` prints `1 resources still in use at exit`.** Benign
  shutdown-ordering warning, not a fault. Do not chase it.
- `main` still has none of this work; the branch fast-forwards cleanly.

### The technique that finds the most real bugs — and now judges taste

An **independent critic reading every QA frame cold** — no knowledge of what was
intended — has out-performed every other check on this project. It is how the
30%-alpha console, the invisible nameplates, the faded world map and the enemies
drawing behind props were all caught, none of which any suite could see. Capture
the frames, then have someone (or some agent) look at them with fresh eyes.

The same cold critic, given `VISUAL_BIBLE_V2.md`'s "Definition of done" as a
rubric and told nothing about what was attempted, is how the "AI slop" work is
being scored (3.6 → 4.75 → …). It is the only reviewer that cannot be talked
into approving its own intentions. Use Fable for that seat; Opus for the build.

## 8. Ground rules

- Work only in the `token-runner/` checkout.
- Never rename or remove existing node names, groups, scene paths, texture
  filenames, or public function signatures — tests and scene paths depend on
  them. Additive or in-place edits only.
- Content JSON is indexed **by id** by both tests and runtime resolvers. Rewrite
  prose freely; never rename ids or change objective types/targets/counts.
- Run the full suite before committing. All 28 must pass with no `SCRIPT ERROR`
  or `Parse Error` lines.
- Verify visual work by **capturing and looking at frames**. Do not claim a
  visual result you have not seen.
