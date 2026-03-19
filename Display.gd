extends XRAnchor3D

@export var listen_port: int = 8080
@export var fallback_port: int = 0
@export var bind_address: String = "0.0.0.0"
@export var expected_path: String = "/AR/SensoNODE/Variables"
@export var debug_enabled: bool = true
@export var debug_raw_http: bool = false

@onready var label: Label3D = $Label3D

static var _active_instance: Node = null

var server: TCPServer = TCPServer.new()
var clients: Array[Dictionary] = []
var server_started: bool = false

func _enter_tree() -> void:
	# Evita duas instancias do servidor ao mesmo tempo.
	if _active_instance != null and _active_instance != self:
		_dbg("Instancia duplicada detectada. Esta instancia nao iniciara servidor.")
		set_process(false)
		return

	_active_instance = self

func _ready() -> void:
	if _active_instance != self:
		label.text = "Servidor duplicado (ignorado)"
		return

	if get_parent() is XRAnchor3D:
		_dbg("Aviso: este node esta dentro de ancora visual e pode ser recriado quando tracking oscilar.")

	_start_server()

func _exit_tree() -> void:
	if _active_instance == self:
		_shutdown_server()
		_active_instance = null

func _start_server() -> void:
	_dbg("Inicializando servidor HTTP...")
	_dbg("Tentando bind em %s:%d" % [bind_address, listen_port])
	if listen_port < 1024:
		_dbg("Aviso: portas < 1024 costumam falhar por permissao/uso no dispositivo. Considere usar 8080.")

	var err: int = _try_listen(listen_port)
	if err != OK and fallback_port > 0 and fallback_port != listen_port:
		_dbg("Falha na porta %d. Tentando fallback na porta %d..." % [listen_port, fallback_port])
		err = _try_listen(fallback_port)
		if err == OK:
			listen_port = fallback_port

	if err != OK:
		label.text = "Erro servidor: %s" % _error_name(err)
		_dbg("ERRO: listen falhou com codigo %d (%s)" % [err, _error_name(err)])
		_dbg("Dica: evite porta 80 no Quest; use 8080 e configure o gateway para http://IP_DO_OCULUS:8080/AR/SensoNODE/Variables")
		server_started = false
		return

	server_started = true
	label.text = "Aguardando dados HTTP..."
	_dbg("Servidor ouvindo em %s:%d" % [bind_address, listen_port])

func _try_listen(port: int) -> int:
	if server.is_listening():
		server.stop()
	return server.listen(port, bind_address)

func _shutdown_server() -> void:
	if not server_started:
		return

	_dbg("Encerrando servidor e desconectando clientes...")
	for i in range(clients.size() - 1, -1, -1):
		var c: Dictionary = clients[i]
		var p: StreamPeerTCP = c["peer"] as StreamPeerTCP
		if p != null and p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			p.disconnect_from_host()

	clients.clear()
	server.stop()
	server_started = false
	_dbg("Servidor encerrado.")

func _process(_delta: float) -> void:
	if not server_started:
		return

	_accept_clients()
	_read_clients()

func _accept_clients() -> void:
	while server.is_connection_available():
		var peer: StreamPeerTCP = server.take_connection()
		if peer == null:
			continue

		var state: Dictionary = {
			"peer": peer,
			"buffer": ""
		}
		clients.append(state)
		_dbg("Novo cliente conectado. Ativos: %d" % clients.size())

func _read_clients() -> void:
	for i in range(clients.size() - 1, -1, -1):
		var state: Dictionary = clients[i]
		var peer: StreamPeerTCP = state["peer"] as StreamPeerTCP
		var buffer: String = state["buffer"] as String

		if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_dbg("Cliente desconectado antes de completar request.")
			clients.remove_at(i)
			continue

		var available: int = peer.get_available_bytes()
		if available > 0:
			var chunk: String = peer.get_utf8_string(available)
			buffer += chunk
			state["buffer"] = buffer
			clients[i] = state

			if debug_raw_http:
				_dbg("Chunk HTTP (%d bytes):\n%s" % [available, chunk])

		if not _request_is_complete(buffer):
			continue

		var req: Dictionary = _parse_http_request(buffer)
		var method: String = req["method"] as String
		var path: String = req["path"] as String
		var body: String = req["body"] as String

		_dbg("Request completa -> method=%s path=%s body_len=%d" % [method, path, body.length()])

		if method != "POST":
			label.text = "HTTP invalido: use POST"
			_dbg("Metodo rejeitado: %s" % method)
			_send_http_response(peer, 405, "METHOD NOT ALLOWED")
			_finalize_client(i, peer)
			continue

		if path != expected_path:
			label.text = "Rota invalida"
			_dbg("Path rejeitado: %s (esperado: %s)" % [path, expected_path])
			_send_http_response(peer, 404, "NOT FOUND")
			_finalize_client(i, peer)
			continue

		var metrics: Dictionary = _extract_metrics(body)
		if metrics.is_empty():
			label.text = "Payload invalido"
			_dbg("Payload nao reconhecido: %s" % body)
			_send_http_response(peer, 400, "BAD REQUEST")
			_finalize_client(i, peer)
			continue

		var temperature: Variant = metrics["temperature"]
		var pressure: Variant = metrics["pressure"]
		var flow: Variant = metrics["flow"]
		var nas_particle: Variant = metrics["nas_particle"]

		label.text = "Temp: %s C\nPress: %s\nFlow: %s\nNas: %s" % [
			str(temperature),
			str(pressure),
			str(flow),
			str(nas_particle)
		]

		_dbg("Dados aceitos: %s" % str(metrics))
		_send_http_response(peer, 200, "OK")
		_finalize_client(i, peer)

func _finalize_client(index: int, peer: StreamPeerTCP) -> void:
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()

	clients.remove_at(index)
	_dbg("Cliente finalizado. Ativos: %d" % clients.size())

func _request_is_complete(buffer: String) -> bool:
	var header_end: int = buffer.find("\r\n\r\n")
	if header_end < 0:
		return false

	var header_text: String = buffer.substr(0, header_end)
	var content_length: int = _get_content_length(header_text)

	var body_start: int = header_end + 4
	var total_needed: int = body_start + content_length
	return buffer.length() >= total_needed

func _parse_http_request(buffer: String) -> Dictionary:
	var header_end: int = buffer.find("\r\n\r\n")
	if header_end < 0:
		return {
			"method": "",
			"path": "",
			"body": ""
		}

	var header_text: String = buffer.substr(0, header_end)
	var body_all: String = buffer.substr(header_end + 4, buffer.length() - (header_end + 4))
	var content_length: int = _get_content_length(header_text)

	var body: String = body_all
	if content_length >= 0 and body_all.length() >= content_length:
		body = body_all.substr(0, content_length)

	var lines: PackedStringArray = header_text.split("\r\n", false)
	var first_line: String = ""
	if lines.size() > 0:
		first_line = lines[0]

	var method: String = ""
	var path: String = ""
	var parts: PackedStringArray = first_line.split(" ", false)
	if parts.size() >= 2:
		method = parts[0].strip_edges().to_upper()
		path = parts[1].strip_edges()

	return {
		"method": method,
		"path": path,
		"body": body
	}

func _get_content_length(header_text: String) -> int:
	var lines: PackedStringArray = header_text.split("\r\n", false)
	for line in lines:
		var l: String = line.strip_edges()
		var lower: String = l.to_lower()
		if lower.begins_with("content-length:"):
			var value_str: String = l.substr("content-length:".length(), l.length() - "content-length:".length()).strip_edges()
			if value_str.is_valid_int():
				return int(value_str)
			return 0

	return 0

func _extract_metrics(body: String) -> Dictionary:
	if body.is_empty():
		_dbg("Body vazio.")
		return {}

	var json: JSON = JSON.new()
	var parse_result: int = json.parse(body)
	if parse_result != OK:
		_dbg("Erro JSON: %s (linha %d)" % [json.get_error_message(), json.get_error_line()])
		return {}

	var data: Variant = json.data
	var obj: Dictionary = {}

	# Caso 1: [{...}]
	if typeof(data) == TYPE_ARRAY:
		var arr: Array = data
		if arr.is_empty():
			_dbg("Array vazio.")
			return {}

		var first_item: Variant = arr[0]
		if typeof(first_item) != TYPE_DICTIONARY:
			_dbg("Primeiro item do array nao e objeto.")
			return {}

		obj = first_item as Dictionary

	# Caso 2: {...}
	elif typeof(data) == TYPE_DICTIONARY:
		obj = data as Dictionary

	else:
		_dbg("Tipo de payload nao suportado: %d" % typeof(data))
		return {}

	return {
		"temperature": obj.get("temperature", null),
		"pressure": obj.get("pressure", null),
		"flow": obj.get("flow", null),
		"nas_particle": obj.get("nas_particle", null)
	}

func _send_http_response(peer: StreamPeerTCP, status_code: int, body: String) -> void:
	var status_text: String = "OK"
	if status_code == 400:
		status_text = "BAD REQUEST"
	elif status_code == 404:
		status_text = "NOT FOUND"
	elif status_code == 405:
		status_text = "METHOD NOT ALLOWED"
	elif status_code != 200:
		status_text = "ERROR"

	var response: String = "HTTP/1.1 %d %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
		status_code, status_text, body.length(), body
	]
	peer.put_data(response.to_utf8_buffer())
	_dbg("Resposta enviada: %d %s" % [status_code, status_text])

func _error_name(code: int) -> String:
	match code:
		OK:
			return "OK"
		ERR_INVALID_PARAMETER:
			return "ERR_INVALID_PARAMETER"
		ERR_ALREADY_IN_USE:
			return "ERR_ALREADY_IN_USE"
		ERR_CANT_CREATE:
			return "ERR_CANT_CREATE"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		_:
			return "ERR_%d" % code

func _dbg(msg: String) -> void:
	if not debug_enabled:
		return
	var ts: String = Time.get_datetime_string_from_system()
	print("[HTTP-DISPLAY %s] %s" % [ts, msg])
