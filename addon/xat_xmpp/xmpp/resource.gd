extends Reference

# Recurso XMPP estable por dispositivo. Prosody (y otros) mantienen una sesión
# por (bare JID, resource) y con un resource distinto en cada arranque acumulan
# sesiones zombie hasta el timeout. Se persiste un sufijo aleatorio de 8 chars
# base36 y se compone `<base>-<sufijo>`.

const _ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyz"
const LENGTH := 8

# Determinista para un mismo seed (testeable).
static func generate(p_seed: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p_seed)
	var out := ""
	for _i in range(LENGTH):
		out += _ALPHABET[rng.randi_range(0, _ALPHABET.length() - 1)]
	return out

# Lee el sufijo persistido en `p_path`; si no existe, lo genera y guarda.
func load_or_create(p_path: String) -> String:
	var f := File.new()
	if f.file_exists(p_path):
		if f.open(p_path, File.READ) == OK:
			var saved = f.get_as_text().strip_edges()
			f.close()
			if saved != "":
				return saved
	var suffix = generate(str(OS.get_unix_time()) + ":" + str(OS.get_ticks_usec()))
	var w := File.new()
	if w.open(p_path, File.WRITE) == OK:
		w.store_string(suffix)
		w.close()
	return suffix

static func compose(p_base: String, p_suffix: String) -> String:
	return p_base + "-" + p_suffix

# Full JID estable: `bare/<base>-<sufijo>` (p. ej. a@b/xat-abcd1234).
static func full_jid(p_bare: String, p_base: String, p_suffix: String) -> String:
	return p_bare + "/" + compose(p_base, p_suffix)
