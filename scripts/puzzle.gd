class_name Puzzle
extends RefCounted
## Seeded puzzle state for one run.
##  * Breakers: 6 switches. A minimal set of logic clues (split over 4 notes) pins
##    exactly one up/down pattern. Every clue is necessary, so every note is needed.
##  * Keypad: 6 digits. Each digit is written in fresh blood next to a symbol;
##    the keypad screen shows the symbol order once powered. Old brown writings lie.

const N := 6
const ORD := ["first", "second", "third", "fourth", "fifth", "sixth"]
const CLUE_NOTES := 4
const SYMBOL_COUNT := 6
## Journal names for textures/symbols/sym_N.png.
const SYMBOL_NAMES := ["eye", "triangle", "spiral", "ladder", "crossed circle", "fork"]

var rng := RandomNumberGenerator.new()
var target_mask := 0
var clues: Array[Dictionary] = []
var note_clues: Array = []  # Array[Array[String]], one per clue note
var code: Array[int] = []  # digit per symbol index, code[s] = digit painted beside symbol s
var symbol_order: Array[int] = []  # order shown on keypad screen
var decoys: Array[Dictionary] = []  # {symbol, digit}
var ok := false  # breaker clue generation succeeded


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	_gen_breakers()
	_gen_code()


func bit(mask: int, i: int) -> int:
	return (mask >> i) & 1


func eval_clue(c: Dictionary, m: int) -> bool:
	var a: Array = c.args
	match c.type:
		"diff": return bit(m, a[0]) != bit(m, a[1])
		"same": return bit(m, a[0]) == bit(m, a[1])
		"imp": return bit(m, a[0]) != a[2] or bit(m, a[1]) == a[3]
		"count3": return bit(m, a[0]) + bit(m, a[1]) + bit(m, a[2]) == a[3]
		"atmost1": return bit(m, a[0]) + bit(m, a[1]) <= 1
		"atleast1": return bit(m, a[0]) + bit(m, a[1]) >= 1
	return false


func clue_text(c: Dictionary) -> String:
	var a: Array = c.args
	var ud := func(v: int) -> String: return "up" if v == 1 else "down"
	match c.type:
		"diff": return "The %s and the %s never agree. When one is up the other is down." % [ORD[a[0]], ORD[a[1]]]
		"same": return "The %s and the %s move together. Always together." % [ORD[a[0]], ORD[a[1]]]
		"imp": return "If the %s is %s, then the %s has to be %s." % [ORD[a[0]], ud.call(a[2]), ORD[a[1]], ud.call(a[3])]
		"count3":
			var n_words := ["none", "only one", "exactly two", "all three"]
			return "Of the %s, the %s and the %s: %s up." % [ORD[a[0]], ORD[a[1]], ORD[a[2]], n_words[a[3]]]
		"atmost1": return "Never the %s and the %s up at the same time. It burned me." % [ORD[a[0]], ORD[a[1]]]
		"atleast1": return "The %s or the %s. One of them must be up, maybe both." % [ORD[a[0]], ORD[a[1]]]
	return ""


func solutions(clue_set: Array) -> Array[int]:
	var out: Array[int] = []
	for m in 1 << N:
		var ok := true
		for c in clue_set:
			if not eval_clue(c, m):
				ok = false
				break
		if ok:
			out.append(m)
	return out


func _random_clue() -> Dictionary:
	var idx := range(N)
	_shuffle(idx)
	var types := ["diff", "same", "imp", "imp", "count3", "count3", "atmost1", "atleast1"]
	var t: String = types[rng.randi() % types.size()]
	var c := {"type": t, "args": []}
	match t:
		"diff", "same", "atmost1", "atleast1":
			c.args = [idx[0], idx[1]]
		"imp":
			c.args = [idx[0], idx[1], rng.randi() % 2, rng.randi() % 2]
		"count3":
			c.args = [idx[0], idx[1], idx[2], 0]
			c.args[3] = bit(target_mask, idx[0]) + bit(target_mask, idx[1]) + bit(target_mask, idx[2])
	return c


func _gen_breakers() -> void:
	for attempt in 500:
		target_mask = rng.randi_range(1, (1 << N) - 2)
		var chosen: Array = []
		var remaining := solutions(chosen).size()
		var guard := 0
		while remaining > 1 and guard < 400:
			guard += 1
			var c := _random_clue()
			if not eval_clue(c, target_mask):
				continue
			var trial := chosen.duplicate()
			trial.append(c)
			var r := solutions(trial).size()
			# Reject clues that solve too much at once: keeps every note load-bearing.
			if r < remaining and (remaining - r) <= max(remaining / 2, 2):
				chosen = trial
				remaining = r
		if remaining != 1:
			continue
		# Prune to a minimal set: every remaining clue is necessary.
		var order := range(chosen.size())
		_shuffle(order)
		var pruned := chosen.duplicate()
		for i in order:
			var c: Dictionary = chosen[i]
			var trial := pruned.duplicate()
			trial.erase(c)
			if solutions(trial).size() == 1:
				pruned = trial
		if pruned.size() < CLUE_NOTES + 2 or pruned.size() > 10:
			continue
		clues.assign(pruned)
		_shuffle(clues)
		note_clues = []
		for n in CLUE_NOTES:
			note_clues.append([])
		for i in clues.size():
			note_clues[i % CLUE_NOTES].append(clue_text(clues[i]))
		ok = true
		return
	push_warning("breaker puzzle generation failed; level will regenerate")


func _gen_code() -> void:
	code.clear()
	for s in SYMBOL_COUNT:
		code.append(rng.randi_range(0, 9))
	symbol_order.assign(range(SYMBOL_COUNT))
	_shuffle(symbol_order)
	decoys.clear()
	var syms := range(SYMBOL_COUNT)
	_shuffle(syms)
	for i in 3:
		var s: int = syms[i]
		var d := (code[s] + rng.randi_range(1, 9)) % 10
		decoys.append({"symbol": s, "digit": d})


func code_string() -> String:
	var out := ""
	for s in symbol_order:
		out += str(code[s])
	return out


func mask_matches(switches: Array) -> bool:
	for i in N:
		if int(switches[i]) != bit(target_mask, i):
			return false
	return true


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
