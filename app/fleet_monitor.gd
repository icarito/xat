extends Control

signal close_requested

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

const COLOR_READY := Color("4ade80")
const COLOR_DEGRADED := Color("ffb547")
const COLOR_DOWN := Color("ff5c7a")
const COLOR_UNKNOWN := Color("8b93a7")
const COLOR_HIBERNATED := Color("7e91b5")

var _content
var _operations_content
var _freshness
var _node := "joework/monitoring/team"
var _summary_values := {}
var _cost_rows

func _ready() -> void:
	visible = false
	anchor_right = 1.0
	anchor_bottom = 1.0
	var backdrop = ColorRect.new()
	backdrop.color = Color("0b0f15")
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	add_child(backdrop)
	var margin = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_constant_override("margin_left", 28)
	margin.add_constant_override("margin_right", 28)
	margin.add_constant_override("margin_top", 22)
	margin.add_constant_override("margin_bottom", 22)
	add_child(margin)
	var layout = VBoxContainer.new()
	layout.add_constant_override("separation", 14)
	margin.add_child(layout)
	_build_header(layout)
	_build_overview(layout)
	_build_content(layout)
	show_snapshot({})

func _build_header(p_layout: VBoxContainer) -> void:
	var header = HBoxContainer.new()
	header.add_constant_override("separation", 14)
	p_layout.add_child(header)
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_constant_override("separation", 1)
	header.add_child(title_box)
	var eyebrow = _label("JOEWORK  /  FLEET OPERATIONS", P.AGENT_EDGE, P.FONT_MEDIUM, 11)
	title_box.add_child(eyebrow)
	var title = _label("Fleet monitor", P.TEXT, P.FONT_BOLD, 24)
	title_box.add_child(title)
	_freshness = _label("WAITING", P.TEXT_DIM, P.FONT_MONO, 11)
	_freshness.align = Label.ALIGN_RIGHT
	_freshness.valign = Label.VALIGN_CENTER
	_freshness.clip_text = true
	_freshness.hint_tooltip = "Projection freshness"
	_freshness.rect_min_size.x = 210
	header.add_child(_freshness)
	var close = Button.new()
	close.text = "Close  ×"
	close.focus_mode = Control.FOCUS_NONE
	close.connect("pressed", self, "_on_close")
	header.add_child(close)
	_add_rule(p_layout)

func _build_overview(p_layout: VBoxContainer) -> void:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	p_layout.add_child(row)
	_add_stat_card(row, "READY", "0", COLOR_READY, "ready")
	_add_stat_card(row, "DEGRADED", "0", COLOR_DEGRADED, "degraded")
	_add_stat_card(row, "UNKNOWN", "0", COLOR_UNKNOWN, "unknown")
	_add_stat_card(row, "HIBERNATED", "0", COLOR_HIBERNATED, "hibernated")
	var cost_card = _card(Color("332a19"))
	cost_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_card.rect_min_size.x = 300
	row.add_child(cost_card)
	var cost_layout = VBoxContainer.new()
	cost_layout.add_constant_override("separation", 3)
	cost_card.add_child(cost_layout)
	cost_layout.add_child(_label("COST OBSERVED", COLOR_DEGRADED, P.FONT_MEDIUM, 11))
	_cost_rows = VBoxContainer.new()
	_cost_rows.add_constant_override("separation", 1)
	cost_layout.add_child(_cost_rows)

func _add_stat_card(p_parent: HBoxContainer, p_title: String, p_value: String, p_color: Color, p_key: String) -> void:
	var card = _card(Color("151b24"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.rect_min_size.x = 115
	p_parent.add_child(card)
	var body = HBoxContainer.new()
	body.add_constant_override("separation", 10)
	card.add_child(body)
	var rail = ColorRect.new()
	rail.color = p_color
	rail.rect_min_size = Vector2(3, 40)
	body.add_child(rail)
	var copy = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_constant_override("separation", 0)
	body.add_child(copy)
	copy.add_child(_label(p_title, P.TEXT_DIM, P.FONT_MEDIUM, 10))
	var value = _label(p_value, P.TEXT, P.FONT_BOLD, 22)
	copy.add_child(value)
	_summary_values[p_key] = value

func _build_content(p_layout: VBoxContainer) -> void:
	p_layout.add_child(_section_divider("CURRENT OPERATIONS"))
	_operations_content = VBoxContainer.new()
	_operations_content.add_constant_override("separation", 5)
	p_layout.add_child(_operations_content)
	var heading = HBoxContainer.new()
	heading.add_child(_label("FLEET INVENTORY", P.TEXT, P.FONT_BOLD, 13))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	heading.add_child(_label("IDENTITY  ·  TYPE  ·  HEALTH  ·  LIFECYCLE", P.TEXT_DIM, P.FONT_MONO, 10))
	p_layout.add_child(heading)
	var column_head = _entity_columns(true)
	p_layout.add_child(column_head)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	p_layout.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_constant_override("separation", 5)
	scroll.add_child(_content)

func show_snapshot(p_snapshot: Dictionary) -> void:
	if _content == null: return
	for child in _content.get_children():
		child.queue_free()
	for child in _operations_content.get_children():
		child.queue_free()
	var stale = bool(p_snapshot.get("stale", false))
	var generated = str(p_snapshot.get("generated_at", ""))
	var has_data = not p_snapshot.get("entities", []).empty()
	var freshness = "STALE" if stale else ("LIVE" if generated != "" else ("UNKNOWN" if has_data else "WAITING"))
	_freshness.text = freshness + "   ·   " + (generated if generated != "" else "no snapshot timestamp")
	_freshness.add_color_override("font_color", Color(1.0, 0.62, 0.26) if stale else (COLOR_READY if freshness == "LIVE" else P.TEXT_DIM))
	var counts := {"ready": 0, "degraded": 0, "unknown": 0, "hibernated": 0}
	for entity in p_snapshot.get("entities", []):
		var state = _state_key(entity)
		counts["degraded" if state == "down" else state] += 1
	for key in counts.keys():
		_summary_values[key].text = str(counts[key])
	_render_costs(p_snapshot.get("cost", []))
	var operations = p_snapshot.get("operations", [])
	if operations.empty():
		_operations_content.add_child(_label("No active operations", P.TEXT_DIM, P.FONT_REGULAR, 11))
	else:
		for operation in operations:
			_operations_content.add_child(_operation_row(operation))
	for entity in p_snapshot.get("entities", []):
		_content.add_child(_entity_row(entity))
	if p_snapshot.get("entities", []).empty():
		_content.add_child(_empty_state("No snapshot received", "PubSub node  ·  " + _node))

func _entity_columns(p_header: bool):
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	var identity = _label("INSTANCE / TEAM" if p_header else "", P.TEXT_DIM, P.FONT_MEDIUM, 10)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	row.add_child(_label("TYPE", P.TEXT_DIM, P.FONT_MEDIUM, 10, 110))
	row.add_child(_label("HEALTH", P.TEXT_DIM, P.FONT_MEDIUM, 10, 145))
	row.add_child(_label("LIFECYCLE", P.TEXT_DIM, P.FONT_MEDIUM, 10, 125))
	return row

func _entity_row(p_entity: Dictionary):
	var status = _state_key(p_entity)
	var color = _state_color(status)
	var card = _card(Color("151b24"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	card.add_child(row)
	var rail = ColorRect.new()
	rail.color = color
	rail.rect_min_size = Vector2(4, 42)
	row.add_child(rail)
	var identity = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_constant_override("separation", 0)
	row.add_child(identity)
	var team = str(p_entity.get("team", "Unassigned"))
	var instance_id = str(p_entity.get("id", ""))
	var entity_label = str(p_entity.get("label", team))
	var title = _label(entity_label, P.TEXT, P.FONT_MEDIUM, 13)
	title.clip_text = true
	title.hint_tooltip = entity_label + " · " + team
	identity.add_child(title)
	var subtitle_text = instance_id
	var jid = str(p_entity.get("jid", ""))
	var subtitle = _label(_ellipsize(subtitle_text if subtitle_text != "" else "—", 30), P.TEXT_DIM, P.FONT_MONO, 10)
	subtitle.clip_text = true
	subtitle.hint_tooltip = subtitle_text + (" · " + jid if jid != "" else "")
	identity.add_child(subtitle)
	var kind = str(p_entity.get("entity-kind", "entity")).to_upper()
	row.add_child(_pill(kind, Color("202a36"), P.AGENT_EDGE, 110))
	row.add_child(_pill(_entity_state_title(p_entity, status), _state_tint(status), color, 145))
	var lifecycle = str(p_entity.get("lifecycle", "—")).replace("_", " ").to_upper()
	row.add_child(_pill(lifecycle, Color("1c222d"), P.TEXT_DIM, 125))
	card.hint_tooltip = "%s · %s · %s" % [team, instance_id, jid]
	return card

func _operation_row(p_operation: Dictionary):
	var card = _card(Color("111720"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	card.add_child(row)
	var title = _label(str(p_operation.get("instance", "Fleet operation")), P.TEXT, P.FONT_MEDIUM, 12)
	title.rect_min_size.x = 200
	title.clip_text = true
	row.add_child(title)
	var fields = p_operation.get("fields", {})
	var detail = []
	for key in fields.keys():
		detail.append("%s  %s" % [str(key).replace("_", " ").to_upper(), fields[key]])
	var values = _label("     ·     ".join(detail), P.TEXT_DIM, P.FONT_MONO, 10)
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.clip_text = true
	values.hint_tooltip = "     ·     ".join(detail)
	values.text = _ellipsize(values.text, 100)
	row.add_child(values)
	return card

func _render_costs(p_rows: Array) -> void:
	for child in _cost_rows.get_children():
		child.queue_free()
	if p_rows.empty():
		_cost_rows.add_child(_label("No cost metrics", P.TEXT_DIM, P.FONT_MEDIUM, 13))
		return
	for i in range(min(2, p_rows.size())):
		var row = p_rows[i]
		var amount = str(row.get("value", "—"))
		var currency = str(row.get("currency", row.get("unit", "")))
		var instance = str(row.get("instance", ""))
		var line_text = amount + (" " + currency if currency != "" else "") + ("   ·   " + instance if instance != "" else "")
		var line = _label(_ellipsize(line_text, 32), P.TEXT, P.FONT_MEDIUM, 13)
		line.clip_text = true
		line.hint_tooltip = line_text
		_cost_rows.add_child(line)
	if p_rows.size() > 2:
		_cost_rows.add_child(_label("+%d more metrics" % (p_rows.size() - 2), P.TEXT_DIM, P.FONT_REGULAR, 10))

func _empty_state(p_title: String, p_detail: String):
	var card = _card(Color("111720"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body = VBoxContainer.new()
	body.add_constant_override("separation", 4)
	card.add_child(body)
	body.add_child(_label(p_title, P.TEXT, P.FONT_MEDIUM, 16))
	body.add_child(_label(p_detail, P.TEXT_DIM, P.FONT_MONO, 11))
	return card

func _section_divider(p_title: String):
	var label = _label(p_title, P.AGENT_EDGE, P.FONT_MEDIUM, 11)
	label.rect_min_size.y = 27
	label.valign = Label.VALIGN_BOTTOM
	return label

func _pill(p_text: String, p_bg: Color, p_fg: Color, p_width: float):
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(p_width, 30)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style = StyleBoxFlat.new()
	style.bg_color = p_bg
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_stylebox_override("panel", style)
	var label = _label(p_text, p_fg, P.FONT_MEDIUM, 10)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.clip_text = true
	label.hint_tooltip = p_text
	panel.add_child(label)
	return panel

func _card(p_bg: Color):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = p_bg
	style.border_color = Color("273140")
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 11
	style.content_margin_right = 11
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_stylebox_override("panel", style)
	return panel

func _label(p_text: String, p_color: Color, p_font: String, p_size: int, p_width: float = 0.0):
	var label = Label.new()
	label.text = p_text
	label.add_color_override("font_color", p_color)
	label.add_font_override("font", XatTheme.font(p_font, p_size))
	label.rect_min_size.x = p_width
	label.valign = Label.VALIGN_CENTER
	return label

func _add_rule(p_parent: Control) -> void:
	var rule = ColorRect.new()
	rule.color = P.LINE
	rule.rect_min_size.y = 1
	p_parent.add_child(rule)

func _state_key(p_entity: Dictionary) -> String:
	var lifecycle = str(p_entity.get("lifecycle", "")).to_lower()
	var health = str(p_entity.get("health", p_entity.get("status", ""))).to_lower()
	if lifecycle == "hibernated" or health == "hibernated": return "hibernated"
	if health in ["ready", "healthy", "up", "running", "online", "active", "ok"]: return "ready"
	if health in ["degraded", "unhealthy"]: return "degraded"
	if health in ["down", "failed", "error"]: return "down"
	return "unknown"

func _state_title(p_state: String) -> String:
	match p_state:
		"ready": return "READY"
		"degraded": return "DEGRADED"
		"down": return "DOWN"
		"hibernated": return "HIBERNATED"
		_: return "UNKNOWN"

func _entity_state_title(p_entity: Dictionary, p_state: String) -> String:
	if p_state == "hibernated": return "HIBERNATED"
	var health = str(p_entity.get("health", p_entity.get("status", ""))).to_lower()
	if health == "down": return "DOWN"
	return _state_title(p_state)

func _state_color(p_state: String) -> Color:
	match p_state:
		"ready": return COLOR_READY
		"degraded": return COLOR_DEGRADED
		"down": return COLOR_DOWN
		"hibernated": return COLOR_HIBERNATED
		_: return COLOR_UNKNOWN

func _state_tint(p_state: String) -> Color:
	match p_state:
		"ready": return Color("183023")
		"degraded": return Color("352a1b")
		"down": return Color("351d26")
		"hibernated": return Color("202a3c")
		_: return Color("222833")

func _ellipsize(p_text: String, p_max_chars: int) -> String:
	if p_text.length() <= p_max_chars: return p_text
	return p_text.substr(0, p_max_chars - 1) + "…"

func _on_close() -> void:
	visible = false
	emit_signal("close_requested")

func set_node(p_node: String) -> void:
	_node = p_node
