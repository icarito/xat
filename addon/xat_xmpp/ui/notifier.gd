extends Node

# Notificaciones fuera de primer plano.
#
# Godot 3 no trae API de notificaciones del sistema: este nodo es la fachada
# portable. Si el binario del fork expone el singleton nativo `XatNotify`
# (Android `NotificationManager` / iOS `UNUserNotificationCenter`), delega en
# él; si no, es un no-op silencioso y la app sigue avisando sólo in-app
# (`juice.toast`). Ver `docs/notifications.md` para el plan nativo completo.
#
# Reglas (portadas de `gtk-llm-chat-android/src/xmpp/notifications.ts`):
#  - Sólo se notifica con la app en segundo plano; en primer plano avisa la UI.
#  - Se ignoran MAM/replay (el servidor reenvía historial al reconectar) y la
#    ventana de gracia post-conexión.
#  - Se descartan los mensajes de "ruido" (progreso de herramienta, recibos).
#  - Dedupe por id de mensaje (el mismo puede llegar en vivo y por carbon).
#
# Contrato del singleton nativo `XatNotify`:
#   available() -> bool
#   request_permission() -> bool          (opcional)
#   notify(title, body, jid, tag)         (tag = id del mensaje, "" si no hay)

const Retention = preload("res://addons/xat_xmpp/xmpp/retention.gd")

const MAX_BODY := 200

var _foreground := true
var _connected_at_ms := 0
var _notified := {}
var _native = null
var _native_ready := false

func _ready() -> void:
	_resolve_native()

# Resuelve el singleton nativo de forma perezosa: el plugin Java puede
# registrarse DESPUÉS del _ready del nodo (el registro ocurre en la inicialización
# del plugin, no en el arranque de GDScript). Antes se cacheaba una sola vez en
# _ready y quedaba en false para siempre.
func _resolve_native() -> bool:
	if _native_ready:
		return true
	if Engine.has_singleton("XatNotify"):
		_native = Engine.get_singleton("XatNotify")
		# No se usa has_method: los JNISingleton exponen los métodos sólo vía
		# call() (su method_map no alimenta has_method/get_method_list).
		_native_ready = _native != null
	return _native_ready

func _notification(p_what: int) -> void:
	match p_what:
		MainLoop.NOTIFICATION_APP_PAUSED, MainLoop.NOTIFICATION_WM_FOCUS_OUT:
			_foreground = false
		MainLoop.NOTIFICATION_APP_RESUMED, MainLoop.NOTIFICATION_WM_FOCUS_IN:
			_foreground = true

func native_available() -> bool:
	return _resolve_native()

func is_background() -> bool:
	return not _foreground

# Marca el instante de conexión: durante la gracia post-conexión el servidor
# vuelca carbons/pendientes y no hay que notificar esa ráfaga.
func set_connected() -> void:
	_connected_at_ms = OS.get_ticks_msec()

# Pide permiso de notificaciones (Android 13+/iOS). No-op sin plugin.
func request_permission() -> bool:
	if _resolve_native():
		return bool(_native.call("request_permission"))
	return false

# Token de push del dispositivo (FCM/APNs) para XEP-0357, o "" si el plugin
# nativo no lo expone todavía. Es asíncrono en el SO: puede estar vacío en el
# primer arranque y rellenarse después; se re-registra al reconectar.
func device_token() -> String:
	if _resolve_native():
		return str(_native.call("get_device_token"))
	return ""

# Android: inicializa Firebase con los valores del google-services.json de la
# app. Necesario antes de `device_token()` (FCM exige FirebaseApp inicializado).
func configure_firebase(p_api_key: String, p_app_id: String, p_project_id: String, p_sender_id: String) -> void:
	# Se usa call() directo: los JNISingleton exponen los métodos vía call() pero
	# NO en has_method()/get_method_list() (el JNISingleton no override esos), así
	# que has_method() da false aunque el método exista y funcione.
	if _resolve_native():
		_native.call("configure", p_api_key, p_app_id, p_project_id, p_sender_id)

# Decide y, si corresponde, muestra la notificación del sistema. Devuelve true
# si se notificó. `p_name` es el nombre visible del contacto (o "" para usar el
# bare JID). `p_rec` es el registro de mensaje de la sesión.
func notify_message(p_peer: String, p_name: String, p_rec: Dictionary) -> bool:
	if not _resolve_native() or _foreground:
		return false
	if str(p_rec.get("direction", "in")) == "out" or bool(p_rec.get("is_mam", false)) or bool(p_rec.get("stale", false)):
		return false
	var body = str(p_rec.get("body", "")).strip_edges()
	if body == "" or _is_noise(body, p_rec):
		return false
	var now_ms = OS.get_unix_time() * 1000
	if _connected_at_ms > 0 and Retention.within_connect_grace(_connected_at_ms, now_ms):
		return false
	if Retention.is_replay(str(p_rec.get("timestamp", "")), now_ms):
		return false
	var mid = str(p_rec.get("id", ""))
	if mid != "":
		if _notified.has(mid):
			return false
		_notified[mid] = true
		_prune()
	var title = p_name if p_name != "" else p_peer
	_native.call("notify", title, _truncate(body), p_peer, mid)
	return true

# Silencia/retira los avisos de una conversación (p. ej. al abrir el chat o al
# resolverse por una corrección). No-op sin plugin.
func clear(p_peer: String) -> void:
	if _resolve_native():
		_native.call("clear", p_peer)

# Mensajes de progreso/estado que ensucian la bandeja (no son contenido del
# usuario). Portado de `isXmppNotificationNoise`.
func _is_noise(p_body: String, p_rec: Dictionary) -> bool:
	if not (p_rec.get("commands", []) as Array).empty() or not (p_rec.get("quick_responses", []) as Array).empty():
		return false
	var re = RegEx.new()
	for pat in [
		"^Recibido\\s*[·.-]\\s*preparando…?$",
		"^Command (?:submitted|expired)\\.?$",
		"^✅\\s*Approval\\s+(?:allow-once|allow-always|deny)\\s+submitted",
		"^✅\\s*aprobado\\s*[—-]",
		"^Usage:\\s*/approve",
		"^\\s*(?:⚠️?|✅|❌)?\\s*(?:🔧|🛠️?|Tool(?:\\s|:)|Using tool|Herramienta:|Exec failed:)",
	]:
		if re.compile(pat) == OK and re.search(p_body) != null:
			return true
	return false

func _truncate(p_body: String) -> String:
	if p_body.length() <= MAX_BODY:
		return p_body
	return p_body.substr(0, MAX_BODY - 3) + "..."

func _prune() -> void:
	if _notified.size() <= 500:
		return
	var keys = _notified.keys()
	for i in range(keys.size() - 250):
		_notified.erase(keys[i])
