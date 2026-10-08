extends Reference

# Agregación de presencia por bare JID entre recursos, siguiendo el patrón
# `_online_resources` de gtk-llm-chat. Helper puro, testeable headless.
#
# Regla:
#  - Un bare JID está "online" si algún recurso está disponible.
#  - El recurso "mejor" es el disponible con mayor prioridad; a igual
#    prioridad, el `show` más disponible ("" > chat > away > xa > dnd);
#    a igual show, el primero visto (orden estable).

const SHOW_RANK := {
	"": 4,
	"chat": 3,
	"away": 2,
	"xa": 1,
	"dnd": 0,
}

# full JID -> { bare, show, priority, status, available, seq }
var _resources := {}
# bare JID -> Array de full JIDs en orden de aparición
var _order := {}
var _seq := 0

static func bare_of(p_full: String) -> String:
	var slash := p_full.find("/")
	return p_full if slash < 0 else p_full.substr(0, slash)

func update(p_full: String, p_type: String, p_show: String, p_priority: int, p_status: String) -> void:
	var bare := bare_of(p_full)
	var available := p_type != "unavailable"
	if not _resources.has(p_full):
		if not _order.has(bare):
			_order[bare] = []
		_order[bare].append(p_full)
		_seq += 1
	_resources[p_full] = {
		"full": p_full,
		"bare": bare,
		"show": p_show if p_show != "" else "",
		"priority": p_priority,
		"status": p_status,
		"available": available,
		"seq": _resources[p_full]["seq"] if _resources.has(p_full) else _seq,
	}

func remove(p_full: String) -> void:
	if not _resources.has(p_full):
		return
	var bare = _resources[p_full]["bare"]
	_resources.erase(p_full)
	if _order.has(bare):
		_order[bare].erase(p_full)
		if _order[bare].empty():
			_order.erase(bare)

func is_online(p_bare: String) -> bool:
	if not _order.has(p_bare):
		return false
	for full in _order[p_bare]:
		if _resources.has(full) and _resources[full]["available"]:
			return true
	return false

func best(p_bare: String):
	var candidates := []
	if _order.has(p_bare):
		for full in _order[p_bare]:
			if _resources.has(full) and _resources[full]["available"]:
				candidates.append(full)
	if candidates.empty():
		return null
	var best_full = candidates[0]
	for full in candidates:
		if _better(_resources[full], _resources[best_full]):
			best_full = full
	return _resources[best_full]

func online_bares() -> Array:
	var out := []
	for bare in _order.keys():
		if is_online(bare):
			out.append(bare)
	return out

func _better(a: Dictionary, b: Dictionary) -> bool:
	if a["priority"] != b["priority"]:
		return a["priority"] > b["priority"]
	var ra = SHOW_RANK.get(a["show"], 0)
	var rb = SHOW_RANK.get(b["show"], 0)
	if ra != rb:
		return ra > rb
	return a["seq"] < b["seq"]
