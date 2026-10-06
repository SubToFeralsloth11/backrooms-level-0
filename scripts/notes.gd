class_name Notes
extends RefCounted
## Journal pages left by the previous wanderer. Clue lines come from Puzzle.

static func intro() -> String:
	return "\n\n".join([
		"Day ? - I stopped counting.",
		"If you are reading this you fell through too. Listen to me. DON'T RUN. The tall one has no eyes. It hears you. Walk slow. Crouch when it clicks. Throw something and it goes to the noise instead.",
		"There is a door. Steel. South side, past the room with the dead lights. It wants power and a number. I found the power. Breakers in the dark wing, east. Don't guess them. Guessing is what got Daniel killed.",
		"I wrote down what the wiring taught me. Four pages. I hid them. All four matter.",
	])


static func clue(i: int, lines: Array) -> String:
	var heads := [
		"Breakers. Page one.\nI count them left to right, like reading.",
		"Breakers. Page two.\nBurned my hand learning this.",
		"Breakers. Page three.\nThe lights went out twice before I got this right.",
		"Breakers. Page four.\nThe smiling thing lives here in the dark.\nKeep the light ON it. Don't look away.",
	]
	var tails := [
		"\n\nThe others are on the other pages.",
		"\n\nSomething was walking behind me the whole time.",
		"\n\nIf you pull the big lever wrong it ALL goes black.\nIt hears the lever. Every time.",
		"\n\nThe batteries don't last. Mine are dying.",
	]
	var body := ""
	for l in lines:
		body += "\n\n- " + str(l)
	return heads[i % heads.size()] + body + tails[i % tails.size()]


static func breaker() -> String:
	return "\n\n".join([
		"I did it. The lights by the door came on. Then the new one came. It moves when you don't watch it. You can hear its bones.",
		"The door asks in shapes, not numbers. The walls remember the numbers - each one painted beside its shape.",
		"Some of them are OLD. Brown, dried, flaking. Someone before me. They lie. Only trust the red ones that are still wet and running. The red is mine.",
		"Three wrong and it screams for them.",
		"I'm going back for the last one. If I don't",
	])


## My own page: every painted symbol/number I have looked at. entries: {symbol, digit, fresh}
static func codes(entries: Array) -> String:
	var body := "Numbers on the walls. What I saw, where I saw it."
	for e in entries:
		body += "\n\n- %s : %d   (%s)" % [Puzzle.SYMBOL_NAMES[e.symbol], e.digit, "red, wet" if e.fresh else "brown, dry"]
	return body
