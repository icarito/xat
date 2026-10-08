extends SceneTree

# Helpers de sesión: recurso estable por dispositivo y backoff de reconexión.

var _fail := 0

func _init():
	var DeviceResource = load("res://addons/xat_xmpp/xmpp/resource.gd")
	var Backoff = load("res://addons/xat_xmpp/xmpp/backoff.gd")

	# generate: 8 chars base36, determinista por seed.
	var a = DeviceResource.generate("seed-1")
	var b = DeviceResource.generate("seed-1")
	var c = DeviceResource.generate("seed-2")
	check(a.length() == 8, "sufijo de 8 chars")
	check(a == b, "determinista por seed")
	check(a != c, "distinto con otra seed")
	var alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
	var only_alphabet = true
	for i in range(a.length()):
		if alphabet.find(a[i]) < 0:
			only_alphabet = false
	check(only_alphabet, "sólo base36")
	check(DeviceResource.compose("xat", "abcd1234") == "xat-abcd1234", "compose")
	check(DeviceResource.full_jid("a@b", "xat", "abcd1234") == "a@b/xat-abcd1234", "full_jid")

	# load_or_create: persiste y relee.
	var path = "user://xat_resource_test"
	var f = File.new()
	if f.file_exists(path):
		Directory.new().remove(path)
	var r = DeviceResource.new()
	var suffix = r.load_or_create(path)
	check(suffix.length() == 8, "persistido")
	check(r.load_or_create(path) == suffix, "relee el mismo sufijo")
	var fr = File.new()
	check(fr.open(path, File.READ) == OK and fr.get_as_text().strip_edges() == suffix, "archivo escrito")
	fr.close()
	Directory.new().remove(path)

	# Backoff: min(60, 2^min(intento,5)).
	check(Backoff.delay_for_attempt(0) == 1, "intento 0 -> 1")
	check(Backoff.delay_for_attempt(1) == 2, "intento 1 -> 2")
	check(Backoff.delay_for_attempt(2) == 4, "intento 2 -> 4")
	check(Backoff.delay_for_attempt(3) == 8, "intento 3 -> 8")
	check(Backoff.delay_for_attempt(4) == 16, "intento 4 -> 16")
	check(Backoff.delay_for_attempt(5) == 32, "intento 5 -> 32")
	check(Backoff.delay_for_attempt(6) == 32, "intento 6 -> tope exponente")
	check(Backoff.delay_for_attempt(20, 10) == 10, "cap personalizado")

	if _fail == 0:
		print("SESSION_HELPERS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
