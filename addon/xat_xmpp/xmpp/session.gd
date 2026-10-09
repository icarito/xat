extends Node

# Sesión XMPP: orquesta el transporte nativo, el roster/presencia, el historial
# y los XEPs de mensajería. La UI consume señales; acá vive el estado.
#
# Frontera: el nativo emite en el hilo principal (via call_deferred), así que
# todo esto corre en el hilo principal. SQLite nunca se toca desde libstrophe.

signal state_changed(state)
signal roster_changed()
signal presence_changed(bare_jid)
signal message_received(rec)
signal message_corrected(rec)
signal delivery_received(id, bare_jid)
signal chat_state_received(bare_jid, state)
signal actions_received(bare_jid, rec)
signal history_fetched(bare_jid, rows, complete)
signal command_response(resp)
signal command_form(from_jid, resp)
signal error_received(rec)
signal log_message(level, msg)
signal agent_state_changed(bare_jid, state)
signal auth_failed()
signal avatar_changed(bare_jid, texture)
signal agent_hook(bare_jid, hook)
# Adjuntos (XEP-0363 + OOB): estado de subida y disponibilidad local del media.
signal media_upload_state(bare_jid, request_id, state, url)
signal media_ready(bare_jid, message_id, path, kind)
signal media_failed(bare_jid, message_id, reason)

enum State { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }

const Transport = preload("res://addons/xat_xmpp/xmpp/transport.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Jid = preload("res://addons/xat_xmpp/xmpp/jid.gd")
const Presence = preload("res://addons/xat_xmpp/xmpp/presence.gd")
const Roster = preload("res://addons/xat_xmpp/xmpp/roster.gd")
const Message = preload("res://addons/xat_xmpp/xmpp/message.gd")
const Store = preload("res://addons/xat_xmpp/xmpp/store.gd")
const Mam = preload("res://addons/xat_xmpp/xmpp/mam.gd")
const Correction = preload("res://addons/xat_xmpp/xmpp/corrections.gd")
const DeviceResource = preload("res://addons/xat_xmpp/xmpp/resource.gd")
const Backoff = preload("res://addons/xat_xmpp/xmpp/backoff.gd")
const Commands = preload("res://addons/xat_xmpp/xmpp/commands.gd")
const Actions = preload("res://addons/xat_xmpp/xmpp/actions.gd")
const Retention = preload("res://addons/xat_xmpp/xmpp/retention.gd")
const Normalize = preload("res://addons/xat_xmpp/xmpp/normalize.gd")
const Caps = preload("res://addons/xat_xmpp/xmpp/caps.gd")
const Pep = preload("res://addons/xat_xmpp/xmpp/pep.gd")
const AgentState = preload("res://addons/xat_xmpp/xmpp/agent_state.gd")
const Avatar = preload("res://addons/xat_xmpp/xmpp/avatar.gd")
const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")
const HttpTransfer = preload("res://addons/xat_xmpp/xmpp/http_transfer.gd")

const OMEMO_PLACEHOLDER := "🔒 Mensaje cifrado con OMEMO: xat todavía no puede leerlo."
const RESOURCE_BASE := "xat"
const RESOURCE_PATH := "user://xat_resource"
const PING_INTERVAL := 180.0
const HISTORY_DB := "user://history.db"
const MEDIA_DIR := "user://media/"

var state = State.DISCONNECTED
var presence_model = Presence.new()
var roster_model = Roster.new()
var agent_model = AgentState.new()
var avatars := {} # bare -> ImageTexture (XEP-0084)
var _avatar_req := {} # iq id -> {bare, path}
var store = null

var _transport = null
var _jid = ""
var _bare = ""
var _password = ""
var _host = ""
var _port = 5222
var _cafile = ""
var _auto_reconnect := true
var _reconnect_attempt := 0
var _reconnect_timer: Timer
var _ping_timer: Timer
var _ping_outstanding := 0
var _pending_mam := {} # queryid -> bare_jid
var _auth_failed := false
var last_sent_id := "" # id del último send_message (para matchear recibos 0184)

# --- Adjuntos ---
var _upload_host := ""           # componente XEP-0363 descubierto ("" = no hay)
var _upload_host_known := false  # ya se intentó descubrir (no repetir por envío)
var _upload_max_bytes := 0       # max-file-size publicado por el componente (0 = sin dato)
var _upload_ctx := {}            # iq id del slot -> contexto de subida
var _disco_ctx := {}             # iq id de disco -> {kind, candidates, index, domain}
var _upload_queue := []          # contextos esperando a que se resuelva el host
var _media_dl := {}              # message_id -> path (descargas en curso)

func _ready() -> void:
	store = Store.new()
	if store.available():
		store.open(HISTORY_DB)

	_transport = Transport.new()
	_transport.name = "Transport"
	add_child(_transport)
	_transport.connect("stanza", self, "_on_stanza")
	_transport.connect("connected", self, "_on_connected")
	_transport.connect("disconnected", self, "_on_disconnected")
	_transport.connect("log_message", self, "_on_log")

	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.connect("timeout", self, "_reconnect_now")
	add_child(_reconnect_timer)

	_ping_timer = Timer.new()
	_ping_timer.wait_time = PING_INTERVAL
	_ping_timer.connect("timeout", self, "_on_ping_timeout")
	add_child(_ping_timer)

# --- API pública ---

func connect_account(jid, password: String, host: String = "", port: int = 5222, cafile: String = "", auto_reconnect: bool = true) -> int:
	var j = Jid.new()
	j.parse(str(jid))
	if not j.is_valid():
		return -1
	_bare = j.bare
	_password = password
	_host = host
	_port = port
	_cafile = cafile
	_auto_reconnect = auto_reconnect
	var suffix = DeviceResource.new().load_or_create(RESOURCE_PATH)
	_jid = DeviceResource.full_jid(_bare, RESOURCE_BASE, suffix)
	_auth_failed = false
	_set_state(State.CONNECTING)
	return _transport.open(_jid, _password, _host, _port, _cafile)

func disconnect_account() -> void:
	_auto_reconnect = false
	_reconnect_timer.stop()
	_ping_timer.stop()
	_transport.close()
	_set_state(State.DISCONNECTED)

func is_connected_to_server() -> bool:
	return state == State.CONNECTED

func bare() -> String:
	return _bare

func send_message(p_to_bare: String, p_body: String) -> int:
	# Cuerpos largos se parten respetando XMPP_MAX_BODY; sólo el primero pide
	# recibo (el resto son continuación).
	var parts = Normalize.split_for_limit(p_body)
	var rc = 0
	var first_id = ""
	for i in range(parts.size()):
		var mid = _new_id("m")
		if i == 0:
			first_id = mid
			last_sent_id = mid
		var stanza = Message.build_chat(p_to_bare, parts[i], mid, _new_id("o"), i == 0)
		var r = _transport.send(stanza.to_xml())
		if i == 0:
			rc = r
	if rc == 0 and store != null and store.available():
		store.record_message({"bare_jid": p_to_bare, "body": p_body, "direction": "out", "ts": _now_iso(), "request_id": first_id})
	return rc

func send_chat_state(p_to_bare: String, p_state: String) -> int:
	return _transport.send(Message.build_chat_state(p_to_bare, p_state).to_xml())

# --- Adjuntos (XEP-0363 + XEP-0066) ---

# Sube un archivo local y lo envía como adjunto. Devuelve el request_id de la
# fila optimista (id del mensaje); "" si no se pudo empezar.
func send_media_file(p_to_bare: String, p_path: String, p_mime: String = "", p_duration_ms: int = 0, p_caption: String = "") -> String:
	if not is_connected_to_server():
		return ""
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return ""
	var size = f.get_len()
	f.close()
	if size <= 0 or size > Media.MAX_UPLOAD_SIZE:
		return ""
	var mime = p_mime if p_mime != "" else Media.mime_for_path(p_path)
	var request_id = _new_id("a")
	var ctx = {
		"to": p_to_bare,
		"path": p_path,
		"mime": mime,
		"kind": Media.kind_for_mime(mime),
		"size": size,
		"duration_ms": int(p_duration_ms),
		"filename": Media.sanitize_filename(p_path.get_file(), "adjunto"),
		"request_id": request_id,
		"caption": p_caption.strip_edges(),
		"get_url": "",
	}
	# Fila optimista: se ve en el chat con estado "subiendo" y se reemplaza el
	# cuerpo por la URL cuando termina.
	if store != null and store.available():
		var placeholder = ctx["caption"] if ctx["caption"] != "" else ctx["filename"]
		store.record_message({"bare_jid": p_to_bare, "body": placeholder, "direction": "out", "ts": _now_iso(), "request_id": request_id, "attach": _attach_of(ctx, "uploading", "")})
	emit_signal("media_upload_state", p_to_bare, request_id, "uploading", "")
	if not _upload_host_known:
		_upload_queue.append(ctx)
		_start_upload_discovery()
	elif _upload_host == "":
		_fail_upload(ctx, "sin-servicio")
	else:
		_request_slot(ctx)
	return request_id

# Devuelve la ruta local del adjunto de `p_rec`; si no está, arranca la
# descarga y devuelve "". La UI escucha `media_ready`.
func ensure_media(p_bare: String, p_rec: Dictionary) -> String:
	var attach = p_rec.get("attach", {})
	if not (attach is Dictionary) or attach.empty():
		return ""
	var url = str(attach.get("url", ""))
	if url == "":
		return ""
	var path = media_cache_path(url)
	var f = File.new()
	if f.file_exists(path):
		return path
	var mid = str(p_rec.get("id", ""))
	if mid == "" or _media_dl.has(mid):
		return ""
	_ensure_media_dir()
	_media_dl[mid] = path
	var t = HttpTransfer.new()
	t.name = "Dl_" + mid
	t.configure_download(mid, url, path)
	t.connect("finished", self, "_on_download_finished", [p_bare, p_rec, attach])
	add_child(t)
	t.start()
	return ""

func media_cache_path(p_url: String) -> String:
	return MEDIA_DIR + str(p_url.hash()) + "_" + Media.filename_from_url(p_url, "media")

func _ensure_media_dir() -> void:
	var d = Directory.new()
	if not d.dir_exists(MEDIA_DIR):
		d.make_dir_recursive(MEDIA_DIR)

func _attach_of(p_ctx: Dictionary, p_state: String, p_url: String) -> Dictionary:
	return {
		"url": p_url,
		"mime": p_ctx["mime"],
		"kind": p_ctx["kind"],
		"name": p_ctx["filename"],
		"size": p_ctx["size"],
		"duration_ms": p_ctx["duration_ms"],
		"state": p_state,
		"local": p_ctx["path"],
	}

func _request_slot(p_ctx: Dictionary) -> void:
	var iq_id = _new_id("slot")
	_upload_ctx[iq_id] = p_ctx
	_transport.send(Media.build_slot_request(iq_id, _upload_host, p_ctx["filename"], p_ctx["size"], p_ctx["mime"]).to_xml())

func _start_upload_discovery() -> void:
	if _upload_host_known:
		return
	var at = _bare.find("@")
	if at < 0:
		_resolve_no_host()
		return
	var domain = _bare.substr(at + 1)
	var iq_id = _new_id("disc")
	_disco_ctx[iq_id] = {"kind": "items", "domain": domain, "candidates": [], "index": 0}
	_transport.send(Media.build_disco_items(iq_id, domain).to_xml())

func _on_disco_result(p_stanza) -> void:
	var iq_id = p_stanza.get_attr("id", "")
	var st = _disco_ctx.get(iq_id, null)
	if st == null:
		return
	_disco_ctx.erase(iq_id)
	if st["kind"] == "items":
		var candidates = []
		for j in Media.parse_disco_items(p_stanza):
			if j != st["domain"] and not candidates.has(j):
				candidates.append(j)
		# El componente suele vivir en `upload.<dominio>` aunque no salga en items.
		var guess = "upload." + st["domain"]
		# Sólo probar la conjetura si el dominio no tiene items (evita ruido).
		if candidates.empty() and not candidates.has(guess):
			candidates.append(guess)
		if candidates.empty():
			_resolve_no_host()
		else:
			_disco_probe(candidates, 0)
	elif st["kind"] == "info":
		if Media.disco_has_upload(p_stanza):
			_upload_max_bytes = Media.disco_max_file_size(p_stanza)
			_resolve_host(st["candidates"][st["index"]])
		else:
			_disco_probe(st["candidates"], int(st["index"]) + 1)

func _on_disco_error(p_stanza) -> void:
	var st = _disco_ctx.get(p_stanza.get_attr("id", ""), null)
	if st == null:
		return
	_disco_ctx.erase(p_stanza.get_attr("id", ""))
	if st["kind"] == "info":
		_disco_probe(st["candidates"], int(st["index"]) + 1)
	else:
		_resolve_no_host()

func _disco_probe(p_candidates: Array, p_index: int) -> void:
	if p_index >= p_candidates.size():
		_resolve_no_host()
		return
	var iq_id = _new_id("disc")
	_disco_ctx[iq_id] = {"kind": "info", "domain": "", "candidates": p_candidates, "index": p_index}
	_transport.send(Media.build_disco_info(iq_id, p_candidates[p_index]).to_xml())

func _resolve_host(p_host: String) -> void:
	_upload_host = p_host
	_upload_host_known = true
	var queue = _upload_queue
	_upload_queue = []
	for ctx in queue:
		_request_slot(ctx)

# Límite de subida anunciado por el servidor (bytes), 0 si no lo publicó.
func upload_max_bytes() -> int:
	return _upload_max_bytes

func _resolve_no_host() -> void:
	_upload_host = ""
	_upload_host_known = true
	var queue = _upload_queue
	_upload_queue = []
	for ctx in queue:
		_fail_upload(ctx, "sin-servicio")

# Al perder la conexión se olvida el componente descubierto y se fallan los
# envíos pendientes (no podrán completarse en esta sesión).
func _reset_upload_state() -> void:
	_upload_host = ""
	_upload_host_known = false
	_upload_max_bytes = 0
	_disco_ctx.clear()
	_upload_ctx.clear()
	var queue = _upload_queue
	_upload_queue = []
	for ctx in queue:
		_fail_upload(ctx, "red-0")

func _on_slot_result(p_stanza) -> void:
	var iq_id = p_stanza.get_attr("id", "")
	var ctx = _upload_ctx.get(iq_id, null)
	if ctx == null:
		return
	_upload_ctx.erase(iq_id)
	var slot = Media.parse_slot_result(p_stanza)
	if not slot["ok"]:
		_fail_upload(ctx, slot.get("error", "slot"))
		return
	ctx["get_url"] = slot["get_url"]
	print("xat-media: slot put=%s" % slot["put_url"])
	var f = File.new()
	if f.open(ctx["path"], File.READ) != OK:
		_fail_upload(ctx, "archivo")
		return
	var bytes = f.get_buffer(ctx["size"])
	f.close()
	var t = HttpTransfer.new()
	t.name = "Up_" + ctx["request_id"]
	t.configure_upload(ctx["request_id"], slot["put_url"], Media.headers_array(slot["headers"]), bytes, ctx["mime"])
	t.connect("finished", self, "_on_upload_finished", [ctx])
	add_child(t)
	t.start()

func _on_slot_error(p_stanza) -> void:
	var ctx = _upload_ctx.get(p_stanza.get_attr("id", ""), null)
	if ctx == null:
		return
	_upload_ctx.erase(p_stanza.get_attr("id", ""))
	var reason = "slot-error"
	if p_stanza.get_child("file-too-large", NS.HTTP_UPLOAD) != null or p_stanza.get_child("file-too-large", "urn:xmpp:http:upload") != null:
		reason = "file-too-large"
	print("xat-media: slot error -> %s" % p_stanza.to_xml())
	_fail_upload(ctx, reason)

func _on_upload_finished(id: String, ok: bool, _code: int, _payload, error: String, ctx: Dictionary) -> void:
	print("xat-media: upload ok=%s err=%s" % [ok, error])
	if not ok:
		_fail_upload(ctx, error)
		return
	var url = str(ctx["get_url"])
	var stanza = Message.build_media(ctx["to"], url, ctx["caption"], ctx["request_id"], _new_id("o"), true)
	var rc = _transport.send(stanza.to_xml())
	if rc == 0:
		last_sent_id = ctx["request_id"]
	var attach = _attach_of(ctx, "sent", url)
	if store != null and store.available():
		store.update_by_request_id(ctx["to"], ctx["request_id"], url)
		store.set_attachment(ctx["to"], ctx["request_id"], attach)
	emit_signal("media_upload_state", ctx["to"], ctx["request_id"], "sent", url)
	emit_signal("media_ready", ctx["to"], ctx["request_id"], ctx["path"], ctx["kind"])

func _fail_upload(p_ctx: Dictionary, p_reason: String) -> void:
	if store != null and store.available():
		store.set_attachment(p_ctx["to"], p_ctx["request_id"], _attach_of(p_ctx, "failed", ""))
	emit_signal("media_upload_state", p_ctx["to"], p_ctx["request_id"], "failed", "")
	emit_signal("media_failed", p_ctx["to"], p_ctx["request_id"], p_reason)

func _on_download_finished(id: String, ok: bool, _code: int, payload, error: String, p_bare: String, p_rec: Dictionary, p_attach: Dictionary) -> void:
	_media_dl.erase(id)
	print("xat-media: download ok=%s path=%s err=%s" % [ok, str(payload), error])
	if not ok:
		emit_signal("media_failed", p_bare, id, error)
		return
	var path = str(payload)
	var attach = p_attach.duplicate()
	attach["local"] = path
	var rid = str(p_rec.get("request_id", p_rec.get("id", "")))
	if store != null and store.available() and rid != "":
		store.set_attachment(p_bare, rid, attach)
	emit_signal("media_ready", p_bare, id, path, str(attach.get("kind", "")))

# Detecta un adjunto en un mensaje: OOB explícito o link con extensión conocida
# en el cuerpo. Deja `rec["attach"]`.
func _apply_media(rec: Dictionary) -> void:
	var url = str(rec.get("oob_url", ""))
	if url == "":
		var cand = Media.url_of(str(rec.get("body", "")))
		if cand != "" and Media.MIME_BY_EXT.has(Media.extension_of(cand)):
			url = cand
	if url == "":
		return
	if str(rec.get("body", "")) == "":
		rec["body"] = url
	var mime = Media.mime_for_path(url)
	rec["attach"] = {
		"url": url,
		"mime": mime,
		"kind": Media.kind_for_mime(mime),
		"name": Media.filename_from_url(url, "adjunto"),
		"size": 0,
		"state": "remote",
	}
	print("xat-media: entrante url=%s kind=%s" % [url, rec["attach"]["kind"]])

func send_presence(p_show: String = "", p_status: String = "") -> int:
	var p = Stanza.new("presence")
	if p_show != "":
		var show = Stanza.new("show")
		show.append_text(p_show)
		p.add_child_stanza(show)
	if p_status != "":
		var status = Stanza.new("status")
		status.append_text(p_status)
		p.add_child_stanza(status)
	p.add_child_stanza(Caps.build_caps_child())
	return _transport.send(p.to_xml())

func request_roster() -> int:
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", _new_id("r"))
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS.ROSTER)
	iq.add_child_stanza(query)
	return _transport.send(iq.to_xml())

func load_history(p_bare_jid: String, p_max: int = 50) -> int:
	if not is_connected_to_server():
		return -1
	var queryid = _new_id("mam")
	# Siempre la ÚLTIMA página (RSM <before/> vacío). Así se recupera la
	# conversación reciente y se rellenan huecos que el catch-up hacia adelante
	# por watermark dejaba pasar (mensajes de otro cliente mientras este estaba
	# desconectado). El dedupe en `_handle_mam_result` evita repetir.
	_pending_mam[queryid] = {"bare": p_bare_jid, "pages": 0, "max_pages": 1}
	return _send_mam_last_page(queryid, p_bare_jid, p_max)

func _send_mam_page(p_queryid: String, p_bare: String, p_after: String, p_max: int) -> int:
	var iq = Mam.build_query(_bare, p_queryid, _new_id("iq"), p_bare, p_max, p_after)
	return _transport.send(iq.to_xml())

func _send_mam_last_page(p_queryid: String, p_bare: String, p_max: int) -> int:
	var iq = Mam.build_query(_bare, p_queryid, _new_id("iq"), p_bare, p_max, "", "", "", "", true)
	return _transport.send(iq.to_xml())

func get_recent_history(p_bare_jid: String, p_limit: int = 50) -> Array:
	if store == null or not store.available():
		return []
	return store.get_recent(p_bare_jid, p_limit)

# Ejecuta un comando ad-hoc (o el selection IQ de un ítem inline) contra un JID.
func execute_command(p_to: String, p_node: String, p_sessionid: String = "") -> int:
	if not is_connected_to_server():
		return -1
	return _transport.send(Commands.build_execute(p_to, p_node, p_sessionid, _new_id("cmd")).to_xml())

func submit_command(p_to: String, p_node: String, p_sessionid: String, p_fields: Array) -> int:
	if not is_connected_to_server():
		return -1
	return _transport.send(Commands.build_submit(p_to, p_node, p_sessionid, p_fields, _new_id("cmd")).to_xml())

# --- Transport ---

func _on_connected(bound_jid: String) -> void:
	_set_state(State.CONNECTED)
	_reconnect_attempt = 0
	_ping_outstanding = 0
	_ping_timer.start()
	request_roster()
	_enable_carbons()
	send_presence()

func _on_disconnected(error: int) -> void:
	_ping_timer.stop()
	# El componente de upload se redescubre en la próxima conexión; los envíos
	# en curso ya no pueden completarse.
	_reset_upload_state()
	# Credenciales malas: reintentar sólo arriesga un bloqueo del servidor.
	if _auth_failed:
		_reconnect_timer.stop()
		_set_state(State.DISCONNECTED)
		emit_signal("auth_failed")
		return
	if _auto_reconnect:
		_set_state(State.RECONNECTING)
		_schedule_reconnect()
	else:
		_set_state(State.DISCONNECTED)

func _on_log(level: int, msg: String) -> void:
	# libstrophe no distingue el fallo de SASL en el código de desconexión; sí lo loguea.
	if msg.find("auth failed") >= 0:
		_auth_failed = true
	emit_signal("log_message", level, msg)

func _on_stanza(xml: String) -> void:
	var stanza = Stanza.parse(xml)
	if stanza == null:
		return
	match stanza.name:
		"message":
			_on_message(stanza)
		"presence":
			_on_presence(stanza)
		"iq":
			_on_iq(stanza)

# --- Mensajería ---

func _on_message(p_stanza) -> void:
	if p_stanza.get_child("event", NS.PEP) != null:
		_on_pep_event(p_stanza)
		return
	var rec = Message.parse(p_stanza)
	# OMEMO (0384) no soportado todavía: en vez de descartar en silencio un
	# mensaje cifrado sin body, mostrar que llegó y por qué no se lee.
	if rec["body"] == "" and (p_stanza.get_child("encrypted", "urn:xmpp:omemo:2") != null or p_stanza.get_child("encrypted", "eu.siacs.conversations.axolotl") != null):
		rec["body"] = OMEMO_PLACEHOLDER
		rec["encrypted"] = true
	# Adjuntos: OOB explícito o link con extensión conocida en el cuerpo.
	_apply_media(rec)
	if rec["is_mam"]:
		_handle_mam_result(rec)
		return

	# Guardas de retención: marcar mensajes con delay viejo y descartar botones
	# vencidos antes de exponerlos a la UI.
	var now_ms = _now_ms()
	var ts_ms = 0
	if rec["timestamp"] != "":
		ts_ms = Retention.parse_stamp_ms(rec["timestamp"])
		rec["stale"] = Retention.is_stale_delayed(rec["timestamp"], now_ms)
	rec["commands"] = Actions.filter_live(rec["commands"], now_ms, ts_ms)
	var quick_items = []
	for q in rec["quick_responses"]:
		var qi = q.duplicate()
		qi["name"] = str(qi.get("label", qi.get("value", "")))
		quick_items.append(qi)
	rec["quick_responses"] = Actions.filter_live(quick_items, now_ms, ts_ms)

	if rec["chat_state"] != "":
		emit_signal("chat_state_received", _bare_of(rec["from"]), rec["chat_state"])
	if rec["receipt_request"] and rec["id"] != "":
		_transport.send(Message.build_receipt(rec["from"], rec["id"]).to_xml())
	if rec["received_id"] != "":
		emit_signal("delivery_received", rec["received_id"], _bare_of(rec["from"]))

	# Corrección 0308: reescribe la fila ancla y avisa a la UI.
	if rec["replace_id"] != "":
		if store != null and store.available():
			store.update_by_request_id(_bare_of(rec["from"]), rec["replace_id"], rec["body"])
		emit_signal("message_corrected", rec)
		return

	# Carbons de mensajes propios: registrar (dedupe por ventana) y reflejar en
	# la UI como saliente; nunca se tratan como input de agente.
	if rec["carbon"] == "sent":
		# Un carbon de chat-state/recibo (sin body) no es un mensaje: no se
		# guarda ni se muestra (antes quedaba una burbuja vacía).
		if rec["body"] == "" and (rec["commands"] as Array).empty() and (rec["quick_responses"] as Array).empty():
			return
		if store != null and store.available() and not _has_recent_outgoing(_bare_of(rec["to"]), rec["body"]):
			store.record_message({"bare_jid": _bare_of(rec["to"]), "body": rec["body"], "direction": "out", "ts": _timestamp(rec), "request_id": rec["id"], "attach": rec.get("attach", {})})
		rec["direction"] = "out"
		emit_signal("message_received", rec)
		return

	if rec["body"] == "":
		if not (rec["commands"] as Array).empty() or not (rec["quick_responses"] as Array).empty():
			emit_signal("actions_received", _bare_of(rec["from"]), rec)
		return

	if store != null and store.available():
		store.record_message({
			"bare_jid": _bare_of(rec["from"]),
			"body": rec["body"],
			"direction": "in",
			"ts": _timestamp(rec),
			"request_id": rec["id"],
			"quick": rec["quick_responses"],
			"commands": rec["commands"],
			"attach": rec.get("attach", {}),
		})
	if not (rec["commands"] as Array).empty() or not (rec["quick_responses"] as Array).empty():
		emit_signal("actions_received", _bare_of(rec["from"]), rec)
	emit_signal("message_received", rec)

# PEP (0163): telemetría y hooks de OpenClaw. El payload no trae JID: el agente
# es el `from` (bare) del evento.
func _on_pep_event(p_stanza) -> void:
	var bare = _bare_of(p_stanza.get_attr("from", ""))
	var ev = Pep.parse_event(p_stanza)
	if ev["retract"] or bare == "":
		return
	if ev["node"] == NS.AVATAR_METADATA:
		_on_avatar_metadata(bare, Pep.parse_avatar_metadata(ev))
		return
	if ev["node"] == NS.TELEMETRY:
		emit_signal("agent_state_changed", bare, agent_model.apply_telemetry(bare, Pep.parse_telemetry(ev)))
		return
	var hook = Pep.parse_hook(ev)
	if not hook.empty():
		emit_signal("agent_hook", bare, hook)
		emit_signal("agent_state_changed", bare, agent_model.apply_hook(bare, hook))

# Metadata de avatar: usar la caché por id o pedir el item de datos.
func _on_avatar_metadata(p_bare: String, p_meta: Dictionary) -> void:
	if p_meta["id"] == "":
		return
	var path = Avatar.cache_path(p_meta["id"], p_meta["type"])
	var tex = Avatar.load_texture(path)
	if tex != null:
		avatars[p_bare] = tex
		emit_signal("avatar_changed", p_bare, tex)
		return
	var iq_id = _new_id("av")
	_avatar_req[iq_id] = {"bare": p_bare, "path": path}
	_transport.send(Avatar.build_data_request(iq_id, p_bare, p_meta["id"]).to_xml())

func _on_avatar_data(p_stanza) -> void:
	var req = _avatar_req.get(p_stanza.get_attr("id", ""), null)
	if req == null:
		return
	_avatar_req.erase(p_stanza.get_attr("id", ""))
	var data = Avatar.parse_data_result(p_stanza)
	if data["base64"] == "":
		return
	Avatar.save(req["path"], Marshalls.base64_to_raw(data["base64"]))
	var tex = Avatar.load_texture(req["path"])
	if tex != null:
		avatars[req["bare"]] = tex
		emit_signal("avatar_changed", req["bare"], tex)

func _handle_mam_result(rec: Dictionary) -> void:
	# El archivo trae ambos sentidos: si lo mandamos nosotros, el peer es `to`.
	var mine = _bare_of(rec["from"]) == _bare
	rec["direction"] = "out" if mine else "in"
	var peer = _bare_of(rec["to"]) if mine else _bare_of(rec["from"])
	if peer == "":
		peer = _bare_of(rec["to"])
	# Corrección 0308 dentro del archivo: aplicarla a la fila ancla en vez de
	# crear una fila nueva. Las correcciones de OpenClaw (marcadores/recibos) no
	# traen body: sin esto quedaban burbujas vacías.
	if rec["replace_id"] != "":
		if store != null and store.available():
			store.update_by_request_id(peer, rec["replace_id"], rec["body"])
		return
	# MAM archiva también chat-states, recibos y marcadores sin <body>. No son
	# mensajes: no se guardan ni se muestran (antes quedaban burbujas vacías).
	if rec["body"] == "" and (rec["commands"] as Array).empty() and (rec["quick_responses"] as Array).empty():
		return
	if store != null and store.available() and rec["mam_id"] != "":
		# Dedupe: el mismo mensaje pudo entrar en vivo antes (sin mam_id), ya
		# estar archivado, o llegar repetido (espejo del agente). Si no, se
		# duplicaba (burbujas repetidas).
		if store.has_mam(peer, rec["mam_id"]):
			return
		var rid = rec["id"]
		if rid != "" and store.attach_mam_by_request(peer, rid, rec["mam_id"]):
			return
		if rid != "" and store.has_request_id(peer, rid):
			return
		if store.attach_mam(peer, rec["mam_id"], rec["body"], rec["direction"], _norm_stamp(_timestamp(rec))):
			return
		# Dedupe por (bare_jid, mam_id); el request_id permite plegar 0308.
		store.record_message({
			"bare_jid": peer,
			"body": rec["body"],
			"direction": rec["direction"],
			"ts": _timestamp(rec),
			"mam_id": rec["mam_id"],
			"request_id": rec["replace_id"] if rec["replace_id"] != "" else rec["id"],
			"quick": rec["quick_responses"],
			"commands": rec["commands"],
			"attach": rec.get("attach", {}),
		})
	emit_signal("message_received", rec)

func _has_recent_outgoing(p_bare_jid: String, p_body: String) -> bool:
	if store == null or not store.available():
		return false
	var rows = store.get_recent(p_bare_jid, 20)
	for r in rows:
		if r["direction"] == "out" and r["body"] == p_body:
			return true
	return false

# --- Presencia / Roster ---

func _on_presence(p_stanza) -> void:
	var full = p_stanza.get_attr("from", "")
	var ptype = p_stanza.get_attr("type", "")
	var show = ""
	var status = ""
	var priority = 0
	var show_node = p_stanza.get_child("show")
	var status_node = p_stanza.get_child("status")
	var prio_node = p_stanza.get_child("priority")
	if show_node != null:
		show = show_node.get_text()
	if status_node != null:
		status = status_node.get_text()
	if prio_node != null and prio_node.get_text().is_valid_integer():
		priority = int(prio_node.get_text())
	presence_model.update(full, ptype, show, priority, status)
	emit_signal("presence_changed", Presence.bare_of(full))

# --- IQ ---

func _on_iq(p_stanza) -> void:
	var iq_type = p_stanza.get_attr("type", "")
	if iq_type == "get":
		# disco#info dirigido a nuestras caps: responder identidad+features.
		var disco = p_stanza.get_child("query", NS.DISCO_INFO)
		# XEP-0115: el server resuelve caps preguntando por `node#ver`. Sin
		# respuesta no conoce nuestros +notify y nunca manda eventos PEP.
		var qnode = disco.get_attr("node", "") if disco != null else ""
		if disco != null and (qnode == "" or qnode == Caps.XAT_NODE or qnode == Caps.XAT_NODE + "#" + Caps.XAT_VER):
			_transport.send(Caps.build_disco_info_result(p_stanza.get_attr("id", ""), p_stanza.get_attr("from", ""), qnode).to_xml())
		return
	if iq_type == "result":
		if p_stanza.get_child("query", NS.ROSTER) != null:
			roster_model.apply_roster_result(p_stanza)
			emit_signal("roster_changed")
		var fin = p_stanza.get_child("fin", NS.MAM)
		if fin != null:
			_on_mam_fin(p_stanza)
		if p_stanza.get_child("command", NS.COMMANDS) != null:
			_on_command_response(p_stanza)
		if p_stanza.get_child("pubsub", NS.PUBSUB) != null:
			_on_avatar_data(p_stanza)
		var iq_id = p_stanza.get_attr("id", "")
		if _disco_ctx.has(iq_id):
			_on_disco_result(p_stanza)
		if _upload_ctx.has(iq_id):
			_on_slot_result(p_stanza)
		_ping_outstanding = 0
	elif iq_type == "error":
		emit_signal("error_received", {})
		var eid = p_stanza.get_attr("id", "")
		if _disco_ctx.has(eid):
			_on_disco_error(p_stanza)
		if _upload_ctx.has(eid):
			_on_slot_error(p_stanza)
		_on_mam_error(p_stanza)
		if p_stanza.get_child("command", NS.COMMANDS) != null:
			_on_command_response(p_stanza)

func _on_command_response(p_stanza) -> void:
	var resp = Commands.parse_response(p_stanza)
	resp["from"] = p_stanza.get_attr("from", "")
	emit_signal("command_response", resp)
	if resp["form"] != null and str(resp["form"].get("type", "")) == "form":
		emit_signal("command_form", resp["from"], resp)

func _on_mam_error(p_stanza) -> void:
	var queryid = p_stanza.get_attr("id", "")
	var st = _pending_mam.get(queryid, null)
	if st == null:
		return
	_pending_mam.erase(queryid)
	var rows = []
	if store != null and store.available():
		rows = store.get_recent(st["bare"], 50)
	emit_signal("history_fetched", st["bare"], rows, false)

func _on_mam_fin(p_stanza) -> void:
	var queryid = p_stanza.get_attr("id", "")
	var st = _pending_mam.get(queryid, null)
	if st == null:
		return
	var info = Mam.parse_fin(p_stanza)
	st["pages"] = int(st["pages"]) + 1
	# Paginar hacia adelante mientras el server no marque completo y queden
	# páginas permitidas (retención: máximo MAX_MAM_PAGES).
	if not info["complete"] and info["rsm_last"] != "" and int(st["pages"]) < int(st["max_pages"]):
		_pending_mam[queryid] = st
		_send_mam_page(queryid, st["bare"], info["rsm_last"], Retention.MAM_PAGE_SIZE)
		return
	_pending_mam.erase(queryid)
	var rows = []
	if store != null and store.available():
		rows = store.get_recent(st["bare"], 50)
	emit_signal("history_fetched", st["bare"], rows, info["complete"])

# --- Ping / reconexión ---

func _on_ping_timeout() -> void:
	if not is_connected_to_server():
		return
	_ping_outstanding += 1
	if _ping_outstanding > 2:
		_transport.close()
		return
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", _new_id("ping"))
	iq.set_attr("to", _bare)
	var ping = Stanza.new("ping")
	ping.set_attr("xmlns", NS.PING)
	iq.add_child_stanza(ping)
	_transport.send(iq.to_xml())

func _schedule_reconnect() -> void:
	var delay = Backoff.delay_for_attempt(_reconnect_attempt)
	_reconnect_attempt += 1
	_reconnect_timer.start(delay)

func _reconnect_now() -> void:
	if _jid == "":
		return
	_set_state(State.CONNECTING)
	_transport.open(_jid, _password, _host, _port, _cafile)

func _enable_carbons() -> void:
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", _new_id("carb"))
	var enable = Stanza.new("enable")
	enable.set_attr("xmlns", NS.CARBONS)
	iq.add_child_stanza(enable)
	_transport.send(iq.to_xml())

# --- Utils ---

func _set_state(p_state: int) -> void:
	if state != p_state:
		state = p_state
		emit_signal("state_changed", state)

func _bare_of(p_jid: String) -> String:
	return Presence.bare_of(p_jid)

func _timestamp(p_rec: Dictionary) -> String:
	return p_rec["timestamp"] if p_rec["timestamp"] != "" else _now_iso()

# Normaliza un stamp ISO al formato con segundos exactos y 'Z' (sin fracción),
# que es el que SQLite `strftime` parsea en las ventanas de dedupe.
func _norm_stamp(p_ts: String) -> String:
	if p_ts == "":
		return ""
	var dot = p_ts.find(".")
	if dot >= 0:
		return p_ts.substr(0, dot) + "Z"
	return p_ts

func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

func _now_ms() -> int:
	return OS.get_unix_time() * 1000

func _new_id(p_prefix: String) -> String:
	return p_prefix + "-" + str(OS.get_ticks_usec())
