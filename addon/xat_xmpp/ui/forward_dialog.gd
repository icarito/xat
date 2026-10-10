extends AcceptDialog

# Diálogo para elegir un destinatario (reenvío de un mensaje). Lista los
# contactos del roster; emite `submitted(jid)`.

signal submitted(jid)

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

var _list: ItemList
var _jids := []

func _init() -> void:
	window_title = "Reenviar a…"
	rect_min_size = Vector2(360, 420)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.rect_min_size = Vector2(0, 320)
	_list.connect("item_activated", self, "_on_activate")
	box.add_child(_list)
	add_child(box)
	get_ok().text = "Reenviar"
	connect("confirmed", self, "_on_confirm")

# p_contacts: [{jid, name}]
func open(p_contacts: Array) -> void:
	_jids = []
	_list.clear()
	for c in p_contacts:
		var jid = str(c.get("jid", ""))
		if jid == "":
			continue
		var name = str(c.get("name", ""))
		_jids.append(jid)
		_list.add_item(name if name != "" else jid)
	popup_centered()

func _on_activate(p_idx: int) -> void:
	_emit(p_idx)

func _on_confirm() -> void:
	var sel = _list.get_selected_items()
	if sel.size() > 0:
		_emit(int(sel[0]))

func _emit(p_idx: int) -> void:
	if p_idx >= 0 and p_idx < _jids.size():
		hide()
		emit_signal("submitted", _jids[p_idx])