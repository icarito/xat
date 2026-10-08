extends Reference

# Markdown mínimo -> BBCode para RichTextLabel del chat. Puro, testeable.
# Soporta: bloques ```fence```, `código` inline, **negrita**, *cursiva*,
# ~~tachado~~ y [texto](url). Escapa '[' del texto para que no inyecte tags.

const _SENT := "\u0001"

static func to_bbcode(p_text: String, p_inline = null) -> String:
	var store := []
	var out := ""
	var in_code := false
	var buf := ""
	for line in p_text.split("\n"):
		if line.strip_edges().begins_with("```"):
			if in_code:
				out += _sentinel(store, "[code]" + _escape_code(buf.rstrip("\n")) + "[/code]") + "\n"
				buf = ""
				in_code = false
			else:
				in_code = true
			continue
		if in_code:
			buf += line + "\n"
		else:
			out += _inline(line, store, p_inline) + "\n"
	if in_code: # fence sin cerrar
		out += _sentinel(store, "[code]" + _escape_code(buf.rstrip("\n")) + "[/code]") + "\n"
	if out.ends_with("\n"):
		out = out.substr(0, out.length() - 1)

	out = out.replace("[", "[lb]")

	var bold := RegEx.new()
	bold.compile("\\*\\*([^*]+)\\*\\*")
	out = _sub_all(bold, out, "[b]$1[/b]")
	var strike := RegEx.new()
	strike.compile("~~([^~]+)~~")
	out = _sub_all(strike, out, "[s]$1[/s]")
	var ital := RegEx.new()
	ital.compile("\\*([^*]+)\\*")
	out = _sub_all(ital, out, "[i]$1[/i]")

	# El texto de un enlace puede contener un sentinel de emoji: restaurar de fuera
	# hacia dentro (los stores externos se agregan después de sus hijos).
	for i in range(store.size() - 1, -1, -1):
		out = out.replace(_SENT + str(i) + _SENT, store[i])
	return out

static func _inline(p_line: String, p_store: Array, p_inline = null) -> String:
	var o := ""
	var i := 0
	while i < p_line.length():
		var ch = p_line[i]
		if ch == "`":
			var close = p_line.find("`", i + 1)
			if close > i:
				o += _sentinel(p_store, "[code]" + _escape_code(p_line.substr(i + 1, close - i - 1)) + "[/code]")
				i = close + 1
				continue
		elif ch == "[":
			var rb = p_line.find("]", i + 1)
			if rb > i and rb + 1 < p_line.length() and p_line[rb + 1] == "(":
				var rp = p_line.find(")", rb + 2)
				if rp > rb:
					var text = p_line.substr(i + 1, rb - i - 1)
					if p_inline != null:
						text = _escape_code(_inline(text, p_store, p_inline))
					var url = p_line.substr(rb + 2, rp - rb - 2)
					o += _sentinel(p_store, "[url=" + url + "]" + text + "[/url]")
					i = rp + 1
					continue
		if p_inline != null:
			var replacement = p_inline.replacement(p_line, i)
			if not replacement.empty():
				o += _sentinel(p_store, replacement["markup"])
				i += replacement["length"]
				continue
		o += ch
		i += 1
	return o

static func _sentinel(p_store: Array, p_value: String) -> String:
	p_store.append(p_value)
	return _SENT + str(p_store.size() - 1) + _SENT

static func _escape_code(p_text: String) -> String:
	return p_text.replace("[", "[lb]")

# RegEx.sub sólo reemplaza la primera coincidencia por defecto; forzamos todas.
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
