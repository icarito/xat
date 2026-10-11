extends SceneTree

# Registro en banda XMPP (XEP-0077): modelo puro (descubrir, enviar, parsear).

var _fail := 0

func _init():
	var R = load("res://addons/xat_xmpp/xmpp/registration.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# Feature del stream.
	var features = Stanza.parse('<stream:features xmlns:stream="http://etherx.jabber.org/streams">'
		+ '<register xmlns="http://jabber.org/features/iq-register"/></stream:features>')
	check(R.supports_registration(features), "feature: registro anunciado")
	check(not R.supports_registration(Stanza.parse('<stream:features xmlns:stream="http://etherx.jabber.org/streams"/>')), "feature: sin registro")

	# Descubrimiento.
	var get_iq = R.build_discover_iq("r1", "hablar.fuentelibre.org")
	check(get_iq.get_attr("type") == "get" and get_iq.get_attr("to") == "hablar.fuentelibre.org", "discover: atributos")
	check(get_iq.get_child("query", "jabber:iq:register") != null, "discover: query ns")

	# Envío.
	var set_iq = R.build_register_iq("r2", "hablar.fuentelibre.org", {"username": "ana", "password": "secreto"})
	var q = set_iq.get_child("query", "jabber:iq:register")
	check(set_iq.get_attr("type") == "set" and q.get_child("username").get_text() == "ana", "register: campos")
	check(q.get_child("password").get_text() == "secreto", "register: contraseña")

	# Respuesta con formulario (get) -> instrucciones y campos.
	var form = R.parse(Stanza.parse('<iq type="result" id="r1"><query xmlns="jabber:iq:register">'
		+ '<instructions>Elegí un usuario y contraseña</instructions>'
		+ '<username/><password/><email/></query></iq>'))
	check(form["ok"] and form["instructions"].find("usuario") >= 0, "parse: instrucciones")
	check(R.field_names(form) == ["username", "password", "email"], "parse: campos del formulario")

	# Resultado exitoso a un set.
	var ok = R.parse(Stanza.parse('<iq type="result" id="r2"><query xmlns="jabber:iq:register"/></iq>'))
	check(ok["ok"] and not ok["registered"], "parse: registro enviado")

	# `registered` cuando la cuenta ya existe.
	var already = R.parse(Stanza.parse('<iq type="result" id="r1"><query xmlns="jabber:iq:register"><registered/></query></iq>'))
	check(already["registered"], "parse: cuenta ya registrada")

	# Error estándar (conflict = usuario tomado).
	var err = R.parse(Stanza.parse('<iq type="error" id="r2"><query xmlns="jabber:iq:register"/>'
		+ '<error type="cancel"><conflict xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>'
		+ '<text>Username already taken</text></error></iq>'))
	check(err["error"] == "conflict" and err["error_text"] == "Username already taken", "parse: error con condición y texto")

	if _fail == 0:
		print("REGISTRATION_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
