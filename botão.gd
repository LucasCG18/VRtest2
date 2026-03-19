extends Area3D

## Sinais
signal button_pressed()
signal button_released()

## Configurações HTTP
@export_group("HTTP")
@export var http_enabled := true
@export var http_host := "192.168.1.118"
@export var http_port := 1880
@export var http_path := "/test/AR"

## Nós
@onready var mesh = $MeshInstance3D

## Estado
var is_pressed := false
var can_toggle := true
var last_toggle_time := 0
var cooldown_ms := 500

## HTTP
var http_pool = []


func _ready() -> void:
	#print("=== BOTÃO INICIALIZADO ===")
	_set_button_color(false)

	# Garante que os sinais estão conectados
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	
	#print("🔍 Corpos já em contato: ", get_overlapping_bodies())
	
	if http_enabled:
		_setup_http()
	#print("=== PRONTO ===\n")


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_F3):
		print("🔄 Overlapping bodies: ", get_overlapping_bodies())


# ============================================================
# FUNÇÃO PÚBLICA DE TOGGLE (NOVA - PODE SER CHAMADA DE FORA)
# ============================================================
func toggle_button(source_name: String, force_state: int = -1) -> void:
	var current_time = Time.get_ticks_msec()
	
	# Respeita o cooldown
	if current_time - last_toggle_time < cooldown_ms:
		return
	last_toggle_time = current_time

# Se force_state for -1, alterna. Se tiver valor, usa o valor forçado
	if  force_state == -1:
		is_pressed = !is_pressed
	elif force_state == 1:    
		is_pressed = true
	elif force_state == 0:
		is_pressed = false
	
	_set_button_color(is_pressed)

	if is_pressed:
		button_pressed.emit()
	#	print("🟢 Botão ATIVADO por: ", source_name)
		_send_http(1)
	else:
		button_released.emit()
	#	print("🔴 Botão DESATIVADO por: ", source_name)
		_send_http(0)


# ============================================================
# SINAIS ORIGINAIS (AGORA CHAMAM A FUNÇÃO PÚBLICA)
# ============================================================

func _on_body_entered(body: Node3D) -> void:
	#print("Entrou (body): ", body.name)
	toggle_button("body: " + body.name)  # Chama a função pública

func _on_area_entered(area: Area3D) -> void:
	#print("Entrou (area): ", area.name)
	toggle_button("area: " + area.name)  # Chama a função pública


# ============================================================
# FUNÇÕES VISUAIS E HTTP (MANTIDAS IGUAIS)
# ============================================================

func _set_button_color(pressed: bool) -> void:
	if not mesh:
		return

	var mat = StandardMaterial3D.new()
	if pressed:
		mat.albedo_color = Color(0, 1, 0)  # Verde = ativado
	else:
		mat.albedo_color = Color(1, 0, 0)  # Vermelho = desativado

	mesh.set_surface_override_material(0, mat)


func _setup_http():
	#print("\n⚡ === HTTP OTIMIZADO ===")
	#print("URL: http://", http_host, ":", http_port, http_path)

	for i in range(3):
		var http = HTTPRequest.new()
		http.timeout = 1.0
		http.use_threads = true
		add_child(http)
		http.request_completed.connect(_on_http_completed.bind(http))
		http_pool.append(http)

	#print("✅ Pool de ", http_pool.size(), " conexões!\n")


func _send_http(state: int) -> void:
	if not http_enabled:
		return

	var send_time = Time.get_ticks_msec()

	var payload = {
		"position": state,
		"percentage": state * 100,
		"timestamp_ms": send_time
	}

	var json_string = JSON.stringify(payload)

	var http = _get_available_http()
	if not http:
		http = HTTPRequest.new()
		http.timeout = 1.0
		http.use_threads = true
		add_child(http)
		http.request_completed.connect(_on_http_completed.bind(http))

	var url = "http://" + http_host + ":" + str(http_port) + http_path
	var headers = [
		"Content-Type: application/json",
		"Connection: keep-alive"
	]

	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_string)

	if error == OK:
		#print("⚡ [", send_time, "ms] Enviado: ", state * 100, "%")
		http.set_meta("send_time", send_time)
		http.set_meta("in_use", true)
	else:
		#print("❌ Erro ao enviar: ", error)
		http.set_meta("in_use", false)


func _get_available_http():
	for http in http_pool:
		if not http.get_meta("in_use", false):
			return http
	return null


func _on_http_completed(result, response_code, headers, body, http_node):
	var receive_time = Time.get_ticks_msec()
	var send_time = http_node.get_meta("send_time", 0)
	var latency = receive_time - send_time

	#if response_code == 200:
	#	print("✅ [", receive_time, "ms] OK | Latência: ", latency, "ms")
	#else:
	#	print("❌ Erro HTTP: ", response_code, " | Latência: ", latency, "ms")

	http_node.set_meta("in_use", false)
