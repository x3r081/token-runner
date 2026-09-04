# 3D BIBLE — Token Runner 3D (authoritative conversion contract)

The 2D game becomes a 3D game. This file is the contract that lets ten agents
build it in parallel without producing ten different games. Read it fully.

## 1. Vision

Same game, new dimension. "Neon Afterhours" at 3AM, now with depth: a 3/4
top-down camera over low-poly Kenney worlds, neon emissive signage blooming
through volumetric haze, moonlight shadows, rigged chibi characters. It must
read as ONE coherent art direction across all 10 regions — Kenney's flat
colormap style is that coherence; lighting and post-processing sell the mood.

## 2. Non-negotiables

1. **The gameplay brain is untouched.** All 15 autoloads, data/*.json, quests,
   dialogue, economy, cycle, events, achievements, saves, HUD, dialogue UI,
   modals, boss HUD, death/victory screens, menus, audio — reused as-is.
2. **Managers speak MAP PIXELS.** The 2D coordinate system (64 px per tile,
   regions 20x15 tiles = 1280x960 px, apartment 25x16 = 1600x1024 px) stays the
   lingua franca for GameManager.region_spawn / player_position, saves, UI,
   tests and every authored table. The 3D layer converts at its edge only.
3. **Coordinate law:** `world3d = Vector3(px.x / 64.0, height, px.y / 64.0)`;
   map +y (screen down) = world +z. Use `Map3D.to3d()` / `Map3D.to_map()`.
   Kenney kits are authored at 1 unit = 1 tile, so the authored layout maps 1:1.
4. **Authored layout is reused, not re-authored.** RegionBuilder (2D) exposes
   static tables: `RegionBuilder._region_enemies(id)`, `_region_npcs(id)`,
   `_region_portals(id)`, `_region_enemy_posts(id)`, `_region_boss_arena(id)`,
   `_region_cover(id)`, `_region_theme(id)` (has "focal"), `REGION_FLAVOR`
   (prop id, px pos, label), `REGION_SIZE`, `TILE_SIZE`; localhost geometry is
   in LocalhostBuilder (spawn (600,640), Claude (820,560), interactables,
   PORTAL_POS). Call these; never retype positions.
5. **2D stays in the repo** (28 suites depend on it). All 3D work lives in
   `scripts/world3d/`, `scenes/world3d/`, `assets/shaders3d/`. The game boots
   into 3D via `GameManager.WORLD_SCENE` (exists()-guarded fallback to 2D).
6. **Shadow proxies keep the UI alive.** UI code (objective_waypoint.gd,
   guide_overlay.gd) is typed to Node2D and reads actors by group. Every 3D
   actor attaches an `ActorProxy` (Node2D) in the SAME groups with mirrored
   fields (see §5). The player's proxy is in group `player_proxy` (NOT `player`).
7. No renames of existing node names, groups, signatures, JSON ids. Additive.

## 3. Scene: `scenes/world3d/world3d.tscn` (root script `scripts/world3d/world3d.gd`)

```
World3D            Node3D, groups ["world"]
├─ WorldEnvironment  (see §7 recipe)
├─ Moon              DirectionalLight3D (cool, low, soft shadows)
├─ RegionRoot        Node3D  — RegionBuilder3D.build(root, id) / LocalhostBuilder3D.build(root)
├─ Player            instance scenes/world3d/player3d.tscn (group "player")
├─ CameraRig         Node3D + Camera3D child, script camera_rig3d.gd, group "camera_fx"
├─ Stage3D           Node, script stage3d.gd, group "stage3d"
├─ Proxies           Node2D, group "proxy_root" (hidden; ActorProxy parent)
├─ HUD               instance scenes/ui/hud.tscn
├─ DialogueUI        instance scenes/ui/dialogue_ui.tscn
└─ EventPopup        instance scenes/ui/event_popup.tscn
```
`world3d.gd` mirrors world.gd's public behaviour exactly: `_ready` state flow
(PLAYING, opening sequence gating with `player.can_move`, `grant_spawn_grace`,
18s safety timer), `_load_region(id)` (free old RegionRoot child, build, set
`GameManager.region_spawn` in px, move player, camera settle, `QuestManager.
on_region_entered`, production/all-hands story triggers exactly as world.gd),
`_on_region_changed` / `on_region_changed(id)`, `_on_player_died` (death
screen into HUD), `_on_debt_incident`, `show_overlay(node)` (adds to HUD),
`_input` pause → pause_menu into HUD, `_unhandled_input` for quest_log /
dream_app / map → `_toggle_quest_log/_toggle_dream_app/_toggle_map` (KEEP these
method names; the capture tool calls them), `_toggle_modal_panel` with
UIManager push/pop. Music: same enable/play calls as world.gd.

## 4. Actor contracts (exact — HUD, death screen, managers, tests read these)

**Player3D** (`scripts/world3d/player3d.gd`, CharacterBody3D, group "player"):
signals `health_changed(current: int, max_hp: int)`, `died`; consts
`MAX_HP := 100`, `SPEED`; vars `hp: int`, `facing: Vector2` (map-space unit
dir), `can_move: bool`, `is_invincible: bool`, `_dash_cd/_duck_cd/_trace_cd/
_ctrlz_cd: float`; child Timer named `AbilityCooldown` exposed as
`ability_cooldown`; funcs `take_damage(amount: int, _source: String = "")`,
`heal(amount: int)`, `respawn(pos: Vector2)` (map px), `grant_spawn_grace(
seconds: float = 2.5)`, `prompt_cost() -> int`, `ability_ready(id: String) ->
bool`, `apply_external_knockback(impulse: Vector2)` (map px/s). Death flow is
EXACT: trauma → `died.emit()` → `GameManager.handle_player_death()`. Input
actions: move_*, interact, ability_1..5, dash, cycle_model (same semantics and
costs as player.gd — read it). Footsteps: call `AudioManager.play_footstep()`
on a stride cadence (the manager's own poll only understands CharacterBody2D).
SFX names identical to player.gd. Interaction: Area3D on mask "interactables",
nearest node in group "interactable" with `interact(player)`/`get_prompt()`;
a billboard Label3D prompt "[E] <prompt>" above the target.

**Enemy3D** (`enemy3d.gd`, CharacterBody3D, group "enemy"): exports
`enemy_type, max_hp, damage, speed, token_drop, is_boss, generation`; vars
`hp, target, _aggroed, _elite`; funcs `take_damage(amount: int, is_crit: bool
= false, from_dir: Vector2 = Vector2.ZERO)`, `stun(duration)`, `reset_to_home()`,
`apply_knockback(impulse: Vector2)`, `is_committed() -> bool`. Boss: `max_hp*=4,
damage*=2, token_drop*=5`, BossHud lifecycle exactly as enemy_base.gd
(`BossHud.new(); setup(enemy_type, accent); set_health(hp,max); play_entrance()`
on first aggro/damage). Death: `QuestManager.on_enemy_defeated(enemy_type)`,
`GameManager.record_stat("enemies_defeated")`, `AudioManager.play_sfx(
"enemy_death")`, token drops (TokenPickup3D, boss=5), `merge_conflict` splits
once. Behaviours: port enemy_base.gd's per-type patterns (charger telegraph,
ranged lob, shield, splitter, summoner, boss phases 75/50/25) in 3D on the XZ
plane. Aggro/leash → `AudioManager.play_music("combat_music"/"explore_music")`
with the same calm-check. Accent colours: enemy_base.DEATH_ACCENTS.

**Projectile3D** (`projectile3d.gd`, Area3D, group "player_projectile"):
`setup(dir: Vector2, dmg: int, type: String)`, vars `damage, pierce, weak,
crit`; flies on XZ at y≈0.6; hits group "enemy" → `take_damage(damage, crit,
dir)`. Scene path is FIXED: `res://scenes/world3d/projectile3d.tscn`.

**NPC3D** (`npc3d.gd`, Node3D + Area3D child, groups "interactable","npc"):
`npc_id, quest_ids: Array[String]`, `interact(player)` → `QuestManager.
on_interact(npc_id)` then `DialogueManager.start_dialogue(npc_id)`;
`get_prompt()` = "Talk to %s" % DialogueManager.get_npc_name(npc_id); Label3D
nameplate; quest [!] marker driven by npc.gd's `_has_available_quest` logic,
refreshed on QuestManager.quest_updated / quest_completed (arity!).

**Portal3D** (`portal3d.gd`, Node3D + Area3D, group "interactable"):
`target_region, portal_label`; `interact()` mirrors region_portal.gd (read it:
unlock check, GameManager.change_region, feedback); `get_prompt()`.

**TokenPickup3D** (`token_pickup3d.gd`, Area3D, group "token"): `token_type,
amount, magnet_radius, collected`; collection mirrors token_pickup.gd exactly
(ResourceManager, QuestManager.on_token_collected, SFX, magnet toward player).

**Interactable3D** (`interactable3d.gd`, Node3D + Area3D, group "interactable"):
`interact_id, interact_text, one_shot`; DELEGATES to a hidden 2D
`GenericInteractable` instance (instantiate scenes/world/generic_interactable.
tscn, set fields, `set_process(false)`, `visible=false`) and calls its
`interact(player)` — 100% logic reuse (deploy, terminals, story scripts).

## 5. Shadow proxy protocol (`scripts/world3d/actor_proxy.gd`, PROVIDED)

`ActorProxy.attach(host: Node3D, groups: Array, fields: Dictionary) ->
ActorProxy` parents a Node2D under the "proxy_root" node, joins `groups`, and
copies `fields` onto typed vars (`npc_id, quest_ids, token_type, amount,
collected, target_region, portal_label, interact_id, interact_text, enemy_type,
hp, max_hp, is_boss`). Host calls `proxy.sync()` every frame (sets
global_position = Map3D.to_map(host.global_position)) and
`proxy.set_field(name, value)` on changes. Proxy frees itself with its host.
Player: groups ["player_proxy"]. Others: the same groups as their 2D twin.

## 6. Shared helpers (PROVIDED — use them, do not fork them)

- `Map3D` (`scripts/world3d/map3d.gd`): `PX`, `to3d(px, y)`, `to_map(v)`,
  `model(key) -> Node3D` (key "pack/name", exists()-guarded, null if missing),
  `bounds(key) -> Dictionary {min,max,size,rigged,anims}` from manifest,
  `fit_height(node, key, h)`, `tint(node, color, emission_energy)`.
- `KenneyAnim` (`scripts/world3d/kenney_anim.gd`): `KenneyAnim.attach(root)
  -> KenneyAnim` (finds AnimationPlayer, loops idle/walk/sprint etc.),
  `play(name, blend := 0.15, speed := 1.0)`, `has(name)`.
- Manifest: `assets/external/kenney3d/manifest.json` — every model's
  min/max/size and animation list. Characters (mini-characters, graveyard
  character-*, mini-dungeon character-*, mini-arena/market/forest character-*)
  share ONE 32-clip set: static, idle, walk, sprint, jump, fall, crouch, sit,
  drive, die, pick-up, emote-yes/no, holding-right/left/both(-shoot),
  attack-melee-right/left, attack-kick-right/left, interact-right/left.
  Cube-pets: static, idle, walk, run, eat, dance. UFOs: none (bob procedurally).

## 7. Look recipe ("Neon Afterhours" in 3D)

- **Environment:** background Color(0.03,0.03,0.06); ambient light color
  (0.35,0.40,0.55) energy 0.35; tonemap ACES (white 1.0, exposure 1.05);
  glow ON: hdr_threshold 1.0, intensity 0.9, bloom 0.12, blend SOFTLIGHT,
  levels 2-5; SSAO ON (radius 1.0, intensity 2.0); SSR off; volumetric fog ON
  (density 0.025, albedo tinted per region, emission 0.15 * accent, length 64,
  anisotropy 0.6). Fog (depth) off. Per-region: rebuild the fog albedo/
  ambient/moon tint from the region accent (`world.REGION_ACCENT` in world.gd).
- **Moon:** DirectionalLight3D energy 0.4, colour (0.7,0.78,1.0), rotation
  pitch -50° yaw 30°, shadows on (PCF, blur 1.5, max distance 60).
- **Neon:** OmniLight3D per lamp/sign/screen: energy 2.5–5, range 5–9,
  attenuation 1.6, shadows OFF except the region focal (ON). Emissive
  StandardMaterial3D on screens/signs: emission = accent, energy 4–7 (they
  must bloom). Kenney materials: keep flat colormap, roughness 0.9, metallic 0.
- **Camera:** perspective FOV 34°, pitch −56°, yaw −18° (3/4 view so walls
  and props show a face), distance 21u → ~14u × 9u visible; follow with
  exponential damping (rate 6) + 1.2u look-ahead in velocity dir; clamp so the
  view never leaves the region rect; `add_trauma(amount)`, `punch_zoom(amount)`,
  `region_settle()` in group "camera_fx" (honour SettingsManager camera_shake).
- **Floors:** MultiMeshInstance3D per material (kit floor tiles) — never 300
  MeshInstance3Ds. Walls: StaticBody3D box colliders on the region border
  (layer 6 "walls") plus kit wall meshes. Cover from `_region_cover` gets
  colliders. Cells outside the room are solid black.
- **Region → kit** (all exist under assets/external/kenney3d/):
  localhost → furniture + food (pizza, cup-coffee, soda-can) + space-station
  screens; dependency_district → factory (boxes/conveyors/catwalks) +
  prototype crates + city-industrial backdrop; stackoverflow_ruins →
  graveyard (dead answers = graves/crypts, lanterns, fences); api_bazaar →
  mini-market (stalls, registers, shelves) + retro-urban awnings + food;
  cloud_district → space-station (floor panels, computers, displays) +
  modular-space rooms; open_source_wildlands → nature (trees, rocks, cliffs,
  campfire) + mini-forest; corporate_enterprise → city-commercial skyscrapers
  backdrop + furniture office + space-station displays; gpu_mines →
  modular-cave + factory cogs/pipes + tower-defense detail-crystal;
  production → factory conveyors/buttons + city-industrial + space-station
  displays; token_vault → castle (towers, metal-gate) + mini-dungeon (chest,
  coin, columns) + tower-defense crystals.
- **Characters:** player → `mini-characters/character-male-b`. NPCs:
  roommate_ai male-c, maintainer male-d, stackoverflow_hermit
  `graveyard/character-keeper`, api_reseller `mini-market/character-employee`,
  junior_agent female-b, cloud_salesperson female-c, oss_maintainer
  `mini-forest/character-archer`, svp_ai male-e, gpu_foreman male-f,
  oncall_engineer female-d.
- **Enemies:** bug `cube-pets/animal-bee` (scale 0.35), rate_limiter
  `tower-defense/enemy-ufo-a`, memory_leak `graveyard/character-zombie`,
  merge_conflict `mini-dungeon/character-orc`, scope_creep
  `graveyard/character-vampire`, dependency_demon `graveyard/character-skeleton`,
  hallucination `graveyard/character-ghost`, null_reference
  `tower-defense/enemy-ufo-b`, legacy_system `graveyard/character-keeper`
  (tinted), legacy_monolith `mini-arena/statue` (scale 2.2), infinite_context
  `tower-defense/enemy-ufo-d-weapon` (scale 2), cloud_bill
  `tower-defense/enemy-ufo-c-weapon` (scale 1.8), enterprise_architect
  `mini-characters/character-male-a` (scale 1.8). Tint bosses/elites with the
  enemy's accent; add an OmniLight in the accent for the "tell".
- **Tokens:** `mini-dungeon/coin` spinning (gold; "cached" tinted cyan;
  "compute" → `tower-defense/detail-crystal`) with a small OmniLight.
- **Portals:** `mini-dungeon/gate` frame + an emissive spinning ring shader
  (assets/shaders3d/portal_vortex.gdshader) + OmniLight + GPUParticles3D.
- **Props by interact id:** dream_app_terminal furniture/desk+computerScreen+
  computerKeyboard; deploy_button prototype/button-floor-round (red, emissive);
  client_email furniture/laptop; free_tokens_ad space-station/display-wall;
  agent_terminal space-station/computer-system; broken_service space-station/
  container-tall + red light; prop_coffee furniture/kitchenCoffeeMachine;
  abandoned_package prototype/crate; backup_server space-station/computer-wide;
  prop_node_modules factory/box-large stack; prop_leftpad prototype/crate;
  prop_lockfile mini-dungeon/chest; prop_api_stall mini-market/cash-register;
  prop_status_page space-station/display-wall; prop_pricing mini-market/
  shelf-bags; prop_gravestone graveyard/gravestone-round; prop_accepted
  graveyard/gravestone-cross-large (lit); prop_invoice space-station/computer;
  prop_dashboard space-station/display-wall-wide; prop_rig factory/cog-a +
  crystal; prop_fan factory/cone; prop_sponsor mini-dungeon/chest; prop_issue
  mini-forest/target; prop_mission mini-arena/banner; prop_kanban space-station/
  display-wall; prop_pager space-station/computer; prop_runbook mini-dungeon/
  table; prop_vault castle/metal-gate + mini-dungeon/chest.

## 8. Physics layers (3D) — mirror the 2D scene values

1 player, 2 enemies, 3 tokens, 4 interactables, 5 projectiles, 6 walls.
Player body layer 1 mask 32(walls); player Hitbox Area3D layer 1 mask 2; enemy
body layer 2 mask 32; enemy Hitbox layer 2 mask 16; projectile layer 16 mask
2; npc/portal/interactable Area3D layer 8; token layer 4 mask 1; player
InteractArea mask 8. Cover/walls: StaticBody3D layer 32.

## 9. Budgets

≤ 700 MeshInstance3D per region (floors via MultiMesh), ≤ 40 OmniLights per
region with ≤ 3 casting shadows, ≤ 12 GPUParticles3D alive, one WorldEnvironment.
Region rebuild < 0.5s. 60 fps at 1080p on integrated graphics is the target.

## 10. Validation (centralized, after the round)

`godot --headless --import` (GLBs), all 28 suites + `tests/world3d_test.tscn`,
windowed `tools/capture3d.tscn` → docs/screenshots/qa3d/*.png, eyeballed.
