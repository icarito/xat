extends SceneTree

# Markdown -> BBCode: negrita, cursiva, tachado, código inline/fence, links,
# y escape de '['.

var _fail := 0

func _init():
	var Md = load("res://addons/xat_xmpp/xmpp/markdown.gd")

	check(Md.to_bbcode("hola **mundo**") == "hola [b]mundo[/b]", "negrita")
	check(Md.to_bbcode("esto es *cursiva*") == "esto es [i]cursiva[/i]", "cursiva")
	check(Md.to_bbcode("~~viejo~~") == "[s]viejo[/s]", "tachado")
	check(Md.to_bbcode("usa `code` acá") == "usa [code]code[/code] acá", "código inline")
	check(Md.to_bbcode("ver [docs](https://x.y/z)") == "ver [url=https://x.y/z]docs[/url]", "link")

	# Fence multilínea; '[' interno se escapa.
	var fenced = Md.to_bbcode("antes\n```\nrm -rf [tmp]\n```\ndespués")
	check(fenced.find("[code]rm -rf [lb]tmp][/code]") >= 0, "fence escapado")
	check(fenced.begins_with("antes\n") and fenced.ends_with("después"), "fence delimita")

	# Texto con '[' literal no rompe tags.
	check(Md.to_bbcode("a [b] no es tag") == "a [lb]b] no es tag", "escape de corchete")

	# Código inline dentro de negrita no se rompe.
	check(Md.to_bbcode("**`x`**") == "[b][code]x[/code][/b]", "code dentro de negrita")

	if _fail == 0:
		print("MARKDOWN_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
