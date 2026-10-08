extends SceneTree

# FX: shader de halo de burbuja + efecto de texto shimmer.

var _fail := 0

func _init():
	var Sh = load("res://addons/xat_xmpp/ui/fx/bubble_glow.shader")
	check(Sh is Shader, "shader cargado")
	check(Sh.code.length() > 0, "shader con código")

	var Shim = load("res://addons/xat_xmpp/ui/fx/shimmer.gd")
	var shim = Shim.new()
	check(shim is RichTextEffect, "shimmer es RichTextEffect")
	check(shim.bbcode == "shimmer", "shimmer bbcode")

	# RichTextLabel con el efecto instalado y el tag en uso.
	var rtl = RichTextLabel.new()
	get_root().add_child(rtl)
	rtl.install_effect(shim)
	check(rtl.custom_effects.size() == 1, "efecto instalado")
	rtl.bbcode_text = "hola [shimmer]mundo[/shimmer]"
	check(rtl.bbcode_text.length() > 0, "bbcode aplicado")
	check(rtl.text.length() > 0, "texto presente")

	# Ejercita los efectos directamente (CharFXTransform manual).
	var cf = CharFXTransform.new()
	cf.elapsed_time = 0.1
	cf.relative_index = 3
	cf.color = Color(1, 1, 1, 1)
	cf.env = {"speed": 2.0, "width": 4.0}
	check(shim._process_custom_fx(cf) == true, "shimmer procesa")

	rtl.free()
	if _fail == 0:
		print("FX_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1