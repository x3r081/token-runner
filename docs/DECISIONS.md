# Architecture & Design Decisions

## Engine & Language
- **Godot 4.7** with **GDScript** for fast iteration and native 2D/2.5D rendering.
- Top-down isometric-style presentation with layered parallax and neon cyberpunk palette.

## Presentation
- Stylized cyberpunk / neon aesthetic using procedural textures, shaders, and particles.
- No placeholder primitives in shipping build — all visuals procedurally generated or shader-driven.
- Custom UI theme with sarcastic copy baked into labels and tooltips.

## Architecture Pattern
- **Autoload singletons** for cross-cutting systems (resources, quests, save, audio, events).
- **Resource-based data** (`.tres` / JSON) for quests, upgrades, regions, dialogue.
- **Signal-driven** communication between systems — no tight coupling.
- **Scene composition** for world regions; each district is a sub-scene loaded into world hub.

## Core Loop
1. Explore region → collect tokens/resources
2. Complete quests from NPCs
3. Fight thematic enemies (bugs, rate limiters, scope creep)
4. Return to Localhost base
5. Spend resources on Dream App upgrades
6. Unlock new regions and harder content
7. Ship the Dream App (win condition)

## Resources (Strategic)
| Resource | Role |
|----------|------|
| Tokens | Primary currency, ability costs |
| Compute | Enables expensive models/abilities |
| Context | Quest complexity cap |
| API Credits | Merchant purchases |
| Coffee | Focus regeneration |
| Focus | Combat effectiveness |
| Stability | Reduces random failures |
| Technical Debt | Accumulates; causes incidents |
| Will To Live | Morale; affects failure recovery |
| Reputation | Unlocks corporate quests |

## Combat
- Ability-based, not button-mashing. Cooldowns cost tokens/compute.
- Enemies are thematic (Null Reference, Rate Limiter, Scope Creep).
- Boss encounters at region gates.

## Save Format
- JSON with version field (`save_version: 1`) in `user://saves/`.
- Autosave on region transition and quest completion.

## Humor
- Comedy bible in `docs/COMEDY_BIBLE.md` tracks jokes, NPC voices, and callbacks.
- Humor escalates by act (early: relatable → late: existential tech insanity).

## Testing
- GUT-style headless smoke tests via `--headless --script`.
- CI validates project loads and critical autoloads initialize.

## Release
- Windows x86-64 primary; Linux secondary.
- GitHub Actions for CI and export artifacts.
