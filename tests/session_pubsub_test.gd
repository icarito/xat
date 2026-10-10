extends SceneTree

# La sesión expone resultados, errores y eventos PubSub genéricos.

var _fail := 0
var _items := []
var _events := []
var _subs := []
var _errors := []

func _init():
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")
	var s = Session.new()
	var fake = FakeTransport.new()
	s._transport = fake
	s.state = Session.State.CONNECTED
	s._bare = "me@example"
	s.connect("pubsub_items_received", self, "_on_items")
	s.connect("pubsub_event_received", self, "_on_event")
	s.connect("pubsub_subscribed", self, "_on_subscribed")
	s.connect("pubsub_error", self, "_on_error")

	check(s.request_pubsub_items("pub.example", "news", 10) == 0, "request items aceptado")
	var id = _iq_id(fake.sent[0])
	check(fake.sent[0].find('type="get"') >= 0 and fake.sent[0].find('node="news"') >= 0, "emite IQ get de items")
	s._on_stanza('<iq type="result" id="%s" from="pub.example"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="news"><item id="n1"><entry xmlns="urn:example">x</entry></item></items></pubsub></iq>' % id)
	check(_items.size() == 1 and _items[0][0] == "pub.example" and _items[0][1] == "news", "forward resultado y origen")
	check(_items[0][2].size() == 1 and _items[0][2][0]["payload"].name == "entry", "forward items sin asumir payload")

	check(s.subscribe_pubsub("pub.example", "news") == 0, "subscribe aceptado")
	id = _iq_id(fake.sent[1])
	check(fake.sent[1].find('type="set"') >= 0 and fake.sent[1].find('jid="me@example"') >= 0, "emite IQ subscribe para JID local")
	s._on_stanza('<iq type="result" id="%s" from="pub.example"/>' % id)
	check(_subs.size() == 1 and _subs[0][1] == "news", "forward confirmación de suscripción")

	s._on_stanza('<message from="pub.example/res"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="news"><item id="n2"><entry xmlns="urn:example">y</entry></item></items></event></message>')
	check(_events.size() == 1 and _events[0][0] == "pub.example/res" and _events[0][1]["node"] == "news", "forward evento sin reducir from resource")

	check(s.request_pubsub_items("pub.example", "private") == 0, "segundo request items")
	id = _iq_id(fake.sent[2])
	s._on_stanza('<iq type="error" id="%s" from="pub.example"><error type="cancel"><item-not-found xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/></error></iq>' % id)
	check(_errors.size() == 1 and _errors[0][2] == "private", "forward error correlacionado al nodo")
	s.state = Session.State.DISCONNECTED
	check(s.request_pubsub_items("pub.example", "news") == -1, "rechaza request desconectado")
	s.free()
	if _fail == 0:
		print("SESSION_PUBSUB_CHECK_OK")
	quit()

func _on_items(p_from, p_node, p_items):
	_items.append([p_from, p_node, p_items])

func _on_event(p_from, p_event):
	_events.append([p_from, p_event])

func _on_subscribed(p_from, p_node, p_response):
	_subs.append([p_from, p_node, p_response])

func _on_error(p_id, p_from, p_node, p_stanza):
	_errors.append([p_id, p_from, p_node, p_stanza])

func _iq_id(p_xml: String) -> String:
	var start = p_xml.find('id="') + 4
	return p_xml.substr(start, p_xml.find('"', start) - start)

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1

class FakeTransport:
	var sent := []
	func send(p_xml: String) -> int:
		sent.append(p_xml)
		return 0
