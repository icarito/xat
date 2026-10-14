extends SceneTree

# X6.1 costo honesto: fmt_cost nunca muestra "$0.0000"; 0/ausente -> "sin tarifa".

var _fail := 0

func _init():
	var Mind = load("res://addons/xat_xmpp/ui/mind_panel.gd")
	check(Mind.fmt_cost(0.0) == "sin tarifa", "usd 0 -> sin tarifa")
	check(Mind.fmt_cost(0) == "sin tarifa", "usd 0 (int) -> sin tarifa")
	check(Mind.fmt_cost(null) == "sin tarifa", "usd ausente -> sin tarifa")
	check(Mind.fmt_cost("") == "sin tarifa", "usd vacío -> sin tarifa")
	check(Mind.fmt_cost("0") == "sin tarifa", "usd \"0\" -> sin tarifa")
	check(Mind.fmt_cost(0.0, false).begins_with("sin tarifa"), "sin tarifa con nota si el modelo no publica precio")
	check(Mind.fmt_cost(0.0, false) != Mind.fmt_cost(0.0), "la nota aclara que no hay precio publicado")
	check(Mind.fmt_cost(0.004) == "$0.0040", "valor real -> formato USD")
	check(Mind.fmt_cost(1.5) == "$1.5000", "valor real entero -> formato USD")
	check(Mind.fmt_cost("0.25") == "$0.2500", "valor real como string -> formato USD")
	check(Mind.fmt_cost(0.00001) == "<$0.0001", "valores bajo el redondeo no se muestran como cero")
	check(Mind.fmt_cost(0.0001) == "$0.0001", "el mínimo representable se muestra")
	check(not ("$0.0000" in [Mind.fmt_cost(0.0), Mind.fmt_cost(0.0, false), Mind.fmt_cost(null), Mind.fmt_cost(0.00001)]), "nunca \"$0.0000\"")
	print("DONE fail=%d" % _fail)
	OS.exit_code = 1 if _fail > 0 else 0
	quit()

func check(p_cond: bool, p_msg: String) -> void:
	if p_cond:
		print("ok   ", p_msg)
	else:
		print("FAIL ", p_msg)
		_fail += 1
