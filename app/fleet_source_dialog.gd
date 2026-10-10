extends ConfirmationDialog

signal source_saved(jid, node)

var _jid: LineEdit
var _node: LineEdit

func _init() -> void:
	window_title = "Fuente de monitoreo"
	var fields = VBoxContainer.new()
	fields.add_constant_override("separation", 8)
	add_child(fields)
	var hint = Label.new()
	hint.text = "Cuenta XMPP que publica el estado por XEP-0060.\nLa cuenta conectada debe tener acceso al nodo."
	fields.add_child(hint)
	fields.add_child(_label("JID del publicador"))
	_jid = LineEdit.new()
	_jid.placeholder_text = "operator@example.org"
	_jid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_jid)
	fields.add_child(_label("Nodo PubSub"))
	_node = LineEdit.new()
	_node.placeholder_text = "nombre/del/nodo"
	fields.add_child(_node)
	connect("confirmed", self, "_on_confirmed")

func open(p_jid: String, p_node: String) -> void:
	_jid.text = p_jid
	_node.text = p_node
	popup_centered(Vector2(440, 0))
	_jid.grab_focus()

func _label(p_text: String) -> Label:
	var label = Label.new()
	label.text = p_text
	return label

func _on_confirmed() -> void:
	emit_signal("source_saved", _jid.text.strip_edges(), _node.text.strip_edges())
