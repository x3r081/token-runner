extends RefCounted
class_name ComedyLines
## Central comedy text library — the single source of truth for rotating quips,
## roasts, taunts and toast copy (docs/COMEDY_BIBLE.md is the tone contract).
##
## Two rules govern everything in here:
##  1. The joke rides ALONGSIDE the information, never instead of it. A label
##     that stops telling the player what a thing does has failed, no matter how
##     funny it is.
##  2. Nothing repeats within a session until its pool is exhausted. Repetition
##     is what kills a joke, so `pick()` deals from a shuffled bag per pool and
##     only reshuffles when the bag runs dry.
##
## Static-only. Use via `const _Comedy = preload("res://scripts/ui/comedy_lines.gd")`
## or the global `ComedyLines` name.

# Shuffled bags of remaining indices, keyed by pool name. Static so the
# no-repeat guarantee survives UI screens being freed and re-instantiated
# (the death screen is rebuilt on every single death).
static var _bags: Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var _seeded := false

## Deal one line from `pool`, never repeating until the pool is exhausted.
static func pick(key: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	if not _seeded:
		_rng.randomize()
		_seeded = true
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		bag = []
		for i in pool.size():
			bag.append(i)
		# Fisher-Yates: a shuffled bag, dealt from the back.
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: int = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
		_bags[key] = bag
	var idx: int = int(bag.pop_back())
	idx = clampi(idx, 0, pool.size() - 1)
	return String(pool[idx])

## Plain random choice (no memory) — for one-shot flavor where repeats are fine.
static func any(pool: Array) -> String:
	if pool.is_empty():
		return ""
	if not _seeded:
		_rng.randomize()
		_seeded = true
	return String(pool[_rng.randi() % pool.size()])

## Session counters (how many times you've stared at the same fridge, etc.).
static var _counts: Dictionary = {}

## Increment and return the counter for `key`. First call returns 1.
static func bump(key: String) -> int:
	var n: int = int(_counts.get(key, 0)) + 1
	_counts[key] = n
	return n

static func count_of(key: String) -> int:
	return int(_counts.get(key, 0))

## Wipe the no-repeat memory and the counters. Called on New Game so a fresh
## run genuinely feels fresh.
static func reset_session() -> void:
	_bags.clear()
	_counts.clear()

## The prop-staring ladder: the more times you interact with the same piece of
## scenery, the more openly the game worries about you. Ordered, not random —
## escalation only works if it climbs.
static func visit_note(n: int) -> String:
	match n:
		1: return ""
		2: return "second look · nothing has changed"
		3: return "third look · still nothing"
		4: return "fourth look · this is now a coping mechanism"
		5: return "fifth look · we are becoming concerned"
		6: return "sixth look · are you okay"
		7: return "seventh look · please speak to a human being"
		8: return "eighth look · we have stopped counting (we have not stopped counting)"
	return "%d looks · this object cannot help you and has never claimed otherwise" % n

# ------------------------------------------------------------------ death ----
## Cause-of-death flavor. Dry, specific, and true — the sting is the accuracy.
const DEATH := [
	"You have been rate limited by reality.",
	"Production would like a word.",
	"The agent said it was 100% confident.",
	"Your architecture achieved sentience and rejected you.",
	"You ran out of tokens halfway through fixing the token system.",
	"Works on my machine. Unfortunately, this isn't your machine.",
	"Context window exceeded. You forgot to breathe.",
	"The merge conflict won.",
	"Killed by a race condition. It got there first.",
	"Root cause: undetermined. Contributing factor: you.",
	"The retry logic retried you. Three times. With exponential backoff.",
	"You died doing what you loved: reading a stack trace with 400 frames.",
	"Off by one. It was always going to be off by one.",
	"Your last words were 'it's probably fine.' They were logged at INFO.",
	"Killed by an exception that was caught, logged at DEBUG, and ignored.",
	"You have been deprecated. Migration guide: not written.",
	"Null. Not an object containing null. Just null, all the way down.",
	"The deploy succeeded. You did not.",
	"Terminated by the scheduler. It needed the memory for a dashboard.",
	"Marked as duplicate.",
	"Postmortem scheduled. Blameless. Everyone already knows.",
	"It worked in staging. You do not have a staging.",
	"You were the single point of failure. It was even documented.",
	"The cache was stale. So were you.",
	"Cause of death: a temporary workaround, load-bearing since Tuesday.",
	"You leaked memory until there was none left for you.",
	"A dependency updated itself overnight. Semver was a suggestion.",
	"You have exceeded your monthly quota of survival.",
	"An infinite loop finally found an exit. It was you.",
	"The linter warned you. In yellow. You have never once read yellow.",
	"The rollback rolled back to a version that also did not work.",
	"Segmentation fault. Core dumped. Dignity dumped.",
	"Killed by technical debt, compounded hourly.",
	"The healthcheck returned 200. The health did not.",
	"One character in a config file. It was whitespace.",
	"Your last commit message was 'fix'. It was not a fix.",
	"Garbage collected. Nothing was holding a reference to you.",
	"It was DNS.",
	"You hit a rate limit inside the retry that was handling the rate limit.",
	"Cause of death: a quick five-minute fix, hour 47.",
	"Optimistically locked out of your own life.",
	"The incident channel has 91 people in it. None of them are you now.",
	"The AI wrote the fix. The AI also wrote the bug. The AI is very sorry.",
	"You were paged, and then, briefly, you were the page.",
	"Killed instantly by a feature flag someone flipped on a Friday.",
	"Circular dependency detected. Between you and the deadline.",
	"You have been evicted from the pod. It was nothing personal. It never is.",
]

# ------------------------------------------------------------- main menu ----
## Loading/menu tips. Same energy as "backups are unnecessary until
## approximately three seconds after you need one."
const MENU_TIPS := [
	"Backups are unnecessary until approximately three seconds after you need one.",
	"Deleting the test is technically one way to make the test suite green.",
	"Your free-tier limit is always fourteen seconds away.",
	"Technical debt is just features you have not apologised for yet.",
	"Estimates are a genre of fiction with an unusually loyal readership.",
	"There is no temporary fix. There is only a fix nobody has dared touch since.",
	"If it works and you don't know why, it doesn't work and you don't know why.",
	"Every quick five-minute fix contains a smaller, angrier five-minute fix.",
	"The bug is never in the library. It was in the library.",
	"Staging exists so that production has someone to disappoint.",
	"You do not need Kubernetes. You need Kubernetes to be on your CV.",
	"Sufficiently advanced YAML is indistinguishable from a language you never agreed to learn.",
	"The retro will identify a process failure. It was a person. It was you. It's fine.",
	"Documentation was accurate six months ago and is now historical fiction.",
	"'It works on my machine' is a true statement and a resignation letter.",
	"If you can't reproduce it, congratulations: it's a feature with intermittent availability.",
	"The best time to add monitoring was before the outage. The second best time is during.",
	"Refactoring is moving the problem somewhere the reviewer won't look.",
	"Nobody reads the changelog. Write it anyway. Write it for the archaeologists.",
	"Any variable named `temp` will outlive you.",
	"A code freeze is a period during which the number of hotfixes is not discussed.",
	"The senior engineer's superpower is having already made this exact mistake.",
	"If the meeting could have been an email, the email could have been a decision nobody made.",
	"Your AI assistant is confident. Confidence is not a test suite.",
	"The model will happily invent a function. It will not invent the library it lives in.",
	"Prompting is programming with worse error messages and much better manners.",
	"Every autonomous agent is one bad assumption from being an autonomous incident.",
	"You will not save money by switching models. You'll spend the savings on more calls.",
	"Context windows are like apartments: you fill whatever you rent.",
	"The cloud is someone else's computer, invoiced monthly, with feelings.",
	"Serverless still has servers. They're just nobody's problem until they're everybody's.",
	"Autoscaling scales the invoice first and the capacity second.",
	"Nothing focuses an architecture review like the words 'per request'.",
	"A vendor's free tier is a trial of your own self-control.",
	"'Enterprise-ready' means it has a sales team.",
	"Every migration is a rewrite wearing a reassuring hat.",
	"The database is fine. The database is always fine. Please stop looking at the database.",
	"NoSQL means no schema, which means the schema lives in six services and one person's head.",
	"An index makes reads fast and your 3AM self furious.",
	"Never trust a migration you wrote at 3AM. Or at any other time.",
	"Blame DNS first. Apologise never. Occasionally be correct.",
	"The status page is green because the status page is also down.",
	"Uptime is measured in nines. Yours is measured in vibes.",
	"The on-call phone never rings during office hours. It has standards.",
	"An incident is just a deploy with a wider audience.",
	"Rollbacks are easy right up until the first database migration.",
	"Nobody has ever regretted writing a test. Several have regretted saying so out loud.",
	"Your .env file should not be in version control. Again.",
	"Secrets rotate. Screenshots of secrets do not.",
	"Security is everyone's responsibility, which is how it became nobody's ticket.",
	"The most durable part of any prototype is the part you meant to replace.",
	"Ship it. You can be embarrassed later, on a much bigger server.",
	"Sleep is a dependency. It has no fallback and no maintainer.",
	"Touch grass. The grass has 100% uptime and requires no YAML.",
]

# ------------------------------------------------------------------ pause ----
## Pause is a punchline: nothing is running, which is both the relief and the joke.
const PAUSE := [
	"Nothing is running. That is the problem.",
	"The world is paused. Your cloud bill is not.",
	"Time has stopped. The deadline hasn't been told.",
	"Production is fine. Probably. Nobody is looking.",
	"This is the most stable the app has ever been.",
	"Zero requests. Zero errors. Flawless.",
	"Breathe. The token quota can wait roughly this long.",
	"Somewhere, a cron job is running unsupervised.",
	"You paused. The technical debt is still accruing interest.",
	"Nothing is on fire, because nothing is on.",
	"Uptime: paused. Availability: philosophical.",
	"You are not procrastinating. You are gathering requirements.",
	"The build is green. The build has not been run.",
	"Consider this a maintenance window nobody was told about.",
	"Every service is healthy. None of them are awake.",
	"This is the retrospective. You're in it. Say something.",
	"The agent is idle. That is the safest it has ever been.",
	"Frozen at 3AM, like the codebase.",
	"No alerts. Suspicious. Deeply suspicious.",
	"It's very quiet in here. Somebody should write documentation.",
	"Latency: infinite. Complaints: zero. Ship it.",
	"You have achieved perfect stability by achieving nothing.",
	"The best incident is the one you paused before it started.",
	"Standing meeting in progress. Everyone is standing very still.",
]

const PAUSE_SAVED := [
	"Saved. Unlike your last backup.",
	"Saved. Written, flushed, fsynced. Extravagant.",
	"Saved. Which is more than production does.",
	"Saved. Somewhere a DBA nodded once.",
	"Saved. No merge conflict. Enjoy the novelty.",
	"Saved. Durable, consistent, and mildly smug about it.",
	"Saved. That is one (1) thing that went to plan today.",
	"Saved. If this ever fails, blame DNS.",
	"Saved. Your progress persists. Your posture does not.",
	"Saved. Commit message: 'stuff'.",
	"Saved. Take the win — there won't be another for a while.",
	"Saved. Ctrl+S is muscle memory. Good. Keep it.",
]

# ------------------------------------------------------------- dialogue ----
## All of these unambiguously mean "advance the conversation".
const DIALOGUE_CONTINUE := [
	"Continue", "Go On", "Uh-huh", "And Then?", "Keep Talking",
	"Continue (Reluctantly)", "Sure", "I'm Listening", "Right. Yes. Continue",
]

const DIALOGUE_CHOICE_HINT := [
	"Pick one. Neither is a mistake yet.",
	"Choose. The postmortem will reference this moment.",
	"Both options are defensible. One of them is defensible in court.",
	"There is no wrong answer. There are only expensive ones.",
	"Decide. Consensus is just a decision with more meetings.",
	"Pick one. You can regret it at your own pace.",
]

# ---------------------------------------------------------------- events ----
## Incident-ticket dressing: fake severity language that is funnier the more
## accurately it apes a real incident channel.
const INCIDENT_SEVERITY := [
	"SEV-2 (optimistic)",
	"SEV-1 (accurate)",
	"SEV-3 (politically)",
	"severity: yes",
	"severity: pending vibes",
	"SEV-2, trending SEV-1",
	"severity: 'let's not label it'",
]

const INCIDENT_FOOTER := [
	"Choices have consequences. Some arrive later, at the worst possible moment.",
	"Every option here is a decision you will explain in a retro.",
	"No option is free. Some are just billed later.",
	"Pick fast. Incidents get more expensive while you read.",
	"Whatever you choose becomes 'the way we've always done it'.",
]

# ------------------------------------------------------------- dream app ----
## Dry one-liners for each Dream App branch — flavour on top of the real name.
const BRANCH_QUIPS := {
	"frontend": "The part users judge you by in the first 400ms.",
	"backend": "Where the actual work hides behind a very calm API.",
	"database": "The only component nobody is allowed to be creative with.",
	"ai": "Costs money per token, gratitude per demo.",
	"infrastructure": "Nobody thanks you for this until it stops.",
	"security": "Boring, unglamorous, and the reason you still have users.",
	"marketing": "Turning 'it compiles' into 'redefining the category'.",
	"observability": "Knowing your app is on fire, in real time, with charts.",
	"architecture": "Boxes. Arrows. Consequences.",
}

const SHIP_BTN_TIPS := [
	"Deploy the Dream App. On a Friday. At 3AM. Sure.",
	"Ships the app and ends the run. No takebacks, no staging.",
	"One button between you and a permanent public record.",
	"Deploy to production. Production has been notified. Production is unhappy.",
	"This ends the run and scores your app. Press it when you're proud enough.",
]

const DREAM_APP_SUBTITLES := [
	"holographic dev console · v0.0.1-alpha",
	"holographic dev console · tokens in, features out",
	"holographic dev console · buy upgrades, hit requirements, deploy",
	"holographic dev console · the roadmap, but purchasable",
	"holographic dev console · every upgrade adds debt somewhere",
]

# ------------------------------------------------------------------- map ----
## Region one-liners: what the place IS, said unkindly. Informative first.
const REGION_SUBTITLES := {
	"localhost": "Your apartment. Desk, bed, Claude, the Deploy button.",
	"dependency_district": "1.2 GB of node_modules with its own gravity.",
	"stackoverflow_ruins": "Answers from 2013. Still the only ones that work.",
	"api_bazaar": "Everything is for sale, per request, plus surcharge.",
	"cloud_district": "Someone else's computer. Invoiced monthly.",
	"open_source_wildlands": "Held up by one volunteer and 40M downloads a month.",
	"corporate_enterprise": "Please raise a ticket to raise a ticket.",
	"gpu_mines": "94°C and described, repeatedly, as 'fine'.",
	"production": "Real users. Real money. Do not touch anything.",
	"token_vault": "The reserves. The vault is judging your spending.",
}

## Locked-region taunts. Always paired with the real unlock hint at the callsite.
const LOCKED_TAUNTS := [
	"Access denied. Politely.",
	"Not yet. Raise a ticket.",
	"Locked. Come back with credentials and a reason.",
	"Behind a paywall made of quests.",
	"Requires prior art.",
	"Not provisioned yet.",
	"Pending approval from a committee of one.",
	"Locked. The road exists; you have not earned the road.",
]

# ---------------------------------------------------------------- toasts ----
## Short toast/notification copy. Callers append the real facts — these are the
## garnish, never the substance. (HUD owns the toast widget itself.)
const TOAST_QUEST_DONE := [
	"Closed. Do not reopen it.",
	"Ticket moved to Done. Nobody will notice.",
	"Shipped. Undocumented, but shipped.",
	"Resolved. Cause of resolution: unclear.",
	"Done. Please update the ticket. You will not update the ticket.",
	"Complete. The scope only grew twice.",
]

const TOAST_PURCHASE := [
	"Bought. It's in the codebase now. Forever.",
	"Purchased. Refunds are a myth told to juniors.",
	"Added to the architecture. The diagram grows.",
	"Installed. Load-bearing as of this moment.",
	"Acquired. Future you will 'just quickly refactor' this.",
	"Merged straight to main, as tradition demands.",
]

const TOAST_DEBT := [
	"Borrowed against a future you have not met.",
	"Interest starts now. So does the denial.",
	"You'll fix it in the next sprint. There is no next sprint.",
	"Added to the pile. The pile has a name now.",
	"Noted in a TODO nobody will grep for.",
	"Debt accepted. The codebase remembers everything.",
]

const RIDICULOUS_TIERS := [
	"Architecture: reasonable. Suspicious.",
	"Architecture: one whiteboard's worth of regret.",
	"Architecture: now requires a diagram to explain the diagram.",
	"Architecture: a conference talk is forming.",
	"Architecture: legible only to its author, on a good day.",
	"Architecture Ridiculousness: MAXIMUM. Frame it. Bill for it.",
]

## Short quips for HUD toasts. Facts belong in the caller's text; these garnish.
static func quest_complete_quip() -> String:
	return pick("toast_quest", TOAST_QUEST_DONE)

static func purchase_quip() -> String:
	return pick("toast_purchase", TOAST_PURCHASE)

static func debt_quip() -> String:
	return pick("toast_debt", TOAST_DEBT)

## Deterministic (not rotated) — it describes a state, so it must be stable.
static func ridiculousness_quip(level: int) -> String:
	var idx := clampi(level / 2, 0, RIDICULOUS_TIERS.size() - 1)
	return String(RIDICULOUS_TIERS[idx])

static func region_subtitle(region_id: String) -> String:
	return String(REGION_SUBTITLES.get(region_id, "Uncharted. Probably billable."))

static func branch_quip(branch: String) -> String:
	return String(BRANCH_QUIPS.get(branch, "Nobody remembers why this is in the plan."))

# ---------------------------------------------------------------- roasts ----
## Shared roast fragments used by both the death screen (mid-run) and the
## victory screen (final). Each takes the run's real numbers so the joke is
## about THIS run, not a generic one.

## `model_id` comes from ModelManager.current().id — passed in, because static
## helpers here stay free of autoload lookups.
static func model_roast(model_id: String) -> String:
	match model_id:
		"local":
			return "You were running Local 7B to save money. It saved money."
		"frontier":
			return "You were on Frontier. Expensive AND dead. A premium experience."
		"experimental":
			return "You were on Experimental. The clue was in the name."
		_:
			return "You were on Fast. Fast to where, exactly."

static func debt_roast(debt: float) -> String:
	if debt >= 120.0:
		return "Technical debt %d. This is no longer debt. This is a mortgage." % int(debt)
	if debt >= 80.0:
		return "Technical debt %d. It qualifies for its own Series B." % int(debt)
	if debt >= 40.0:
		return "Technical debt %d — the 'restructure the whole team' kind." % int(debt)
	if debt >= 15.0:
		return "Technical debt %d. Manageable, in the way a small fire is manageable." % int(debt)
	return "Technical debt %d. Almost responsible. It won't last." % int(debt)

static func death_count_roast(deaths: int) -> String:
	if deaths <= 1:
		return "First death. A rite of passage. Nobody clapped."
	if deaths <= 4:
		return "Death #%d. You're establishing a pattern. Not a good one." % deaths
	if deaths <= 9:
		return "Death #%d. At this point it is a workflow." % deaths
	if deaths <= 19:
		return "Death #%d. Consider this your on-call rotation." % deaths
	return "Death #%d. The respawn point knows you by name now." % deaths
