extends Reference

# Normalización de stanzas/objetivos (openclaw-xmpp src/normalize.ts +
# src/protocol.ts). Puro, testeable headless.

const MAX_BODY := 4000

static func bare_jid(p_jid: String) -> String:
	var slash = p_jid.find("/")
	if slash < 0:
		return p_jid
	return p_jid.substr(0, slash)

# Grupo/MUC: el bare (minúsculas) termina en "@<muc_domain>".
static func is_group_jid(p_jid: String, p_muc_domain: String) -> bool:
	if p_muc_domain == "":
		return false
	return bare_jid(p_jid).to_lower().ends_with("@" + p_muc_domain.to_lower())

# ^[^\s@/]+@[^\s@/]+(\/[^\s]*)?$
static func looks_like_xmpp_target_id(p_text: String) -> bool:
	var slash = p_text.find("/")
	var head = p_text if slash < 0 else p_text.substr(0, slash)
	if head.find(" ") >= 0 or head.find("/") >= 0:
		return false
	var at = head.find("@")
	if at <= 0 or at >= head.length() - 1:
		return false
	var local = head.substr(0, at)
	var domain = head.substr(at + 1)
	return local.find("@") < 0 and domain.find("@") < 0

# Quita prefijos xmpp:/channel:/user: y devuelve el JID.
static func normalize_messaging_target(p_text: String) -> String:
	var s = p_text.strip_edges()
	for prefix in ["xmpp:", "channel:", "user:"]:
		if s.to_lower().begins_with(prefix):
			s = s.substr(prefix.length())
			break
	return s

# Corta un cuerpo largo respetando el límite XMPP. Prefiere \n\n, luego \n,
# luego espacio, y si no hay, corte duro.
static func split_for_limit(p_text: String, p_limit: int = MAX_BODY) -> Array:
	if p_text.length() <= p_limit:
		return [p_text]
	var out := []
	var remaining = p_text
	while remaining.length() > p_limit:
		var cut = remaining.rfind("\n\n", p_limit)
		if cut <= 0:
			cut = remaining.rfind("\n", p_limit)
		if cut <= 0:
			cut = remaining.rfind(" ", p_limit)
		if cut <= 0:
			cut = p_limit
		out.append(remaining.substr(0, cut))
		remaining = remaining.substr(cut).lstrip("\n")
	if remaining != "":
		out.append(remaining)
	return out

# Markdown -> texto plano (para fallback/notificaciones).
static func markdown_to_plain(p_text: String) -> String:
	var s = p_text
	# Quita fences ```[lang]\n ... ``` dejando el contenido.
	var fence = RegEx.new()
	fence.compile("```[^\\n`]*\\n?([\\s\\S]*?)\\n?```")
	s = _sub_all(fence, s, "$1")
	var bold = RegEx.new()
	bold.compile("\\*\\*([^*]+)\\*\\*")
	s = _sub_all(bold, s, "$1")
	var ital = RegEx.new()
	ital.compile("\\*([^*]+)\\*")
	s = _sub_all(ital, s, "$1")
	var strike = RegEx.new()
	strike.compile("~~([^~]+)~~")
	s = _sub_all(strike, s, "$1")
	var code = RegEx.new()
	code.compile("`([^`]+)`")
	s = _sub_all(code, s, "$1")
	var link = RegEx.new()
	link.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	s = _sub_all(link, s, "$1 ($2)")
	return s

# Recupera la URL de un cuerpo que trae literal <x xmlns='jabber:x:oob'>.
static func extract_oob_url(p_body: String) -> String:
	if p_body.find("jabber:x:oob") < 0:
		return ""
	var open = p_body.find("<url>")
	if open < 0:
		return ""
	var close = p_body.find("</url>", open)
	if close < 0:
		return ""
	return p_body.substr(open + 5, close - open - 5)

static func strip_inline_oob_markup(p_body: String) -> String:
	var url = extract_oob_url(p_body)
	if url == "":
		return p_body
	return url

static func _sub_all(p_regex: RegEx, p_text: String, p_replacement: String) -> String:
	var out := ""
	var start := 0
	while true:
		var m = p_regex.search(p_text, start)
		if m == null:
			out += p_text.substr(start)
			break
		out += p_text.substr(start, m.get_start() - start)
		out += p_regex.sub(m.get_string(), p_replacement, false)
		start = m.get_end()
		if m.get_end() == m.get_start():
			start += 1
	return out
