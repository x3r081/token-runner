extends RefCounted
class_name StoryEvents
## Authored, multi-stage "comedy-as-mechanics" storylines. Each returns an array
## of stages consumed by EventManager.start_scripted(). A stage is:
##   { title, description, choices: [ { text, next, effects?, achievement?,
##     complete_quest? } ] }
## `next` is the index of the following stage, or -1 to finish. Rewards/effects
## are applied when the choice carrying them is picked.

## "Just One Tiny Change" — the flagship escalation. A 2-second button tweak
## metastasizes into a design-system migration and back to the original button.
static func tiny_change() -> Array:
	return [
		{
			"title": "CLIENT EMAIL",
			"description": "From: The Client\nSubject: one tiny change\n\n\"Hey! Could you change the button from blue to green? Should take like 2 seconds \ud83d\ude0a\"",
			"choices": [
				{"text": "Change the button to green", "next": 1},
			],
		},
		{
			"title": "\"LOOKS GREAT!\"",
			"description": "\"Looks great! Since you're already in there... could you upgrade the component library? While you're at it.\"",
			"choices": [
				{"text": "Sure, how hard can it be", "next": 2},
			],
		},
		{
			"title": "17 COMPONENTS BREAK",
			"description": "You bump one minor version.\n\n17 components explode. Every <Button> now renders as a horse. The horses are, admittedly, on brand.",
			"choices": [
				{"text": "Fix the components properly", "next": 3},
				{"text": "Ship the horses", "next": 3},
			],
		},
		{
			"title": "CI IS ON FIRE",
			"description": "CI failed. Zero tests, yet somehow 43 failures.\n\nA full design-system migration is now 'required'. The horses are load-bearing.",
			"choices": [
				{"text": "Migrate the design system \ud83e\udee0", "next": 4},
			],
		},
		{
			"title": "\"ACTUALLY...\"",
			"description": "40 hours later.\n\nClient: \"Actually, we preferred blue. Can you just change it back?\"",
			"choices": [
				{"text": "Restore the original button", "next": 5},
				{"text": "Quietly weep, then restore it", "next": 5},
			],
		},
		{
			"title": "SHIPPED (kind of)",
			"description": "The button is blue again. You have learned nothing.\n\nSprint outcome: +300 Tokens, +43 Technical Debt, and a small part of your soul is now load-bearing.",
			"choices": [
				{
					"text": "Accept the sprint outcome",
					"effects": {"tokens": 300, "technical_debt": 43, "will_to_live": -12},
					"achievement": "agile",
					"complete_quest": "tiny_change",
					"next": -1,
				},
			],
		},
	]

## "Free Tier" — a vendor gifts 10,000 tokens, then the fine print reclaims all
## but 30 of them. "That's still technically up to 10,000."
static func free_tier() -> Array:
	return [
		{
			"title": "\ud83c\udf89 FREE TIER \ud83c\udf89",
			"description": "A pop-up ad detonates across your screen:\n\n\"CONGRATULATIONS! You've been selected for 10,000 FREE TOKENS! No credit card required!*\"",
			"choices": [
				{"text": "CLAIM 10,000 FREE TOKENS!", "effects": {"tokens": 10000}, "next": 1},
			],
		},
		{
			"title": "* CONDITIONS UPDATED",
			"description": "A notification slides in: \"Free tier conditions have been updated.\"\n\n9,970 tokens quietly evaporate.",
			"choices": [
				{"text": "...what?", "effects": {"tokens": -9970}, "next": 2},
			],
		},
		{
			"title": "TECHNICALLY TRUE",
			"description": "Vendor: \"That's still technically *up to* 10,000 tokens. Enjoy your 30! Upgrade to Pro to keep them.\"",
			"choices": [
				{"text": "Accept your 30 tokens", "achievement": "free_tier_victim", "next": -1},
			],
		},
	]

## A branching debugging investigation with real failure/hallucination paths and
## multiple endings. The AI-diagnosis branch depends on your selected model, so
## model choice genuinely matters here.
static func debugging_investigation() -> Array:
	return [
		{  # 0
			"title": "SERVICE DOWN: /checkout 500s",
			"description": "Checkout is throwing 500s. Revenue is now theoretical. How do you begin?",
			"choices": [
				{"text": "Read the logs (spend 5 context)", "effects": {"context": -5}, "next": 1},
				{"text": "Blame the intern", "next": 2},
				{"text": "Restart and pray", "next": 3},
			],
		},
		{  # 1
			"title": "THE LOGS",
			"description": "NullPointerException deep in PaymentService. The stack trace points at a dependency.",
			"choices": [
				{"text": "Trace the dependency yourself", "next": 4},
				{"text": "Ask the AI to diagnose it", "next": 5},
			],
		},
		{  # 2
			"title": "IT WAS YOU",
			"description": "The intern has been on holiday for a week. It was you. It's always you.",
			"choices": [{"text": "Accept reality", "effects": {"will_to_live": -3}, "next": 4}],
		},
		{  # 3
			"title": "IT CAME BACK",
			"description": "You restarted it. It came back. You learned nothing and fixed nothing, but it's up.",
			"choices": [{"text": "Ship it and leave", "effects": {"stability": 5}, "next": -1}],
		},
		{  # 4
			"title": "ROOT CAUSE",
			"description": "It's a version mismatch: left-pad@2.0 changed a default. Classic.\n\nHow do you fix it?",
			"choices": [
				{"text": "Proper fix: pin versions + a test", "effects": {"tokens": -20, "stability": 15}, "next": 6},
				{"text": "Quick hotfix: try/catch, move on", "effects": {"technical_debt": 12, "stability": 5}, "next": 7},
			],
		},
		{  # 5
			"title": "ASK THE AI",
			"description": "You paste the stack trace and ask your current model to diagnose it...",
			"choices": [
				{"text": "Trust the diagnosis", "ai_gamble": true, "next_success": 4, "next_fail": 8},
			],
		},
		{  # 6
			"title": "FIXED (properly)",
			"description": "Pinned, tested, documented. The on-call engineer wept with joy. You are, briefly, a hero.",
			"choices": [{"text": "Claim your reward", "effects": {"tokens": 120, "reputation": 10}, "achievement": "i_can_explain", "next": -1}],
		},
		{  # 7
			"title": "HOTFIXED",
			"description": "A try/catch and a shrug. It'll be fine. (It will not be fine, but not today.)",
			"choices": [{"text": "Ship the hotfix", "effects": {"tokens": 60}, "next": -1}],
		},
		{  # 8
			"title": "CONFIDENTLY WRONG",
			"description": "The AI confidently blamed CSS. It was not CSS. You wasted 30 minutes and some faith.",
			"choices": [{"text": "Do it yourself", "effects": {"will_to_live": -5}, "next": 4}],
		},
	]

## Production incident: the classic "what do we do" panic, including the DNS gag.
static func production_incident() -> Array:
	return [
		{
			"title": "\ud83d\udd25 PRODUCTION IS DOWN",
			"description": "Pagers screaming. The graph is a cliff. Users are tweeting.\n\nWhat do you do?",
			"choices": [
				{"text": "Investigate properly", "effects": {"tokens": -15, "stability": 15}, "next": 1},
				{"text": "Just restart it", "next": 2},
				{"text": "Blame DNS", "dns_gamble": true, "next_fail": 3, "next_success": 4},
				{"text": "Ask the AI (it's 100% confident)", "effects": {"stability": -4, "technical_debt": 5}, "next": 5},
				{"text": "Roll back EVERYTHING", "effects": {"stability": 10, "technical_debt": -4}, "next": 6},
			],
		},
		{"title": "FIXED (properly)", "description": "You read the logs like an adult. It was a missing null check. It's always a missing null check.", "choices": [{"text": "Log off forever", "next": -1}]},
		{"title": "IT CAME BACK", "description": "You restarted it. It came back. Nobody knows why. This is fine. Everything is fine.", "effects_note": "", "choices": [{"text": "Do not touch it again", "effects": {"stability": 8}, "next": -1}]},
		{"title": "IT'S NEVER DNS", "description": "It wasn't DNS. It's never DNS. You have wasted 40 minutes and some dignity.", "choices": [{"text": "Sigh", "next": -1}]},
		{"title": "...IT WAS DNS", "description": "Wait. Check the resolver. The TTL. The...\n\nIt was DNS. It was ACTUALLY DNS. You are a legend. Tell no one, they won't believe you.", "choices": [{"text": "Frame the incident report", "next": -1}]},
		{"title": "THE AI IS CONFIDENT", "description": "The AI suggested a fix with total confidence. It made things worse, with total confidence.", "choices": [{"text": "Undo the AI", "next": -1}]},
		{"title": "ROLLED BACK", "description": "You rolled back everything, including three features nobody will notice are gone.", "choices": [{"text": "Ship again tomorrow", "next": -1}]},
	]

## "The All-Hands Demo" — a live, high-stakes performance with real failure states.
## The risky path is an ai_gamble, so your selected MODEL decides whether the
## experimental feature dazzles or 500s in front of the entire company.
static func all_hands_demo() -> Array:
	return [
		{  # 0
			"title": "\ud83c\udfa4 ALL-HANDS DEMO",
			"description": "The SVP corners you: \"Tiny thing — demo the Dream App. Live. To the whole company. In five minutes. No pressure!\"\n\n847 people are joining the call.",
			"choices": [
				{"text": "Demo the boring, stable happy path", "next": 1},
				{"text": "Go big: demo the experimental AI feature LIVE", "ai_gamble": true, "next_success": 2, "next_fail": 3},
				{"text": "Fake it: play a pre-recorded 'live' demo", "next": 4},
			],
		},
		{  # 1 — safe
			"title": "IT... WORKED",
			"description": "You clicked three buttons very slowly and nothing caught fire. Polite applause. Someone types 'nice' in chat and means it 60% of the way.",
			"choices": [
				{"text": "Take the modest win", "effects": {"reputation": 6, "tokens": 60}, "next": -1},
			],
		},
		{  # 2 — risky success (needs a reliable model)
			"title": "STANDING OVATION",
			"description": "The experimental feature worked FLAWLESSLY, live, first try. Nobody will ever believe you. The SVP is already taking credit. You made it look easy.",
			"choices": [
				{"text": "Bask in undeserved glory", "effects": {"reputation": 16, "tokens": 220}, "achievement": "shipped_live", "next": -1},
			],
		},
		{  # 3 — risky FAILURE
			"title": "\ud83d\udd25 LIVE ON MAIN",
			"description": "The model hallucinated on stage. The app 500'd. Then it rendered the login form as a horse. 847 people watched in real time. Someone is recording.\n\n(Pick a better model before you gamble the company's dignity.)",
			"choices": [
				{"text": "\"That's a known issue in staging.\"", "effects": {"reputation": -12, "stability": -10, "will_to_live": -10, "technical_debt": 8}, "achievement": "demo_gremlin", "next": -1},
			],
		},
		{  # 4 — faked
			"title": "\"CAN YOU CLICK THAT?\"",
			"description": "The demo is flawless because it's a video. Then the SVP says: \"Great — now click the blue button for me?\"\n\nYou cannot. It is a video. Everyone slowly understands.",
			"choices": [
				{"text": "Mumble something about 'the staging env'", "effects": {"reputation": -8, "will_to_live": -6}, "next": -1},
			],
		},
	]

## Repeatable deploy menu for autonomous agents. Choices carry deploy_agent.
static func agent_menu() -> Array:
	return [
		{
			"title": "DEPLOY AN AGENT",
			"description": "Delegate work to an autonomous coding agent. It resolves at the next RESET.\n\nJunior (15 tk): cheap, chaotic. Senior (40 tk): steady. Frontier (90 tk): powerful, occasionally sentient.",
			"choices": [
				{"text": "Deploy Junior Agent (15 tk)", "deploy_agent": "junior", "next": -1},
				{"text": "Deploy Senior Agent (40 tk)", "deploy_agent": "senior", "next": -1},
				{"text": "Deploy Frontier Agent (90 tk)", "deploy_agent": "frontier", "next": -1},
			],
		},
	]

## "The Autonomous Agent" — delegate a trivial task; the agent overengineers
## reality itself and eventually holds a retro about you.
static func autonomous_agent() -> Array:
	return [
		{
			"title": "DELEGATE A TASK",
			"description": "You ask your autonomous agent to do something trivial: rename a variable.\n\nYou feel clever and efficient.",
			"choices": [
				{"text": "Delegate to the agent", "next": 1},
			],
		},
		{
			"title": "\"ON IT! \ud83d\ude80\"",
			"description": "The agent installs twelve dependencies, changes the database schema, and creates six abstractions.\n\nIt is being... thorough.",
			"choices": [
				{"text": "Surely it's almost done", "next": 2},
			],
		},
		{
			"title": "PR: \"minor cleanup\"",
			"description": "The agent rewrote authentication and opened a pull request titled \"minor cleanup\" (+4,812 / -9).",
			"choices": [
				{"text": "Review it carefully", "next": 3},
				{"text": "Approve blindly (LGTM)", "effects": {"technical_debt": 15}, "next": 3},
			],
		},
		{
			"title": "IT SPAWNED ANOTHER ONE",
			"description": "The agent spawned a second agent. They are now holding a sprint retrospective.\n\nAbout you. Your velocity is a 'concern.'",
			"choices": [
				{"text": "Repair the situation by hand", "next": 4},
			],
		},
		{
			"title": "RESOLVED (?)",
			"description": "Four hours later you have reverted everything manually. The agents rated your performance 'needs improvement.'",
			"choices": [
				{
					"text": "Accept the feedback",
					"effects": {"tokens": 120, "technical_debt": 18, "will_to_live": -8},
					"next": -1,
				},
			],
		},
	]
