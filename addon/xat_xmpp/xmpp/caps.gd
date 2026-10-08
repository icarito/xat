extends Reference

# XEP-0115 (Entity Capabilities) y detección de agentes OpenClaw. Puro.
#
# Ojo: el `ver` de OpenClaw se calcula como base64(sha1(string)) — NO es el
# sha1 hex estándar. El string de verificación es:
#   `<category>/<type>//<name><` seguido de cada `<feature><` (features
#   ordenadas). Notar el `//` vacío entre type y name.

const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

const OPENCLAW_NODE := "https://github.com/openclaw/openclaw"
const AGENT_FEATURES := [
	NS.COMMANDS,
	"urn:openclaw:telemetry:0+notify",
]

# Caps propias de xat. El `ver` es OPACO (no es el sha1 real): Prosody no lo
# valida y un ver desconocido hace que pregunte disco#info al resource. Hay que
# subirlo a mano cuando cambian los features (si no, el caché no se invalida).
const XAT_NODE := "https://github.com/icarito/xat"
const XAT_VER := "v2-xat-telemetry-hooks-avatar-chatstates"
const XAT_FEATURES := [
	NS.DISCO_INFO,
	NS.COMMANDS,
	"urn:openclaw:telemetry:0+notify",
	NS.HOOKS_ACTIVITY + "+notify",
	NS.HOOKS_APPROVAL + "+notify",
	NS.HOOKS_PROGRESS + "+notify",
	NS.AVATAR_METADATA + "+notify",
	NS.CHATSTATES,
]

# <c xmlns='...caps' hash='sha-1' node ver/> para la presencia inicial.
static func build_caps_child():
	var c = Stanza.new("c")
	c.set_attr("xmlns", NS.CAPS)
	c.set_attr("hash", "sha-1")
	c.set_attr("node", XAT_NODE)
	c.set_attr("ver", XAT_VER)
	return c

# Respuesta a un disco#info dirigido a nuestro node.
static func build_disco_info_result(p_id: String, p_to: String, p_node: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "result")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS.DISCO_INFO)
	if p_node != "":
		query.set_attr("node", p_node)
	var identity = Stanza.new("identity")
	identity.set_attr("category", "client")
	identity.set_attr("type", "pc")
	identity.set_attr("name", "xat")
	query.add_child_stanza(identity)
	for f in XAT_FEATURES:
		var feature = Stanza.new("feature")
		feature.set_attr("var", f)
		query.add_child_stanza(feature)
	iq.add_child_stanza(query)
	return iq

static func parse_caps(p_presence) -> Dictionary:
	var out := {"present": false, "node": "", "hash": "", "ver": ""}
	if p_presence == null:
		return out
	var c = p_presence.get_child("c", NS.CAPS)
	if c == null:
		return out
	out["present"] = true
	out["node"] = c.get_attr("node", "")
	out["hash"] = c.get_attr("hash", "")
	out["ver"] = c.get_attr("ver", "")
	return out

static func verification_string(p_category: String, p_type: String, p_name: String, p_features: Array) -> String:
	var s = p_category + "/" + p_type + "//" + p_name + "<"
	var features = p_features.duplicate()
	features.sort()
	for f in features:
		s += str(f) + "<"
	return s

static func compute_ver(p_category: String, p_type: String, p_name: String, p_features: Array) -> String:
	var s = verification_string(p_category, p_type, p_name, p_features)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(s.to_utf8())
	var digest = ctx.finish()
	return Marshalls.raw_to_base64(digest)

# Un peer es agente si su node es el de OpenClaw o si anuncia los features de
# comando + telemetría.
static func is_agent(p_caps: Dictionary) -> bool:
	if not p_caps.get("present", false):
		return false
	if p_caps.get("node", "") == OPENCLAW_NODE:
		return true
	return false

static func features_mark_agent(p_features: Array) -> bool:
	for f in AGENT_FEATURES:
		if not p_features.has(f):
			return false
	return true
