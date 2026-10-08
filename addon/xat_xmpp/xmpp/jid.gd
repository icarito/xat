extends Reference

# Parser/representación de un JID XMPP (RFC 6120 §2). Helper puro, testeable
# headless. Se usa `preload`/`const` en vez de `class_name` para no depender de
# registro global y evitar choques con clases nativas.

var node := ""
var domain := ""
var resource := ""
var bare := ""
var full := ""

func parse(raw: String) -> void:
	var s := raw.strip_edges()
	full = s
	var slash := s.find("/")
	if slash >= 0:
		resource = s.substr(slash + 1)
		s = s.substr(0, slash)
	var at := s.find("@")
	if at >= 0:
		node = s.substr(0, at)
		domain = s.substr(at + 1)
	else:
		node = ""
		domain = s
	bare = s
	domain = domain.to_lower()

func is_valid() -> bool:
	return domain != "" and domain.find(" ") < 0

func is_bare() -> bool:
	return resource == ""

func get_bare() -> String:
	return bare

func get_full() -> String:
	return full

func get_domain() -> String:
	return domain
