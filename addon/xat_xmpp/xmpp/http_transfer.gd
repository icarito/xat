extends Node

# Una transferencia HTTP para adjuntos, sobre `HTTPRequest` (sigue redirects y
# valida TLS con el motor). El nodo se crea por operación y se libera al
# terminar; la sesión conecta `finished`.
#
#   var t = HttpTransfer.new()
#   t.configure_upload(url, headers, bytes, content_type, id)
#   add_child(t); t.start()
#
# Uso:
#   upload: PUT con los bytes en el cuerpo. `payload` del resultado = body.
#   download: GET a memoria. `payload` del resultado = PoolByteArray.
#   download_file: GET a disco. `payload` del resultado = ruta.

const METHOD_GET := HTTPClient.METHOD_GET
const METHOD_PUT := HTTPClient.METHOD_PUT

signal finished(id, ok, code, payload, error)

var id := ""
var mode := "get"          # get | put | get_file
var url := ""
var headers := PoolStringArray()
var content_type := ""
var bytes := PoolByteArray()
var dest := ""
var timeout := 60.0

var _req: HTTPRequest

func configure_upload(p_id: String, p_url: String, p_headers: PoolStringArray, p_bytes: PoolByteArray, p_content_type: String) -> void:
	id = p_id
	mode = "put"
	url = p_url
	headers = p_headers
	bytes = p_bytes
	content_type = p_content_type

func configure_download(p_id: String, p_url: String, p_dest: String = "") -> void:
	id = p_id
	mode = "get_file" if p_dest != "" else "get"
	url = p_url
	dest = p_dest

func start() -> void:
	_req = HTTPRequest.new()
	_req.timeout = timeout
	_req.use_threads = OS.has_feature("standalone") or OS.has_feature("mobile")
	if mode == "get_file":
		_req.download_file = dest
	add_child(_req)
	_req.connect("request_completed", self, "_on_completed")
	var h := headers
	var err := OK
	if mode == "put":
		if content_type != "" and not _has_header(h, "Content-Type"):
			h.append("Content-Type: " + content_type)
		err = _req.request_raw(url, h, true, METHOD_PUT, bytes)
	elif mode == "get_file":
		err = _req.request_raw(url, h, true, METHOD_GET)
	else:
		err = _req.request_raw(url, h, true, METHOD_GET)
	if err != OK:
		call_deferred("_fail", err)

func cancel() -> void:
	if _req != null:
		_req.cancel_request()

func _has_header(p_headers: PoolStringArray, p_name: String) -> bool:
	var needle = p_name.to_lower() + ":"
	for h in p_headers:
		if h.to_lower().begins_with(needle):
			return true
	return false

func _on_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	# result == HTTPRequest.RESULT_SUCCESS (0) no basta: el servidor responde
	# 2xx. Un PUT suele devolver 200/201/204 (sin cuerpo).
	var ok = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var payload = body
	if mode == "get_file":
		payload = dest if ok else ""
	var error = ""
	if not ok:
		error = _error_for(result, response_code)
	print("xat-http: %s result=%d code=%d err=%s" % [mode, result, response_code, error])
	emit_signal("finished", id, ok, response_code, payload, error)
	call_deferred("queue_free")

func _fail(p_err: int) -> void:
	emit_signal("finished", id, false, 0, null, "no-se-pudo-iniciar-%d" % p_err)
	queue_free()

func _error_for(p_result: int, p_code: int) -> String:
	if p_result != HTTPRequest.RESULT_SUCCESS:
		return "red-%d" % p_result
	if p_code == 0:
		return "sin-respuesta"
	return "http-%d" % p_code
