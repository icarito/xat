extends AcceptDialog

# Diálogo para invitar a un contacto a una sala MUC. Lista los contactos del
# roster (con búsqueda) y una razón opcional. Emite `submitted(jid, reason)`.

signal submitted(jid, reason)

var _search: LineEdit
var _list: ItemList
var _reason: LineEdit
var _all := [] # [{jid, name}]

func _init() -> void:
	name = "InviteDialog"
	window_title = "Invitar a la sala"
	rect_min_size = Vector2(360, 380)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	add_child(box)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar contacto…"
	_search.connect("text_changed", self, "_filter")
	box.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.rect_min_size = Vector2(0, 220)
	_list.connect("item_activated", self, "_on_activated")
	box.add_child(_list)
	_reason = LineEdit.new()
	_reason.placeholder_text = "Mensaje (opcional)"
	box.add_child(_reason)
	connect("confirmed", self, "_on_confirmed")

func open(p_contacts: Array) -> void:
	_all = []
	for c in p_contacts:
		var jid = str(c.get("jid", c)) if c is Dictionary else str(c)
		if jid == "":
			continue
		var name = str(c.get("name", "")) if c is Dictionary else ""
		_all.append({"jid": jid, "name": name})
	_search.text = ""
	_reason.text = ""
	_filter("")
	popup_centered()

func _filter(p_text: String) -> void:
	var q = p_text.strip_edges().to_lower()
	_list.clear()
	for c in _all:
		if q != "" and str(c["jid"]).to_lower().find(q) < 0 and str(c["name"]).to_lower().find(q) < 0:
			continue
		var label = str(c["jid"]) if str(c["name"]) == "" else "%s (%s)" % [c["name"], c["jid"]]
		_list.add_item(label)
		_list.set_item_metadata(_list.get_item_count() - 1, str(c["jid"]))

func _selected_jid() -> String:
	var sel = _list.get_selected_items()
	if sel.empty():
		return ""
	return str(_list.get_item_metadata(sel[0]))

func _on_activated(_index: int) -> void:
	emit_signal("confirmed")

func _on_confirmed() -> void:
	var jid = _selected_jid()
	if jid == "":
		return
	emit_signal("submitted", jid, _reason.text.strip_edges())