extends SceneTree

# Parseo del roster `jabber:iq:roster`.

var _fail := 0

func _init():
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var Roster = load("res://addons/xat_xmpp/xmpp/roster.gd")
	var iq = Stanza.parse('<iq type="result" id="r1"><query xmlns="jabber:iq:roster">' \
		+ '<item jid="agente@hablar.fuentelibre.org" name="Agente" subscription="both">' \
		+ '<group>OpenClaw</group><group>Agentes</group></item>' \
		+ '<item jid="otro@hablar.fuentelibre.org" subscription="to"/>' \
		+ '</query></iq>')
	check(iq != null, "parse roster iq")

	var r = Roster.new()
	r.apply_roster_result(iq)
	check(r.bare_jids().size() == 2, "dos items")
	var a = r.get_item("agente@hablar.fuentelibre.org")
	check(a != null and a["name"] == "Agente", "nombre")
	check(a["subscription"] == "both", "suscripción")
	check(a["groups"] == ["OpenClaw", "Agentes"], "grupos")
	var o = r.get_item("otro@hablar.fuentelibre.org")
	check(o != null and o["subscription"] == "to" and o["groups"].empty(), "item sin nombre/grupos")

	r.remove_item("otro@hablar.fuentelibre.org")
	check(r.bare_jids().size() == 1, "remove item")

	# Item sin jid se ignora.
	var iq2 = Stanza.parse('<iq type="result"><query xmlns="jabber:iq:roster"><item/></query></iq>')
	var r2 = Roster.new()
	r2.apply_roster_result(iq2)
	check(r2.bare_jids().empty(), "item sin jid ignorado")

	if _fail == 0:
		print("ROSTER_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
