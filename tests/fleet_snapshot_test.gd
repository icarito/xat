extends SceneTree

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const Snapshot = preload("res://fleet_snapshot.gd")
const Monitor = preload("res://fleet_monitor.gd")

func _init() -> void:
	var xml = '<monitoring xmlns="urn:joework:monitoring:2" version="2" scope="team" generated-at="2020-01-01T00:00:00Z"><instance id="gw-1" state="running"><team>Gateway</team><entity-kind>gateway</entity-kind><lifecycle>active</lifecycle><health>ready</health><metrics><metric name="cost" value="12.50" currency="USD"/></metrics><operational><field name="queue_depth">3</field></operational></instance><instance id="svc-1"><team>API</team><entity-kind>service</entity-kind><lifecycle>active</lifecycle><health>degraded</health></instance><instance id="svc-2"><team>Worker</team><entity-kind>service</entity-kind><lifecycle>active</lifecycle><health>down</health></instance><instance id="svc-3"><team>Scheduler</team><entity-kind>service</entity-kind><lifecycle>active</lifecycle><health>unknown</health></instance><instance id="agent-1"><team>Mateo</team><entity-kind>agent</entity-kind><lifecycle>hibernated</lifecycle><health>hibernated</health><metrics/><operational/></instance></monitoring>'
	var root = Stanza.parse(xml)
	var parsed = Snapshot.parse(root)
	check(parsed["stale"], "old timestamp is marked stale")
	check(parsed["entities"].size() == 5, "all instances are kept without requiring JIDs")
	var states := []
	for entity in parsed["entities"]: states.append(entity["status"])
	check(states == ["ready", "degraded", "down", "unknown", "hibernated"], "projection health and hibernation states are preserved distinctly")
	check(parsed["operations"].size() == 1 and parsed["operations"][0]["fields"]["queue_depth"] == "3", "operational fields are parsed")
	check(parsed["cost"].size() == 1 and parsed["cost"][0]["value"] == "12.50", "cost metrics are parsed")
	OS.exit_code = 1 if _failed else 0
	quit()

var _failed := false

func check(p_ok: bool, p_message: String) -> void:
	if p_ok:
		print("ok ", p_message)
	else:
		_failed = true
		print("FAIL ", p_message)
