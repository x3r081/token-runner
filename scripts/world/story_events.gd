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
