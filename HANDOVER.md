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
| Size | ~28k lines GDScript, 15 shaders, 10 regions, 15 quests, 9-branch upgrade tree |
| Tests | 28 headless suites, ~297 assertions |
| Repo | `github.com/x3r081/token-runner` |
| Branch | `cursor/game-quality-overhaul-2ae1` (**92+ commits ahead of `main`**, clean fast-forward, unmerged) |

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

### Docs worth reading, in order

| File | Why |
|---|---|
| `docs/VISUAL_BIBLE.md` | **Authoritative art direction.** Palette, per-region colours, the 15-shader API, HDR bloom recipes, pixel-art quality bar, lighting/particle budgets, UI tokens. Read before any visual work. |
| `docs/COMEDY_BIBLE.md` | Tone rules, NPC voices, recurring gags. Read before writing any player-facing text. |
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

---

## 5. State as of this handover

Committed on the branch:

- `a3388d9` — **round 1**: art-direction contract + 10-shader library, full lighting/atmosphere/art/UI/VFX overhaul.
- `054d8b6` — **round 2**: player guidance system, comedy expansion, second graphics iteration.
- `af6fd1a` — **round 3**: world typography system, portal vortexes, per-region
  atmosphere/weather, focal set-pieces, combat spectacle, comedy-as-gameplay.
  Also fixed four bugs no test could see — NPCs going permanently silent after
  one conversation (`.clear()` on references into the parsed JSON was destroying
  the dialogue database), the shop selling on credit, `Continue` re-arming every
  completed storyline, and guidance pointing at where a quest was *given* rather
  than where it can be *completed*.

- round 4 — full graphics+sound overhaul: generated musical score + 30 layered
  SFX + rebuilt AudioManager (docs/AUDIO_BIBLE.md is the contract, audio now ON
  by default), menu hero scene, region composition/readability pass, silhouette
  polish, post-FX grade. See AUTONOMOUS_STATUS.md tail.

Working tree clean, all 28 suites green. Branch is **3 commits ahead of its own
origin** (unpushed) and ~95 ahead of `main`.

### The guidance system (the player's biggest past complaint)

The user could not tell what to do and wandered. Quests said *what*, nothing said
*where*. Three pieces now answer it, and **must not regress**:

- `scripts/ui/objective_waypoint.gd` — on-screen chevron beaconing over the target, screen-edge pinned with distance/bearing when off-screen. Resolves objectives to live world nodes via groups + properties.
- `scripts/ui/guide_overlay.gd` — the **[H]** key: current objective *and where*, the 4-step loop, live ship-requirement progress, state-aware nudge.
- `QuestManager.get_current_objective()` — additive objective-routing layer.

**Design rule for all future work:** after any 5-second glance, the player must
be able to name their next physical action. Comedy rides *alongside* the
information and never replaces it — never make a label ambiguous for a joke.

### ⚠️ In flight right now

A **round-3 workflow was still running** when this file was written: ~124
uncommitted modified files across world text/composition, HUD layout, portals and
atmosphere shaders, character and environment art, combat spectacle, and
comedy-as-gameplay. **Check `git status` before assuming the tree is clean.** If
that round finished, validate and commit it before starting new work.

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

All findings carried in earlier rounds were closed in `97f44ff` (quest kill
counts vs spawns, `_meets()` failing open, dialogue choices dropping
`achievement`, the legacy generator). Nothing known is outstanding.

Two things to be aware of rather than fix:

- **`tests/region_winnable_test.gd` asserts the first combat region has <= 4
  enemies.** That is not an arbitrary number — it codifies a playtest that
  rejected a difficulty spike there. If you need more enemies for a quest,
  change the quest, not the spawn table. (I tried it the other way; the guard
  caught me.)
- `main` still has none of this work; the branch fast-forwards cleanly.

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
