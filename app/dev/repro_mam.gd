extends Control

# Repro: ráfaga de MAM + un mensaje vivo por el camino real (session._on_stanza).

var _m

func _ready() -> void:
	_m = load("res://main.tscn").instance()
	add_child(_m)
	_m._on_state_changed(_m.SessionScript.State.CONNECTED)
	_m._roster.set_peers(["k@h"])
	_m._on_peer_selected("k@h")
	for i in range(5):
		_m.session._on_stanza('<message to="me@h/xat" from="me@h"><result xmlns="urn:xmpp:mam:2" queryid="q1" id="arch%d"><forwarded xmlns="urn:xmpp:forward:0"><delay xmlns="urn:xmpp:delay" stamp="2026-10-07T10:0%d:00Z"/><message xmlns="jabber:client" type="chat" from="k@h/oc" to="me@h" id="oc-%d"><body>Mensaje archivado número %d del agente</body></message></forwarded></result></message>' % [i, i, i, i])
	_m.session._on_stanza('<message type="chat" from="k@h/oc" to="me@h/xat" id="live1"><body>Y este llega en vivo</body></message>')
