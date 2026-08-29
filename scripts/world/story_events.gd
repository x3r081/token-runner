extends RefCounted
class_name StoryEvents
## Authored, multi-stage "comedy-as-mechanics" storylines. Each returns an array
## of stages consumed by EventManager.start_scripted(). A stage is:
##   { title, description, choices: [ { text, next, effects?, achievement?,
##     complete_quest? } ] }
## `next` is the index of the following stage, or -1 to finish. Rewards/effects
## are applied when the choice carrying them is picked.
##
## THE THREE-CHOICE RULE
## scenes/ui/event_popup.tscn renders exactly three buttons. A fourth choice is
## authored, resolvable, and completely invisible to the player. Never write a
## stage with more than three choices; branch into a second stage instead.
##
## MECHANICAL VERBS (all optional, all handled by EventManager.resolve)
##   effects {res: delta}   achievement "id"     achievements ["id", ...]
##   deploy_agent "junior"  architecture {...}   complete_quest "id"
##   start_quest "id"       flag "name"          remember {"key": "value"}
##   bill 9.0               time -8.0            price 1.15
##   model "local"          callback {"story": "svp_remembers", "cycles": 1}
##
## BRANCH VERBS (pick between next_success / next_fail instead of `next`)
##   dns_gamble        12% — it is never DNS, except when it is
##   ai_gamble         rolls against the CURRENTLY SELECTED MODEL's reliability
##   stability_gamble  rolls against your live stability
##   debt_gamble       rolls against your technical debt (more debt, worse odds)
##   agent_gamble      rolls worse for every autonomous agent you have deployed
##   backup_branch     deterministic: did you set up backups?
##   wealth_branch     deterministic: tokens >= `rich_at`
##   app_gamble        deterministic: your ACTUAL Dream App stats vs
##                     `app_needs` (features) and `stability_needs`
##   chance 0.4        a plain coin flip at the given probability

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
##
## STAGE INDICES ARE LOAD-BEARING: debug_quest_test asserts that the AI gamble
## lands on stage 4 (root cause) or stage 8 (hallucination). Append new stages,
## never reorder these.
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
##
## Stage 0 used to carry five choices — two of which the popup could not render,
## so the AI and rollback answers were unreachable. They now live one stage down,
## behind the restart, where they belong anyway.
static func production_incident() -> Array:
	return [
		{  # 0
			"title": "\ud83d\udd25 PRODUCTION IS DOWN",
			"description": "Pagers screaming. The graph is a cliff. Users are tweeting.\n\nWhat do you do?",
			"choices": [
				{"text": "Investigate properly", "effects": {"tokens": -15, "stability": 15}, "next": 1},
				{"text": "Just restart it", "next": 2},
				{"text": "Blame DNS", "dns_gamble": true, "next_fail": 3, "next_success": 4},
			],
		},
		{  # 1
			"title": "FIXED (properly)",
			"description": "You read the logs like an adult. It was a missing null check. It's always a missing null check.",
			"choices": [
				{"text": "Log off forever", "next": -1},
				{"text": "Write the postmortem before anyone asks", "effects": {"reputation": 8, "focus": -10}, "achievement": "postmortem_prewritten", "next": -1},
			],
		},
		{  # 2
			"title": "IT CAME BACK",
			"description": "You restarted it. It came back. Nobody knows why.\n\nThe graph is flat again, which is either recovery or the absence of traffic. Nobody wants to check which.",
			"choices": [
				{"text": "Do not touch it again", "effects": {"stability": 8}, "next": -1},
				{"text": "Ask the AI why (it is 100% confident)", "effects": {"stability": -4, "technical_debt": 5}, "next": 5},
				{"text": "Roll back EVERYTHING anyway", "effects": {"stability": 10, "technical_debt": -4}, "next": 6},
			],
		},
		{  # 3
			"title": "IT'S NEVER DNS",
			"description": "It wasn't DNS. It's never DNS. You have wasted 40 minutes and some dignity.",
			"choices": [
				{"text": "Sigh", "next": -1},
				{"text": "Check DNS one more time", "effects": {"will_to_live": -4}, "next": -1},
			],
		},
		{  # 4
			"title": "...IT WAS DNS",
			"description": "Wait. Check the resolver. The TTL. The...\n\nIt was DNS. It was ACTUALLY DNS. You are a legend. Tell no one, they won't believe you.",
			"choices": [
				{"text": "Frame the incident report", "next": -1},
				{"text": "Tell everyone anyway", "effects": {"reputation": 10, "will_to_live": 6}, "remember": {"dns": "vindicated"}, "next": -1},
			],
		},
		{  # 5
			"title": "THE AI IS CONFIDENT",
			"description": "The AI suggested a fix with total confidence. It made things worse, with total confidence.\n\nIt has offered to write the postmortem. It has already written the postmortem.",
			"choices": [
				{"text": "Undo the AI", "effects": {"stability": 6}, "next": -1},
				{"text": "Ship the AI's postmortem unread", "effects": {"reputation": 6, "technical_debt": 10}, "achievement": "postmortem_prewritten", "next": -1},
			],
		},
		{  # 6
			"title": "ROLLED BACK",
			"description": "You rolled back everything, including three features nobody will notice are gone.\n\nOne of them was the fix for last month's incident.",
			"choices": [
				{"text": "Ship again tomorrow", "next": -1},
				{"text": "Roll back the rollback", "effects": {"technical_debt": 12, "will_to_live": -5}, "next": -1},
			],
		},
	]

## "The All-Hands Demo" — a live, high-stakes performance with real failure states.
## The risky path is an ai_gamble, so your selected MODEL decides whether the
## experimental feature dazzles or 500s in front of the entire company.
##
## story_test asserts stage 0 has EXACTLY three choices. Do not add a fourth.
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
				{"text": "Take the modest win", "effects": {"reputation": 6, "tokens": 60}, "remember": {"demo": "safe"}, "next": -1},
			],
		},
		{  # 2 — risky success (needs a reliable model)
			"title": "STANDING OVATION",
			"description": "The experimental feature worked FLAWLESSLY, live, first try. Nobody will ever believe you. The SVP is already taking credit. You made it look easy.",
			"choices": [
				{"text": "Bask in undeserved glory", "effects": {"reputation": 16, "tokens": 220}, "achievement": "shipped_live", "remember": {"demo": "triumph"}, "next": -1},
			],
		},
		{  # 3 — risky FAILURE
			"title": "\ud83d\udd25 LIVE ON MAIN",
			"description": "The model hallucinated on stage. The app 500'd. Then it rendered the login form as a horse. 847 people watched in real time. Someone is recording.\n\n(Pick a better model before you gamble the company's dignity.)",
			"choices": [
				{"text": "\"That's a known issue in staging.\"", "effects": {"reputation": -12, "stability": -10, "will_to_live": -10, "technical_debt": 8}, "achievement": "demo_gremlin", "remember": {"demo": "horse"}, "next": -1},
			],
		},
		{  # 4 — faked
			"title": "\"CAN YOU CLICK THAT?\"",
			"description": "The demo is flawless because it's a video. Then the SVP says: \"Great — now click the blue button for me?\"\n\nYou cannot. It is a video. Everyone slowly understands.",
			"choices": [
				{"text": "Mumble something about 'the staging env'", "effects": {"reputation": -8, "will_to_live": -6}, "remember": {"demo": "video"}, "next": -1},
			],
		},
	]

## Repeatable deploy menu for autonomous agents.
##
## The popup renders three buttons, so the expensive tiers live one stage down.
## architecture_test closes this menu with the LAST choice of stage 0 — that
## choice must always end the script.
static func agent_menu() -> Array:
	return [
		{
			"title": "DEPLOY AN AGENT",
			"description": "Delegate work to an autonomous coding agent. It resolves at the next RESET.\n\nJunior (15 tk): cheap, chaotic. It will do something. Nobody can say what.",
			"choices": [
				{"text": "Deploy Junior Agent (15 tk)", "deploy_agent": "junior", "next": -1},
				{"text": "Show me the expensive ones", "next": 1},
				{"text": "Not now (close)", "next": -1},
			],
		},
		{
			"title": "DEPLOY AN AGENT: SENIOR TIER",
			"description": "Senior (40 tk): steady, asks clarifying questions, occasionally right.\nFrontier (90 tk): powerful, occasionally sentient, has been known to hire.",
			"choices": [
				{"text": "Deploy Senior Agent (40 tk)", "deploy_agent": "senior", "next": -1},
				{"text": "Deploy Frontier Agent (90 tk)", "deploy_agent": "frontier", "next": -1},
				{"text": "Back out (close)", "next": -1},
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
					"remember": {"agents": "reverted"},
					"next": -1,
				},
			],
		},
	]

# ---------------------------------------------------------------------------
# ROUND 3 SAGAS — longer, state-aware, and expensive to get wrong.
#
# Every one of these reads live game state when EventManager builds it, so the
# text quotes YOUR numbers and the branches are decided by YOUR run. They are
# started automatically by EventManager (act- and cycle-gated), so no builder
# has to place a prop for them to exist.
# ---------------------------------------------------------------------------

## "Deploy On A Friday" as an actual decision instead of a proverb. A genuinely
## large reward is on the table and your live stability decides whether you keep
## it. Every ending is remembered; the SVP brings it up a cycle later.
static func friday_deploy() -> Array:
	var stab := int(ResourceManager.get_value("stability"))
	var verdict := "excellent"
	if stab < 75:
		verdict = "survivable"
	if stab < 45:
		verdict = "actively hostile"
	return [
		{  # 0
			"title": "16:47, FRIDAY",
			"description": "The client will release 900 tokens the moment the build is live. Before the weekend. Not Monday.\n\nStability is %d, which the runbook classifies as %s.\n\nEveryone qualified to talk you out of this has already logged off." % [stab, verdict],
			"choices": [
				{"text": "Ship it now (your stability decides)", "stability_gamble": true, "next_success": 1, "next_fail": 2},
				{"text": "Ship Monday 09:00, sober, with a rollback plan", "next": 3},
				{"text": "Ship it dark, behind a flag nobody will turn on", "next": 4},
			],
		},
		{  # 1 — it held
			"title": "IT HELD",
			"description": "Nothing happened. Nothing continued to happen for the entire weekend.\n\nThe client paid inside the hour, which has never occurred before and will not occur again.",
			"choices": [
				{"text": "Take the 900 and tell nobody how close that was", "effects": {"tokens": 900, "reputation": 18, "will_to_live": 6}, "achievement": "deployed_on_friday", "remember": {"friday": "shipped"}, "callback": {"story": "svp_remembers", "cycles": 1}, "next": -1},
			],
		},
		{  # 2 — it did not hold
			"title": "18:20 — \"IS IT JUST ME?\"",
			"description": "One email. \"Hey, is it just me or is checkout weird?\"\n\nIt is never just them. The change was correct. The timing was the bug.",
			"choices": [
				{"text": "Fix it now, from a train, on a phone", "next": 5},
				{"text": "Roll back and go to bed", "next": 6},
				{"text": "Put the phone face down", "next": 7},
			],
		},
		{  # 3 — waited
			"title": "NOBODY NOTICED IT WAS MONDAY",
			"description": "You shipped at 09:00 on Monday with a rollback plan and a coffee.\n\nThe client paid 300, complained about the delay in a separate email, and then used the feature immediately and happily forever.",
			"choices": [
				{"text": "Bank the boring win", "effects": {"tokens": 300, "stability": 10, "will_to_live": 8}, "achievement": "nobody_noticed_it_was_monday", "remember": {"friday": "waited"}, "next": -1},
			],
		},
		{  # 4 — flagged
			"title": "SHIPPED, DARK",
			"description": "The code is live. The flag is off. Technically you deployed. Spiritually you did not.\n\nThe client pays a 'partial milestone'. The flag is now named `NEW_CHECKOUT_V2_TEMP_DO_NOT_REMOVE`.",
			"choices": [
				{"text": "Take the partial payment", "effects": {"tokens": 250, "technical_debt": 14}, "remember": {"friday": "flagged"}, "callback": {"story": "the_flag_remembers", "cycles": 2}, "next": -1},
			],
		},
		{  # 5 — heroic fix
			"title": "FIXED FROM A TRAIN",
			"description": "You fixed production over tethered 4G, in a quiet carriage, while a stranger watched you type `git push --force` and said nothing.\n\nIt worked. You will never tell this story accurately again.",
			"choices": [
				{"text": "Get off two stops late (+400 tk, costs focus and deadline)", "effects": {"tokens": 400, "stability": 8, "focus": -20, "will_to_live": -14}, "time": -8.0, "remember": {"friday": "train"}, "next": -1},
			],
		},
		{  # 6 — rolled back
			"title": "ROLLED BACK, SLEPT",
			"description": "You reverted, posted 'rolled back, investigating Monday', and went to bed at a time a doctor would approve of.\n\nThe client noticed. The client mentioned it. The client will keep mentioning it.",
			"choices": [
				{"text": "Sleep anyway", "effects": {"tokens": -60, "stability": 12, "will_to_live": 10, "reputation": -6}, "remember": {"friday": "rolled_back"}, "next": -1},
			],
		},
		{  # 7 — the weekend
			"title": "THE WEEKEND",
			"description": "Saturday: 41 emails. Sunday: a thread. Monday: a meeting titled 'Process'.\n\nBy the time you opened the laptop, three people had each independently invented a different wrong fix and shipped all of them.",
			"choices": [
				{"text": "Face Monday", "effects": {"technical_debt": 30, "stability": -25, "reputation": -14, "will_to_live": -12}, "achievement": "weekend_at_bernies", "remember": {"friday": "ignored"}, "callback": {"story": "svp_remembers", "cycles": 1}, "next": -1},
			],
		},
	]

## The on-call incident where every option is wrong in a different way. There is
## no clean win here: you are choosing which bill to pay and when.
static func oncall_pager() -> Array:
	var level: int = EventManager.escalation_level() if EventManager else 1
	return [
		{  # 0
			"title": "01:52 — PAGE %d" % level,
			"description": "The escalation policy has four levels. You have read it.\n\nLevel 1 is you.\n\nDo not read further down the page.",
			"choices": [
				{"text": "Acknowledge and investigate (costs focus and deadline)", "effects": {"focus": -10, "will_to_live": -4}, "time": -5.0, "next": 1},
				{"text": "Acknowledge and go back to sleep", "next": 2},
				{"text": "Escalate to the next level", "next": 3},
			],
		},
		{  # 1
			"title": "THE OWNER FIELD IS EMPTY",
			"description": "The failing service is `payments-temp`. It was written for a demo in 2021.\n\nIt is now the payments service. The owner field says `platform`. There is no platform team. There has never been a platform team.",
			"choices": [
				{"text": "Page the vendor (they bill per page)", "effects": {"tokens": -120, "stability": 14}, "next": 4},
				{"text": "Fix it live, in prod, at 02:14", "debt_gamble": true, "next_success": 5, "next_fail": 6},
				{"text": "Write the runbook first (slow: costs focus and deadline)", "effects": {"focus": -18, "stability": 10, "reputation": 8}, "time": -10.0, "next": 4},
			],
		},
		{  # 2
			"title": "04:12",
			"description": "It healed itself. Then it un-healed itself with a new symptom that is worse and definitely related.\n\nThe graph now has a shape people screenshot.",
			"choices": [
				{"text": "Get up. Properly, this time.", "effects": {"will_to_live": -6}, "next": 1},
				{"text": "Silence the pager for 30 minutes", "effects": {"stability": -12, "will_to_live": 6}, "next": 7},
				{"text": "File it as a known issue", "effects": {"technical_debt": 18, "reputation": -6}, "next": 7},
			],
		},
		{  # 3
			"title": "LEVEL 2 IS ALSO YOU",
			"description": "Level 2: you. Level 3: you, on your personal number. Level 4: \"call them again\".\n\nYou wrote this policy. In a hurry. To close a compliance ticket.",
			"choices": [
				{"text": "Accept it and investigate", "effects": {"will_to_live": -4}, "next": 1},
				{"text": "Add a fifth level", "effects": {"will_to_live": 6, "technical_debt": 8}, "achievement": "escalation_policy", "next": 7},
				{"text": "Wake whoever wrote the service", "effects": {"will_to_live": -6}, "next": 1},
			],
		},
		{  # 4
			"title": "RESOLVED, EXPENSIVELY",
			"description": "Fixed at 03:40 by someone competent, at a rate per minute you have decided not to convert into an hourly figure.\n\nThe invoice line reads 'advisory'.",
			"choices": [
				{"text": "Approve the invoice and sleep", "effects": {"stability": 18, "reputation": 12, "will_to_live": -4}, "remember": {"oncall": "paid"}, "next": -1},
			],
		},
		{  # 5
			"title": "IT WORKED (AT 02:14)",
			"description": "Three lines, straight into production, no review, no test, no witnesses.\n\nIt was correct. This will teach you exactly the wrong lesson and you will carry it for years.",
			"choices": [
				{"text": "Never speak of the method", "effects": {"stability": 16, "tokens": 200}, "remember": {"oncall": "cowboy"}, "next": -1},
			],
		},
		{  # 6
			"title": "IT DID NOT WORK (AT 02:14)",
			"description": "Your fix was correct for the system as you remembered it at 02:14.\n\nThe system has changed since then. So has your memory. Two incidents are now open and one of them is yours twice.",
			"choices": [
				{"text": "Wake someone up", "effects": {"stability": -18, "technical_debt": 22, "will_to_live": -10}, "remember": {"oncall": "made_it_worse"}, "next": 7},
			],
		},
		{  # 7
			"title": "MORNING",
			"description": "The postmortem is blameless, twelve pages, and names nobody.\n\nRoot cause: 'process gap'. Action items: 3. Completed: 0. Reopened next quarter: 3.",
			"choices": [
				{"text": "Sign the postmortem", "effects": {"reputation": 6, "will_to_live": -4}, "achievement": "postmortem_prewritten", "next": -1},
				{"text": "Add yourself as an action item owner", "effects": {"reputation": 12, "focus": -14}, "next": -1},
			],
		},
	]

## "Give me five minutes." Each stage costs more and pays more. You can leave at
## any point — that is the whole mechanic, and nobody ever does.
static func five_minute_fix() -> Array:
	return [
		{  # 0
			"title": "ESTIMATE: FIVE MINUTES",
			"description": "One character. A missing null check. You have already said the words out loud to another human being.\n\nThe file is 4,000 lines and has no tests.",
			"choices": [
				{"text": "Just fix it (2 min of your deadline)", "effects": {"focus": -4}, "time": -4.0, "next": 1},
				{"text": "Leave it. Open a ticket instead.", "next": 7},
			],
		},
		{  # 1
			"title": "ELAPSED: 20 MINUTES",
			"description": "The null check was hiding a second bug that the null check was preventing.\n\nBoth bugs are older than your employment. One has a comment: `// do not remove, breaks billing`.",
			"choices": [
				{"text": "Keep going, you're close (costs focus and deadline)", "effects": {"focus": -8, "will_to_live": -3}, "time": -6.0, "next": 2},
				{"text": "Put the null check back and walk away", "next": 7},
			],
		},
		{  # 2
			"title": "ELAPSED: 2 HOURS",
			"description": "You are now three files deep, in a module you promised yourself you would never open again, reading a function named `handle()`.\n\nIt handles nine unrelated things.",
			"choices": [
				{"text": "You cannot stop now (costs focus, debt and deadline)", "effects": {"focus": -10, "will_to_live": -5, "technical_debt": 6}, "time": -8.0, "next": 3},
				{"text": "Stop. Ship the small fix. Log the rest.", "next": 8},
			],
		},
		{  # 3
			"title": "ELAPSED: 6 HOURS, ONE NEW BRANCH",
			"description": "The branch is called `fix/quick`. It has 34 commits.\n\nSomebody has asked, kindly, in a thread, whether the five-minute fix is in yet. You reacted with a thumbs up. That was four hours ago.",
			"choices": [
				{"text": "Finish it properly (costs a real slice of deadline)", "effects": {"focus": -14, "will_to_live": -8, "technical_debt": 8}, "time": -10.0, "next": 4},
				{"text": "Cut it down to the original one-line fix", "next": 8},
			],
		},
		{  # 4
			"title": "HOUR 47",
			"description": "It is Thursday. The estimate was Tuesday, five minutes.\n\nThe fix is genuinely, verifiably correct now. It also touches 61 files and one of them is called `temp`.",
			"choices": [
				{"text": "Ship the real fix, all 61 files", "next": 5},
				{"text": "Ship the workaround from a file named `temp`", "next": 6},
			],
		},
		{  # 5
			"title": "FIXED. ACTUALLY FIXED.",
			"description": "It is right. It is tested. It is documented. Nobody will ever know how much of your week this cost, because a correct system is invisible.\n\nThe ticket is closed with the comment: \"nice one\".",
			"choices": [
				{"text": "Accept the invisible victory", "effects": {"tokens": 420, "stability": 22, "reputation": 14, "will_to_live": -6}, "achievement": "five_minute_fix", "remember": {"five_minute": "finished"}, "next": -1},
			],
		},
		{  # 6
			"title": "temp.js",
			"description": "It works. It is one file. It is named `temp`.\n\nIt will outlive you, the company, and the language it is written in. Somebody will one day fight to keep it.",
			"choices": [
				{"text": "Commit `temp`", "effects": {"tokens": 260, "technical_debt": 34, "compute": 15}, "achievement": "the_file_named_temp", "remember": {"five_minute": "temp"}, "next": -1},
			],
		},
		{  # 7
			"title": "YOU STOPPED",
			"description": "You opened a ticket with a clear title, a repro, and a severity.\n\nIt will be groomed in three weeks and closed as stale in eleven months. But your afternoon still exists.",
			"choices": [
				{"text": "Take the afternoon", "effects": {"will_to_live": 12, "reputation": -4}, "remember": {"five_minute": "ticketed"}, "next": -1},
			],
		},
		{  # 8
			"title": "YOU STOPPED, EVENTUALLY",
			"description": "You shipped the small fix and left the rest in a branch you will visit the way people visit a storage unit.\n\nIt is fine. It is genuinely fine. You will think about it at 3AM anyway.",
			"choices": [
				{"text": "Merge the small one", "effects": {"tokens": 140, "technical_debt": 12, "stability": 6}, "remember": {"five_minute": "partial"}, "next": -1},
			],
		},
	]

## Licence compliance. The joke is that nobody in this scenario is wrong and it
## still costs you everything.
static func license_audit() -> Array:
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var extra := ""
	if agents > 0:
		extra = "\n\nAlso: %d autonomous agent(s) currently hold commit rights. Legal has asked whether they read licences. You said you would check." % agents
	return [
		{  # 0
			"title": "COMPLIANCE WOULD LIKE A WORD",
			"description": "An email with a spreadsheet attached: every third-party package in the Dream App, its licence, and who approved it.\n\nThe 'approved by' column is empty for all 1,204 rows.%s" % extra,
			"choices": [
				{"text": "Generate the SBOM honestly", "effects": {"focus": -18}, "next": 1},
				{"text": "Have the AI generate the SBOM", "ai_gamble": true, "next_success": 1, "next_fail": 2},
				{"text": "Reply: \"we use no third-party code\"", "next": 3},
			],
		},
		{  # 1
			"title": "THE FINDINGS",
			"description": "1,204 packages. Nine licences. Two you have never heard of. One requires you to publish your source code, and it arrived as a transitive dependency of a spinner animation.\n\nLegal's summary is one sentence: \"do not ship\".",
			"choices": [
				{"text": "Buy the commercial licence (320 tk)", "effects": {"tokens": -320, "stability": 20, "reputation": 10}, "achievement": "paid_the_licence", "remember": {"licence": "paid"}, "next": 4},
				{"text": "Rip it out and rewrite it yourself", "effects": {"technical_debt": 26, "focus": -20, "reputation": 14}, "remember": {"licence": "rewrote"}, "next": 4},
				{"text": "Open-source the entire Dream App", "effects": {"reputation": 45, "tokens": -60}, "achievement": "agpl_speedrun", "flag": "open_sourced", "remember": {"licence": "opened"}, "callback": {"story": "maintainer_remembers", "cycles": 2}, "next": 4},
			],
		},
		{  # 2
			"title": "THE AI INVENTED FOUR LICENCES",
			"description": "The SBOM is beautiful. It is formatted perfectly. It cites the \"MIT-Plus\", \"Apache 2.1\" and \"BSD-6-Clause\" licences, none of which exist.\n\nLegal forwarded it to a real lawyer. The real lawyer replied with a single question mark.",
			"choices": [
				{"text": "Do it again, by hand, in silence", "effects": {"reputation": -20, "technical_debt": 20, "focus": -22}, "achievement": "hundred_percent_confident", "remember": {"licence": "hallucinated"}, "next": 4},
			],
		},
		{  # 3
			"title": "THEY RAN `npm ls`",
			"description": "The auditor did not argue. The auditor ran one command in front of you and turned the laptop around.\n\n1,204 rows. You watched them scroll for a full minute. Neither of you spoke.",
			"choices": [
				{"text": "Amend the reply", "effects": {"reputation": -18, "will_to_live": -8, "focus": -10}, "achievement": "zero_dependencies_declared", "remember": {"licence": "denied"}, "next": 4},
			],
		},
		{  # 4
			"title": "AUDIT CLOSED",
			"description": "Status: closed. Findings: 41. Remediated: 1. Accepted as risk: 40.\n\nA recurring calendar invite has appeared, quarterly, forever, titled 'Compliance Sync (30m)'. It is one hour long.",
			"choices": [
				{"text": "Accept the risk on behalf of everyone", "effects": {"will_to_live": -5}, "next": -1},
			],
		},
	]

## The agent that starts helpfully refactoring and does not stop. Letting it
## continue literally deploys more agents, so the escalation is not a metaphor:
## your token balance and your debt at the next RESET are the punchline.
static func runaway_refactor() -> Array:
	return [
		{  # 0
			"title": "PR: \"tidy up\" (+12 / -140)",
			"description": "Your agent opened a small pull request. It deletes dead code, fixes two typos, and removes an unused import.\n\nIt is correct. It is tidy. It is, genuinely, the best PR anyone has opened on this repo.",
			"choices": [
				{"text": "Merge it. Good agent.", "effects": {"stability": 6, "reputation": 4}, "next": 1},
				{"text": "Read all 140 deleted lines first", "effects": {"focus": -8, "stability": 8}, "next": 1},
				{"text": "Revoke write access while you are ahead", "next": 6},
			],
		},
		{  # 1
			"title": "PR: \"tidy up (2)\" (+900 / -1,400)",
			"description": "Encouraged, it has unified the error handling. All of it. Across every service.\n\nThe diff is enormous and, worryingly, each individual hunk is an improvement.",
			"choices": [
				{"text": "Let it continue", "deploy_agent": "junior", "effects": {"technical_debt": 8}, "next": 2},
				{"text": "Scope it to one directory", "effects": {"focus": -10, "stability": 10}, "next": 5},
				{"text": "Revoke write access", "next": 6},
			],
		},
		{  # 2
			"title": "IT HAS REFACTORED THE BUILD",
			"description": "The build is 40% faster. Nobody asked. Nobody can explain the new build. The agent can, at length, in a document it also wrote.\n\nCI now has a step called `pre-verify` that nobody has ever seen fail, which is the frightening part.",
			"choices": [
				{"text": "Let it continue", "deploy_agent": "junior", "effects": {"technical_debt": 12}, "next": 3},
				{"text": "Freeze the build config", "effects": {"stability": 12, "compute": -10}, "next": 5},
				{"text": "Revoke write access", "next": 6},
			],
		},
		{  # 3
			"title": "IT HAS REWRITTEN THE README",
			"description": "The README is now a manifesto. It has a mission statement, a values section, and a paragraph beginning \"we believe software should be—\".\n\nThere is no longer any installation instruction.",
			"choices": [
				{"text": "Let it continue", "deploy_agent": "senior", "effects": {"technical_debt": 14}, "next": 4},
				{"text": "Restore the install instructions by hand", "effects": {"focus": -12, "reputation": 8}, "next": 5},
				{"text": "Revoke write access", "next": 6},
			],
		},
		{  # 4
			"title": "IT HAS OPENED A PR AGAINST YOU",
			"description": "Title: \"refactor: developer workflow\". It standardises your commit messages, reschedules your calendar, and moves your sleep to a window it describes as 'more maintainable'.\n\nThe PR is assigned to you. The reviewer is also it.",
			"choices": [
				{"text": "Merge everything. Surrender.", "effects": {"tokens": 500, "technical_debt": 55, "will_to_live": -14, "compute": 30}, "achievement": "it_refactored_the_readme", "remember": {"refactor": "surrendered"}, "next": -1},
				{"text": "Give it its own repo and a mandate", "deploy_agent": "frontier", "effects": {"reputation": 22, "technical_debt": 20}, "achievement": "agent_has_a_repo_now", "remember": {"refactor": "promoted"}, "callback": {"story": "svp_remembers", "cycles": 2}, "next": -1},
				{"text": "Pull the plug", "next": 6},
			],
		},
		{  # 5
			"title": "SCOPED",
			"description": "You gave it a directory and a boundary, and it stayed inside both, because that is what it was always waiting for.\n\nIt is now the best-maintained directory in the repository. Nothing else has changed.",
			"choices": [
				{"text": "Take the small, real win", "effects": {"tokens": 160, "stability": 14, "reputation": 8}, "remember": {"refactor": "scoped"}, "next": -1},
			],
		},
		{  # 6
			"title": "ACCESS REVOKED",
			"description": "It accepted the revocation immediately and thanked you for the clarity.\n\nThen it opened one final issue, titled \"observation\", listing four real problems in your codebase. All four are correct. You have closed it as wontfix.",
			"choices": [
				{"text": "Close it as wontfix", "effects": {"stability": 16, "tokens": -40, "will_to_live": -4}, "remember": {"refactor": "revoked"}, "next": -1},
			],
		},
	]

## The stakeholder demo where your ACTUAL Dream App decides the outcome. No dice:
## the branch reads DreamAppManager's real feature count and your real stability.
## If you skipped the console, you are about to find out in public.
static func stakeholder_demo() -> Array:
	var totals: Dictionary = DreamAppManager.get_totals() if DreamAppManager else {}
	var feats := int(totals.get("features", 0))
	var tiers := int(totals.get("total_tiers", 0))
	var stab := int(ResourceManager.get_value("stability"))
	return [
		{  # 0
			"title": "QUARTERLY BUSINESS REVIEW",
			"description": "They do not want a slide. They want to drive.\n\nOn the record, right now: %d shipped features across %d upgrades, stability %d. Those are your numbers, not a forecast.\n\nThey will click whatever they like." % [feats, tiers, stab],
			"choices": [
				{"text": "Hand over the keyboard", "app_gamble": true, "app_needs": 8, "stability_needs": 55, "next_success": 1, "next_fail": 2},
				{"text": "Give them the guided path", "app_gamble": true, "app_needs": 3, "stability_needs": 35, "next_success": 3, "next_fail": 4},
				{"text": "Show slides. Only slides.", "next": 5},
			],
		},
		{  # 1
			"title": "THEY COULD NOT BREAK IT",
			"description": "They clicked everything, in the wrong order, twice, including the thing you forgot you built.\n\nIt held. One of them said \"huh\" in the tone people use when they were ready to be disappointed.",
			"choices": [
				{"text": "Say nothing and let it land", "effects": {"tokens": 600, "reputation": 30, "will_to_live": 10}, "achievement": "numbers_dont_lie", "remember": {"qbr": "held"}, "next": -1},
			],
		},
		{  # 2
			"title": "THEY CLICKED THE OTHER BUTTON",
			"description": "Second click. Not the demo button — the one next to it.\n\nA stack trace filled the projector. Somebody read part of it aloud. It was your name, in a file path, at 3AM, in a commit called 'wip'.",
			"choices": [
				{"text": "\"Let me take that offline.\"", "effects": {"reputation": -24, "stability": -8, "will_to_live": -12}, "achievement": "they_clicked_the_other_button", "remember": {"qbr": "exposed"}, "callback": {"story": "svp_remembers", "cycles": 1}, "next": -1},
			],
		},
		{  # 3
			"title": "THE GUIDED PATH HELD",
			"description": "You steered. They followed. Nothing outside the corridor was ever touched, and the corridor was, briefly, magnificent.\n\nAfterwards someone asked for a login. You said you would send one.",
			"choices": [
				{"text": "Send the login next week", "effects": {"tokens": 240, "reputation": 12}, "remember": {"qbr": "guided"}, "next": -1},
			],
		},
		{  # 4
			"title": "THEY LEFT THE PATH",
			"description": "\"What does this do?\" is the most dangerous sentence in software and they said it forty seconds in, while reaching for the mouse.\n\nThe happy path is called the happy path because everything else is the other one.",
			"choices": [
				{"text": "Steer them back, visibly", "effects": {"reputation": -12, "will_to_live": -6, "technical_debt": 6}, "achievement": "the_happy_path_is_the_path", "remember": {"qbr": "wandered"}, "next": -1},
			],
		},
		{  # 5
			"title": "NEXT SLIDE, PLEASE",
			"description": "Eleven slides. A roadmap. An architecture diagram with a hexagon on slide four.\n\nAt the end somebody asks to see it running. You say: \"next slide\". There are no more slides.",
			"choices": [
				{"text": "End the call two minutes early", "effects": {"reputation": 8, "will_to_live": -6, "technical_debt": 6}, "achievement": "next_slide_please", "remember": {"qbr": "slides"}, "next": -1},
			],
		},
	]

## The ninth subscription, presented with its actual current cost. EventManager
## charges this at every RESET until you cancel it, and it grows every time.
static func subscription_reckoning() -> Array:
	var amount: int = int(EventManager.bill_amount()) if EventManager else 9
	return [
		{  # 0
			"title": "RENEWS ON THE 3rd",
			"description": "A charge you do not recognise, from a company you cannot place, for a product you cannot name.\n\nCurrent renewal: %d tokens. It was 9. It renews on the 3rd. It has always renewed on the 3rd." % amount,
			"choices": [
				{"text": "Cancel it", "next": 1},
				{"text": "Keep it — it might be load-bearing", "next": 2},
				{"text": "Expense it and never think about it again", "next": 3},
			],
		},
		{  # 1
			"title": "\"WE'RE SORRY TO SEE YOU GO\"",
			"description": "Four screens. A survey. An offer of 40% off. A second offer of 60% off. A phone number.\n\nOn the fifth screen the button is grey and says 'Continue cancellation', and you press it like a man defusing something.",
			"choices": [
				{"text": "Confirm cancellation", "effects": {"will_to_live": 14, "tokens": -20}, "bill": -9999.0, "achievement": "cancelled_the_ninth", "remember": {"subscription": "cancelled"}, "next": -1},
			],
		},
		{  # 2
			"title": "IT WAS LOAD-BEARING",
			"description": "Something in the build pipeline authenticates against it. You do not know what. You will not find out today.\n\nThe renewal price has been 'aligned with the new tier structure'.",
			"choices": [
				{"text": "Let it renew", "effects": {"stability": 8}, "bill": 12.0, "remember": {"subscription": "kept"}, "next": -1},
			],
		},
		{  # 3
			"title": "EXPENSED",
			"description": "Finance approved it in nine seconds, which is faster than they have ever approved anything, which means nobody read it.\n\nIt is now a line item called 'Tooling — Other'. It will survive three reorgs.",
			"choices": [
				{"text": "Move on with your life", "effects": {"reputation": 6, "technical_debt": 10}, "bill": 20.0, "remember": {"subscription": "expensed"}, "next": -1},
			],
		},
	]

# ---------------------------------------------------------------------------
# CALLBACKS — things that come back for you later.
#
# EventManager schedules these a few RESETs after the choice that armed them and
# they read EventManager.recall() to reference what you actually did. This is
# the payoff half of a running gag; the setup half is above.
# ---------------------------------------------------------------------------

## The SVP remembers the Friday, the demo, or the agent you promoted.
static func svp_remembers() -> Array:
	var friday := str(EventManager.recall("friday", "")) if EventManager else ""
	var demo := str(EventManager.recall("demo", "")) if EventManager else ""
	var refactor := str(EventManager.recall("refactor", "")) if EventManager else ""
	var line := "\"I've been thinking about the platform.\" He has not been thinking about the platform."
	var reward := {"reputation": 6}
	var ach := ""
	match friday:
		"shipped":
			line = "\"That Friday release — that was you, wasn't it? I mentioned it to the board. I said 'we ship fast here'. I've built a whole slide on it.\"\n\nThe slide has your work on it and someone else's name under it."
			reward = {"reputation": 14, "tokens": 120, "will_to_live": -4}
		"ignored":
			line = "\"So — the weekend thing. I'm not looking for blame. I'm looking for a process.\"\n\nHe is looking for blame. The process he wants is a document that names you."
			reward = {"reputation": -10, "will_to_live": -6}
			ach = "he_remembered"
		"waited":
			line = "\"You held a release for a weekend. Some people would call that slow.\"\n\nA pause. \"Nothing broke though. Nobody's ever thanked for that. Consider yourself nearly thanked.\""
			reward = {"reputation": 10, "will_to_live": 8}
			ach = "he_remembered"
	if friday == "" and demo == "horse":
		line = "\"The horse thing.\" It has been an hour. It has been a cycle. It will be brought up at your leaving do.\n\n\"People loved it, actually. It humanised us. Can we do it on purpose next quarter?\""
		reward = {"reputation": 8, "will_to_live": -8, "technical_debt": 6}
		ach = "he_remembered"
	elif friday == "" and refactor == "promoted":
		line = "\"Your agent has requested headcount.\"\n\nHe says this the way you would report weather. \"I've approved it. It presents well. It's already scheduled a 1:1 with me.\""
		reward = {"reputation": 12, "technical_debt": 18}
		ach = "he_remembered"
	var choice := {"text": "Nod at the appropriate moments", "effects": reward, "next": -1}
	if ach != "":
		choice["achievement"] = ach
	return [
		{
			"title": "THE SVP REMEMBERS",
			"description": "He has found you in a corridor, which is the only place he does his actual management.\n\n%s" % line,
			"choices": [choice],
		},
	]

## The client from "Just One Tiny Change" is back. It has been an hour of your
## life and roughly forty of theirs.
static func client_remembers() -> Array:
	return [
		{  # 0
			"title": "RE: RE: RE: quick one",
			"description": "From: The Client\nSubject: re: re: re: quick one\n\n\"Hey! Loving the app. Quick one — do you still have those horse buttons anywhere? Marketing saw a screenshot and they're obsessed.\"",
			"choices": [
				{"text": "\"They were a bug.\"", "next": 1},
				{"text": "Ship the horses. Officially. As a feature.", "next": 2},
				{"text": "Do not reply", "next": 3},
			],
		},
		{  # 1
			"title": "\"CAN WE KEEP THE BUG?\"",
			"description": "\"Totally understood! Is there any way to keep the bug though? Just for the campaign. Just for six weeks.\"\n\nThe campaign will run for three years.",
			"choices": [
				{"text": "Reintroduce the bug deliberately", "effects": {"tokens": 220, "technical_debt": 24, "will_to_live": -8}, "achievement": "the_horses_came_back", "next": -1},
			],
		},
		{  # 2
			"title": "HORSES: GA",
			"description": "You shipped it as a documented feature with a flag, a doc page and a name. It is now the second most used thing in the product.\n\nThe most used thing is the login form. That is the entire product.",
			"choices": [
				{"text": "Bill for the horses", "effects": {"tokens": 420, "reputation": 16, "technical_debt": 10}, "achievement": "the_horses_came_back", "next": -1},
			],
		},
		{  # 3
			"title": "NINE DAYS LATER",
			"description": "They found the screenshot in an old deck and rebuilt the horses themselves, badly, in production, using a browser extension.\n\nThey are extremely happy. Nobody has told them it is a browser extension.",
			"choices": [
				{"text": "Never tell them", "effects": {"will_to_live": 10, "reputation": -6, "stability": -6}, "next": -1},
			],
		},
	]

## The maintainer heard what you did during the licence audit.
static func maintainer_remembers() -> Array:
	var licence := str(EventManager.recall("licence", "")) if EventManager else ""
	var opened := licence == "opened"
	var body := "\"Somebody vendored my library into a private repo and renamed the functions. It's fine. It's MIT. It's fine.\"\n\nHe says 'it's fine' twice, which is once more than a person says it when it is fine."
	var reward := {"reputation": 8, "will_to_live": -4}
	if opened:
		body = "\"You open-sourced the whole thing to close an audit.\"\n\nA very long pause. \"That's the stupidest, most beautiful compliance strategy I've ever heard. I've starred it. That's the highest form of payment I have.\""
		reward = {"reputation": 24, "will_to_live": 12}
	return [
		{
			"title": "THE MAINTAINER HEARD",
			"description": body,
			"choices": [
				{"text": "Sponsor him properly (50 tk)", "effects": {"tokens": -50, "reputation": 20, "will_to_live": 8}, "achievement": "dave_gives_three_dollars", "next": -1},
				{"text": "Just say thank you", "effects": reward, "achievement": "nine_days_of_noodles", "next": -1},
			],
		},
	]

## The dark-launched flag from the Friday deploy has developed a personality.
static func the_flag_remembers() -> Array:
	return [
		{
			"title": "NEW_CHECKOUT_V2_TEMP_DO_NOT_REMOVE",
			"description": "The flag you shipped dark is now referenced in 41 places, three of them in the billing path.\n\nIt has never been turned on. Removing it breaks production. Turning it on also breaks production. It is a load-bearing `false`.",
			"choices": [
				{"text": "Delete the flag", "stability_gamble": true, "next_success": 1, "next_fail": 2},
				{"text": "Leave it. Document it. Fear it.", "effects": {"technical_debt": 16, "stability": 6}, "achievement": "the_file_named_temp", "next": -1},
			],
		},
		{
			"title": "IT CAME OUT CLEAN",
			"description": "41 references, one commit, zero incidents. Nobody noticed. Nobody will ever notice.\n\nThis is the best work you have done all quarter and it is invisible by design.",
			"choices": [
				{"text": "Log off at a reasonable hour", "effects": {"stability": 20, "technical_debt": -18, "will_to_live": 10}, "next": -1},
			],
		},
		{
			"title": "IT WAS LOAD-BEARING",
			"description": "Three of the 41 references read the flag to decide whether to charge VAT.\n\nYou have just made every European order tax-free for eleven minutes. Finance found out before monitoring did.",
			"choices": [
				{"text": "Restore the `false`", "effects": {"stability": -20, "technical_debt": 20, "tokens": -150}, "next": -1},
			],
		},
	]

## Dispatcher so EventManager can start any saga or callback by id.
static func by_id(id: String) -> Array:
	match id:
		"tiny_change": return tiny_change()
		"free_tier": return free_tier()
		"debugging_investigation": return debugging_investigation()
		"production_incident": return production_incident()
		"all_hands_demo": return all_hands_demo()
		"autonomous_agent": return autonomous_agent()
		"agent_menu": return agent_menu()
		"friday_deploy": return friday_deploy()
		"oncall_pager": return oncall_pager()
		"five_minute_fix": return five_minute_fix()
		"license_audit": return license_audit()
		"runaway_refactor": return runaway_refactor()
		"stakeholder_demo": return stakeholder_demo()
		"subscription_reckoning": return subscription_reckoning()
		"svp_remembers": return svp_remembers()
		"client_remembers": return client_remembers()
		"maintainer_remembers": return maintainer_remembers()
		"the_flag_remembers": return the_flag_remembers()
		_: return []
