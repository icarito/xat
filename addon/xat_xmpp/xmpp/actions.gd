extends Reference

# Acciones pendientes (botones inline de OpenClaw): expiración, detección de
# aprobaciones y preferencia de comandos sobre quick responses. Puro.

const PENDING_ACTION_MAX_AGE_MS := 15 * 60 * 1000
const APPROVAL_FALLBACK_MAX_AGE_MS := 30 * 60 * 1000

# Palabras que marcan una acción como aprobación (heurística de texto/label).
const _APPROVAL_WORDS := [
	"allow", "deny", "approve", "reject", "permit", "forbid",
	"permitir", "aprobar", "denegar", "rechazar", "autorizar",
]
# Nodos de comandos que NUNCA son aprobaciones (no deben barrerse).
const _NON_APPROVAL_NODES := ["cmd:reset", "cmd:context", "cmd:compact", "cmd:help", "cmd:status", "cmd:model"]

static func looks_like_approval(p_name: String, p_node: String, p_label: String) -> bool:
	if _NON_APPROVAL_NODES.has(p_node):
		return false
	var haystack = (p_name + " " + p_label + " " + p_node).to_lower()
	for w in _APPROVAL_WORDS:
		if haystack.find(w) >= 0:
			return true
	return false

# Expiración efectiva en ms: `expires-at-ms` si viene; si no, fallback por edad
# desde el timestamp del mensaje (30 min para aprobaciones, 15 min el resto).
static func effective_expiry(p_expires_at_ms: int, p_message_ts_ms: int, p_is_approval: bool) -> int:
	if p_expires_at_ms > 0:
		return p_expires_at_ms
	var base = p_message_ts_ms if p_message_ts_ms > 0 else 0
	var window = APPROVAL_FALLBACK_MAX_AGE_MS if p_is_approval else PENDING_ACTION_MAX_AGE_MS
	return base + window

static func is_expired(p_expiry_ms: int, p_now_ms: int) -> bool:
	return p_now_ms > p_expiry_ms

# En restauración de historial, una acción sin `expires-at-ms` es vieja si
# supera 15 min (no se borra la fila: puede seguir pendiente del lado gateway).
static func is_restored_stale(p_message_ts_ms: int, p_now_ms: int) -> bool:
	if p_message_ts_ms <= 0:
		return false
	return p_now_ms - p_message_ts_ms > PENDING_ACTION_MAX_AGE_MS

# Filtra items vivos. Cada item: {expires_at_ms, name, node, label}.
static func filter_live(p_items: Array, p_now_ms: int, p_message_ts_ms: int) -> Array:
	var out := []
	for item in p_items:
		var approval = looks_like_approval(str(item.get("name", "")), str(item.get("node", "")), str(item.get("label", "")))
		var expiry = effective_expiry(int(item.get("expires_at_ms", 0)), p_message_ts_ms, approval)
		if not is_expired(expiry, p_now_ms):
			out.append(item)
	return out

# Preferir command items sobre quick responses cuando ambos existen.
static func preferred(p_rec: Dictionary):
	var commands = p_rec.get("commands", [])
	if not (commands as Array).empty():
		return {"kind": "command", "item": commands[0]}
	var quick = p_rec.get("quick_responses", [])
	if not (quick as Array).empty():
		return {"kind": "quick-response", "item": quick[0]}
	return null
