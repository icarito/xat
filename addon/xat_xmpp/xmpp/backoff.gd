extends Reference

# Backoff de reconexión: min(cap, 2^min(intento,5)) segundos, como en
# gtk-llm-chat. Helper puro, testeable headless.
# Se usa una tabla en vez de `1 << n` porque `exp` choca con la función
# incorporada de GDScript.

const SCHEDULE := [1, 2, 4, 8, 16, 32]

static func delay_for_attempt(p_attempt: int, p_cap: int = 60) -> int:
	var idx = p_attempt
	if idx < 0:
		idx = 0
	if idx >= SCHEDULE.size():
		idx = SCHEDULE.size() - 1
	var d = SCHEDULE[idx]
	if d > p_cap:
		return p_cap
	return d
