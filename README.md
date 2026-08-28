# Token Runner: Ship Before Reset

**A strategic adventure about vibe-coding your dream app before the token reset.**

Collect tokens. Fight dependency demons. Upgrade your Dream App. Deploy to production. Regret everything.

![Token Runner](assets/textures/icon.png)

## About

You are a sleep-deprived vibe coder wandering a stylized cyberpunk tech-world. Your mission: accumulate enough AI tokens, compute, and questionable architectural decisions to **ship the Dream App** before reality rate-limits you.

This is not a prototype. This is a complete indie game with:

- **10 explorable regions** — from Localhost to the Token Vault
- **15+ quests** — each with personality, sarcasm, and catastrophic stakes
- **Strategic resource economy** — tokens, compute, context, technical debt, will to live
- **Dream App upgrade tree** — 9 branches, 50+ upgrades, all funny
- **Combat & abilities** — fight Scope Creep, Rate Limiters, THE LEGACY MONOLITH
- **Random incidents** — provider outages, rogue agents, CFO cloud bill panic
- **Full save system** — autosave, continue, versioned JSON saves
- **Achievements** — "Works On My Machine", "Zero Tests Zero Fear", and more
- **Win condition** — ship the app, get roasted by the results screen
- **Post-game** — keep playing after shipping

## Screenshots

Run the game to generate procedural visuals. Regions feature neon cyberpunk tilesets, particle effects, and shader-driven atmosphere.

## Controls

| Key | Action |
|-----|--------|
| WASD / Arrow Keys | Move |
| E / Space | Interact / Talk |
| 1 | Prompt Blast (costs tokens) |
| 2 | Cache (brief invincibility, costs compute) |
| J | Quest Log |
| B | Dream App Upgrades |
| M | World Map |
| Esc | Pause |

## Installation

### Requirements

- [Godot 4.3+](https://godotengine.org/) (developed on 4.7)

### Run from source

```bash
git clone https://github.com/x3r081/token-runner.git
cd token-runner
godot --headless --path . --script scripts/tools/run_generate.gd
godot --headless --path . --import
godot --path .
```

Press **New Game** and start collecting tokens in your apartment.

### Build

```bash
godot --headless --path . --export-release "Linux" build/token-runner-linux.x86_64
godot --headless --path . --export-release "Windows Desktop" build/token-runner-windows.exe
```

Export templates required. See [Godot export docs](https://docs.godotengine.org/en/stable/tutorials/export/index.html).

## Gameplay

1. **Explore** regions and collect tokens
2. **Talk to NPCs** — each has dialogue, quests, and opinions
3. **Fight enemies** — thematic dev nightmares
4. **Complete quests** — unlock new regions and rewards
5. **Upgrade the Dream App** (B key) — invest in frontend, AI, infrastructure, security...
6. **Manage resources** — balance tokens vs technical debt vs will to live
7. **Ship it** — meet requirements and hit Deploy in Localhost

### Ship Requirements

- 15+ features
- 8+ stability
- 12+ total upgrades
- AI tier 2+
- Infrastructure tier 2+

## Architecture

See [docs/DECISIONS.md](docs/DECISIONS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Core systems are autoload singletons:

- `GameManager` — state, regions, win condition
- `ResourceManager` — economy
- `QuestManager` — quest framework
- `DreamAppManager` — upgrade tree
- `EventManager` — random incidents
- `SaveManager` — persistence

World regions are procedurally built at runtime via `RegionBuilder`. All sprites and tiles are procedurally generated — no external art assets.

## Testing

```bash
godot --headless --path . --scene tests/smoke_test.tscn
```

## Credits

- **Design, code, art, audio, comedy:** Autonomous development
- **Engine:** [Godot Engine](https://godotengine.org/) (MIT)
- **External assets:** None — all visuals and audio procedurally generated

## License

MIT License — see [LICENSE](LICENSE)

## Status

**Release ready** — v1.0

*"Your free-tier limit is always 14 seconds away."*
