# Architecture

## Overview

Token Runner is a Godot 4.7 2D top-down adventure game built with GDScript. All visuals and audio are procedurally generated at build/dev time.

## Directory Structure

```
├── assets/textures/generated/   # Procedural PNG assets
├── data/                        # JSON game content
│   ├── quests/
│   ├── upgrades/
│   ├── dialogue/
│   ├── events/
│   └── achievements.json
├── docs/                        # Design docs, comedy bible, status
├── scenes/                      # Godot scenes
│   ├── main/                    # Main menu
│   ├── player/                  # Player character
│   ├── world/                   # World, tokens, NPCs, portals
│   ├── combat/                  # Enemies, projectiles
│   └── ui/                      # HUD, menus, dialogue
├── scripts/
│   ├── autoload/                # Singleton managers
│   ├── player/
│   ├── world/
│   ├── combat/
│   ├── ui/
│   └── tools/                   # Asset generator
└── tests/                       # Smoke tests
```

## Autoloads

| Singleton | Responsibility |
|-----------|----------------|
| GameManager | Game state, regions, acts, win/loss |
| ResourceManager | Token economy, all resources |
| QuestManager | Quest definitions, progress, rewards |
| DreamAppManager | Upgrade tree, ship readiness |
| EventManager | Random incidents |
| AudioManager | Procedural SFX and music |
| SettingsManager | User preferences |
| AchievementManager | Achievement tracking |
| DialogueManager | NPC conversation flow |
| SaveManager | JSON save/load |

## World Generation

`RegionBuilder` statically constructs each region at runtime:
- Floor tile grid from procedural textures
- Wall collision on borders
- Token pickups, enemies, NPCs, portals, interactables
- Region-specific content tables

## Data-Driven Content

Quests, upgrades, dialogue, events, and achievements are JSON files loaded at startup. Adding content does not require code changes.

## Save Format

`user://saves/save_N.json` with `save_version` field for migration.

## Signals

Systems communicate via signals — no direct scene references between managers and gameplay objects.

## Testing

Headless smoke tests validate autoload init, quest flow, save roundtrip, upgrades, and region building.
