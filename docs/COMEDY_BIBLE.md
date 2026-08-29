# Comedy Bible — Token Runner: Ship Before Reset

## Tone Rules
1. **Brutally accurate** > random memes. Jokes should sting because they're true.
2. **Dry sarcasm** over slapstick. The game is tired, not manic.
3. **Escalate absurdity** across acts — early jokes are relatable, late jokes are existential.
4. **Fourth-wall breaks** sparingly (max ~1 per hour of play).
5. **Never punch down** at junior devs; punch up at hype, enterprise, and our own bad decisions.
6. **Callbacks reward attention** — NPCs reference earlier quests.

## THE HARD RULE (read this before writing any UI text)

**The joke rides ALONGSIDE the information. It never replaces it.**

The player's most common complaint is not "I don't understand the keys", it is
"I don't know what to do or where to go". Every label, button, tooltip and
popup must still answer that after the gag lands. In practice:

- Button labels keep the plain verb: `Continue (Pretending This Is Fine)`,
  `Give Up (Main Menu)`, `Resume Vibe Coding [Esc]`. The parenthetical carries
  the function; the rest carries the joke.
- Settings rows read `Real Name — quip` (never quip alone).
- Blockers state the reason and the fix: the Deploy button lists the exact
  unmet requirements and says which key opens the console to fix them.
- Locked map regions print the literal unlock quest **next to** the taunt.
- Decorative-only surfaces (incident ticket numbers, prop-visit counters, build
  notes) may be pure joke, because nothing depends on reading them.

If a line would be ambiguous to a first-time player, the joke loses. Always.

## Where the jokes live (code map)

| Surface | File | Notes |
|---|---|---|
| Shared pools + no-repeat dealer | `scripts/ui/comedy_lines.gd` | `ComedyLines.pick(key, pool)` never repeats within a session until the pool is exhausted |
| Death causes + run roast | `scripts/ui/death_screen.gd` | pool of 47; roast built from deaths/debt/upgrades/tokens/model |
| Ship report, corners cut, postmortem | `scripts/ui/victory_screen.gd` | uses `GameManager.get_ship_roast()` plus computed sections |
| Menu tips, build notes, premise | `scripts/ui/main_menu.gd` | tip rotates every 9s |
| Pause quips + "while you are here" reminder | `scripts/ui/pause_menu.gd` | reminder = region + tracked objective + key list |
| Sarcastic-but-honest settings | `scripts/ui/settings_menu.gd` | quips come from `SettingsManager.get_setting_label()` |
| Incident ticket dressing | `scripts/ui/event_popup.gd` | INC number derived from event id (stable per incident) |
| Prop flavor + escalation | `scripts/world/generic_interactable.gd` | `FLAVOR: id -> [title, body_1, body_2, ...]` |
| Upgrade framing, ship checklist, receipts | `scripts/ui/dream_app_panel.gd` | |
| Region subtitles, locked taunts | `scripts/ui/map_panel.gd` | |
| Dialogue continue phrasings, choice nudges | `scripts/ui/dialogue_ui.gd` | every variant still means "advance" |

**Adding a new pool:** put it in `comedy_lines.gd` and deal from it with
`ComedyLines.pick("unique_key", POOL)`. Never `randi()` a pool by hand — the
no-repeat guarantee is the whole reason repeated screens stay funny.
`ComedyLines.reset_session()` clears the bags and counters on New Game.

## Recurring Gags
- Token price changes immediately after gains
- "One tiny change" always catastrophic
- Every cloud migration answer is just "cloud"
- Kubernetes requires more YAML than users
- The agent is "100% confident" right before disaster
- DNS is always blamed first
- `.env` committed "accidentally" (again)
- Free tier is always 14 seconds away
- Documentation was accurate six months ago

### Established this pass (keep consistent)
- **The prop-staring counter.** Interacting with the same scenery repeatedly
  escalates: the body text changes for 2–4 visits, and a chip above it counts
  ("third look · still nothing" → "sixth look · are you okay"). The game gets
  visibly more worried about you than you are.
- **The pre-written postmortem.** Incident language applied in advance, with the
  euphemism intact and the truth in brackets. Always closes on
  *"Action items: 3. Completed: 0. Reopened next quarter: 3."*
- **INC-#### · severity: yes.** Every event popup is filed as a ticket with a
  severity nobody can agree on and "reported by: everyone".
- **The debt surcharge.** Technical debt silently raises every future price. The
  Dream App console states the live percentage — the joke is that it is real.
- **The ninth subscription.** You do not remember signing up. It remembers you.
  It renews on the 3rd.
- **Anything named `temp`.** Load-bearing, unattributed, older than the team, and
  never to be deleted.
- **"It is always Friday here."** Deprecations, grandfathering deadlines and
  code freezes all expire today, in the API Bazaar.
- **The zip tie.** The universal fix for thermal, structural and emotional
  problems in the GPU Mines.
- **Undo, but for your entire body.** Ctrl+Z is the respawn key, and the death
  screen never lets that pun go.

## NPC Personalities

### Stack Overflow Hermit
Ancient wisdom, outdated answers. Signs off every sentence with "marked as duplicate."

### Shady API Reseller
Speaks in pricing tiers. Everything has a "limited-time" surcharge.

### Cloud Salesperson
Genuinely cannot explain why you need the cloud. Says "elastic" a lot.

### Open Source Maintainer
Powered by instant noodles and guilt. Will help for free but you'll feel bad.

### Senior VP of AI Transformation Excellence
Buzzwords only. Has never written code. Demands AI strategy by Friday.

### The Junior Agent
Autonomous, enthusiastic, catastrophically wrong. Needs escorting.
(Punch at the *autonomy hype*, never at juniors. The agent is a product
decision that went wrong, not a person who is bad at their job.)

## Quest Naming Convention
`[Relatable Pain] + [Understatement or Absurd Stakes]`
- "Just One Tiny Change"
- "Quick Five-Minute Fix" (estimated: 47 hours)
- "We Don't Need Staging"

## Death Messages
Full pool: `ComedyLines.DEATH` (47 lines, no repeat within a session).
Shape: a **cause of death** written the way an incident channel would write it.
One clause, specific, technically literate, no setup–punchline structure.
- "You have been rate limited by reality."
- "Killed by an exception that was caught, logged at DEBUG, and ignored."
- "You hit a rate limit inside the retry that was handling the rate limit."
- "Garbage collected. Nothing was holding a reference to you."

Under it, the **run roast**: death count line + the two most damning facts that
are currently true (debt, upgrades bought, tokens hoarded, model chosen,
ridiculousness). Never generic — if it could apply to any run, cut it.

## Loading / Menu Tips
Full pool: `ComedyLines.MENU_TIPS` (54 lines); a smaller legacy pool also lives
in `GameManager.get_loading_tip()` for non-menu loading screens.
Reference energy — every new tip must clear this bar:
- "Backups are unnecessary until approximately three seconds after you need one."
- "Estimates are a genre of fiction with an unusually loyal readership."
- "There is no temporary fix. There is only a fix nobody has dared touch since."
- "Any variable named `temp` will outlive you."
- "Prompting is programming with worse error messages and much better manners."

## Things NOT to Overuse
- "It's always DNS" (max 3 times per playthrough)
- Kidney-selling for API credits (once, prominently)
- "Hello world" jokes
- Generic "404" humor
- Rage/exclamation marks. The voice is exhausted, not shouting.
- Emoji as punchline. Emoji are wayfinding (📍 🔒 ✓ ✗ ▸ ◀), not comedy.
- Jokes about someone being bad at their job. Aim at the system that produced
  the decision.

## Ideas Queue
- NPC notices save reload (fourth-wall, Act 2)
- Boss complains about difficulty slider
- Item description admits dev ran out of ideas (secret item)
- CFO cutscene when cloud bill exceeds tokens earned
- Prop-staring counter reaching double digits unlocks a tiny achievement
- The pager escalation policy eventually lists you four times

## Act Structure
| Act | Regions | Comedy Level |
|-----|---------|--------------|
| 1 | Localhost, Dependency District | Relatable frustration |
| 2 | Stack Overflow Ruins, API Bazaar | Workflow absurdity |
| 3 | Cloud District, Open Source Wildlands | Cost & complexity |
| 4 | Corporate Enterprise, GPU Mines | Bureaucracy & hype |
| 5 | Production, Token Vault | Existential insanity |
