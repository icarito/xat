extends SceneTree

# Fallback OMEMO en inglés de otros clientes -> aviso local (chat y preview).

var _fail := 0

func _init():
	var S = load("res://addons/xat_xmpp/xmpp/session.gd")
	var B = load("res://addons/xat_xmpp/ui/bubble.gd")
	check(S.is_omemo_fallback_body("[This message is OMEMO encrypted]"), "conversations: corchetes")
	check(S.is_omemo_fallback_body("This message is OMEMO encrypted."), "sin corchetes / punto")
	check(S.is_omemo_fallback_body("I sent you an OMEMO encrypted message"), "omemo encrypted en frase")
	check(S.is_omemo_fallback_body("Mensaje cifrado con OMEMO"), "aviso local cuenta como fallback")
	check(not S.is_omemo_fallback_body("hola, ¿todo bien?"), "texto normal no es fallback")
	check(not S.is_omemo_fallback_body(""), "vacío no es fallback")
	check(not S.is_omemo_fallback_body("hablamos de omemo y cifrado en general alguna vez quizá no se"), "texto largo no es fallback")
	check(B.is_omemo_notice("Mensaje cifrado con OMEMO · no se pudo leer"), "notice local")
	check(B.is_omemo_notice("[This message is OMEMO encrypted]"), "notice por fallback en inglés")
	check(not B.is_omemo_notice("hola"), "texto normal no es notice")
	check(B.notice_text("Mensaje cifrado con OMEMO") == "Mensaje cifrado con OMEMO · no se pudo leer", "notice_text legible")
	if _fail == 0:
		print("OMEMO_FALLBACK_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
