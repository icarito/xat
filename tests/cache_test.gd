extends SceneTree

# Caches de UI: los recursos pesados (fuentes, miniaturas, Markdown→BBCode) se
# memoizan para no rehacerse al reconstruir el historial/roster.

var _fail := 0

func _init():
	var XatTheme = load("res://addons/xat_xmpp/ui/xat_theme.gd")
	var MediaUtil = load("res://addons/xat_xmpp/ui/media_util.gd")
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")
	var Markdown = load("res://addons/xat_xmpp/xmpp/markdown.gd")

	# --- Fuentes: misma (path, size) -> misma instancia ---
	var f1 = XatTheme.font(XatTheme.Palette.FONT_REGULAR, 15)
	var f2 = XatTheme.font(XatTheme.Palette.FONT_REGULAR, 15)
	check(f1 == f2, "font cache: misma instancia")
	var f3 = XatTheme.font(XatTheme.Palette.FONT_REGULAR, 17)
	check(f1 != f3, "font cache: distinto tamaño -> distinta fuente")
	var f4 = XatTheme.font(XatTheme.Palette.FONT_BOLD, 15)
	check(f1 != f4, "font cache: distinta familia -> distinta fuente")

	# --- Miniaturas: mismo (path, max) -> misma textura ---
	var img = Image.new()
	img.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var path = "user://cache_test.png"
	img.save_png(path)
	var t1 = MediaUtil.load_thumbnail(path, 64)
	var t2 = MediaUtil.load_thumbnail(path, 64)
	check(t1 != null and t1 == t2, "thumb cache: misma instancia")
	var t3 = MediaUtil.load_thumbnail(path, 32)
	check(t3 != null and t3 != t1, "thumb cache: distinto max -> distinta textura")
	check(MediaUtil.load_thumbnail("", 64) == null, "thumb cache: path vacío -> null")
	Directory.new().remove(path)

	# --- Markdown→BBCode: memoizado y consistente ---
	var b1 = Bubble._bbcode("hola **mundo**", null)
	var b2 = Bubble._bbcode("hola **mundo**", null)
	check(b1 == b2 and b1 == Markdown.to_bbcode("hola **mundo**", null), "bbcode cache: consistente")
	check(b1.find("[b]mundo[/b]") >= 0, "bbcode cache: negrita convertida")

	if _fail == 0:
		print("CACHE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
