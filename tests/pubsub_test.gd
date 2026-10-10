extends SceneTree

# XEP-0060: builders y lectura genérica de resultados/eventos sin interpretar payloads.

var _fail := 0

func _init():
	var PubSub = load("res://addons/xat_xmpp/xmpp/pubsub.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var request = PubSub.build_items_request("i1", "pub.example", "news", 25)
	var xml = request.to_xml()
	check(xml.find('type="get"') >= 0 and xml.find('to="pub.example"') >= 0, "items request IQ")
	check(xml.find('node="news"') >= 0 and xml.find('<max>25</max>') >= 0, "items node y límite RSM")
	var subscribe = PubSub.build_subscribe("i2", "pub.example", "news", "me@example/res")
	check(subscribe.to_xml().find('<subscribe node="news" jid="me@example/res"/>') >= 0, "subscribe incluye node y subscriber")

	var result = Stanza.parse('<iq type="result" from="pub.example" id="i1"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="news"><item id="n1"><entry xmlns="urn:example:news"><title>hello</title></entry></item><item id="n2"/></items></pubsub></iq>')
	var parsed = PubSub.parse_items_result(result)
	check(parsed["node"] == "news" and parsed["items"].size() == 2, "parsea lista y nodo")
	check(parsed["items"][0]["id"] == "n1" and parsed["items"][0]["payload"].name == "entry", "preserva id y payload XML")
	check(parsed["items"][1]["payload"] == null, "admite item vacío")

	var event = Stanza.parse('<message from="pub.example/res"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="news"><item id="n3"><entry xmlns="urn:example:news">world</entry></item></items></event></message>')
	var ev = PubSub.parse_event(event)
	check(ev["kind"] == "items" and ev["node"] == "news" and ev["items"][0]["id"] == "n3", "parsea evento items")
	var deleted = PubSub.parse_event(Stanza.parse('<message><event xmlns="http://jabber.org/protocol/pubsub#event"><delete node="news"><redirect uri="other"/></delete></event></message>'))
	check(deleted["kind"] == "delete" and deleted["redirect"] == "other", "parsea evento delete")
	check(PubSub.parse_event(Stanza.parse('<message/>'))["kind"] == "", "ignora mensaje sin evento pubsub")

	if _fail == 0:
		print("PUBSUB_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
