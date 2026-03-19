extends Node

@export var cena_da_imagem: PackedScene
@export_enum("AprilTag", "Aruco", "QRCode") var tipo_marker_alvo: int = 2
@export var id_tag_alvo: int = 586
@export var qrcode_texto_alvo: String = ""
@export var tempo_para_apagar_segundos: float = 2.0
@export var intervalo_atualizacao_segundos: float = 1
@export var frames_visiveis_para_spawn: int = 2
@export_range(1, 120, 1) var frames_invisiveis_para_remover: int = 2
@export var exigir_texto_qrcode: bool = true
@export var filtrar_tamanho_qrcode: bool = true
@export var qrcode_lado_min_m: float = 0.03
@export var qrcode_lado_max_m: float = 0.20

var marcadores_ativos: Dictionary = {}
var ultimo_update_marcador_ms: Dictionary = {}
var _contagem_visivel_por_tracker: Dictionary = {}
var _contagem_invisivel_por_tracker: Dictionary = {}
var _acumulador_atualizacao_s: float = 0.0

func _ready():
	print("\n[DEBUG] ======= INICIANDO SPATIAL MANAGER =======")
	
	if not cena_da_imagem:
		push_error("[ERRO GRAVE] Defina 'cena_da_imagem' no Inspector.")
		return

	# Reage aos trackers que o XRServer adicionar/remover.
	XRServer.tracker_added.connect(_on_tracker_added)
	XRServer.tracker_updated.connect(_on_tracker_updated)
	XRServer.tracker_removed.connect(_on_tracker_removed)

	# Processa trackers que ja existiam antes deste node entrar na arvore.
	_debug_dump_anchor_trackers("boot")
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANCHOR)
	for tracker_name in trackers:
		_on_tracker_added(tracker_name, XRServer.TRACKER_ANCHOR)

	# Novo snapshot apos alguns segundos para confirmar se algum tracker apareceu.
	_call_delayed_tracker_dump()
	
	print("[DEBUG] Sinais conectados. Aguardando marcadores visuais...")

func _call_delayed_tracker_dump() -> void:
	await get_tree().create_timer(3.0).timeout
	_debug_marker_capabilities()
	_debug_dump_anchor_trackers("t+3s")

func _debug_marker_capabilities() -> void:
	if not ClassDB.class_exists("OpenXRSpatialMarkerTrackingCapability"):
		print("[DEBUG] Marker capability class nao encontrada neste build.")
		return

	print("[DEBUG] Classes marker config disponiveis | april_cfg=",
		ClassDB.class_exists("OpenXRSpatialCapabilityConfigurationAprilTag"),
		" | aruco_cfg=", ClassDB.class_exists("OpenXRSpatialCapabilityConfigurationAruco"),
		" | qr_cfg=", ClassDB.class_exists("OpenXRSpatialCapabilityConfigurationQrCode"),
		" | micro_qr_cfg=", ClassDB.class_exists("OpenXRSpatialCapabilityConfigurationMicroQrCode"))

	# Lista os metodos expostos pela classe nesta versao para diagnostico.
	var methods: Array = ClassDB.class_get_method_list("OpenXRSpatialMarkerTrackingCapability")
	var method_names: PackedStringArray = []
	for method_info in methods:
		if method_info is Dictionary and method_info.has("name"):
			method_names.push_back(String(method_info["name"]))

	print("[DEBUG] OpenXRSpatialMarkerTrackingCapability methods: ", method_names)

	# Consulta suporte do runtime usando o singleton da engine.
	var cap = OpenXRSpatialMarkerTrackingCapability
	var april_supported = cap.call("is_april_tag_supported") if cap.has_method("is_april_tag_supported") else null
	var aruco_supported = cap.call("is_aruco_supported") if cap.has_method("is_aruco_supported") else null
	var qr_supported = cap.call("is_qrcode_supported") if cap.has_method("is_qrcode_supported") else null
	var micro_qr_supported = cap.call("is_micro_qrcode_supported") if cap.has_method("is_micro_qrcode_supported") else null

	print("[DEBUG] Runtime marker support | april=", april_supported,
		" | aruco=", aruco_supported,
		" | qr=", qr_supported,
		" | micro_qr=", micro_qr_supported)

func _debug_dump_anchor_trackers(contexto: String) -> void:
	var anchors: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANCHOR)
	print("[DEBUG] Snapshot ", contexto, " | trackers de ancora: ", anchors.size())
	for tracker_name in anchors:
		var t: XRTracker = anchors[tracker_name]
		if t:
			print("[DEBUG]  - ", tracker_name, " | classe=", t.get_class())

func _on_tracker_added(tracker_name: StringName, type: int):
	print("[DEBUG] tracker_added evento: ", tracker_name, " | type=", type)

	if type != XRServer.TRACKER_ANCHOR:
		return

	var tracker: XRTracker = XRServer.get_tracker(tracker_name)
	if tracker == null:
		return

	if not (tracker is OpenXRMarkerTracker):
		return

	var marker_tracker: OpenXRMarkerTracker = tracker
	print("[DEBUG] OpenXRMarkerTracker registrado: ", tracker_name, " | type=", marker_tracker.marker_type, " | id=", marker_tracker.marker_id)
	_try_spawn_visual_for_tracker(tracker_name, marker_tracker)

func _process(delta: float) -> void:
	_acumulador_atualizacao_s += delta
	if _acumulador_atualizacao_s < intervalo_atualizacao_segundos:
		return
	_acumulador_atualizacao_s = 0.0

	# Reconcilia trackers continuamente para permitir respawn do MESMO QR code
	# quando o runtime mantem o tracker e nao dispara tracker_added novamente.
	var anchors: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANCHOR)
	for tracker_name in anchors:
		var tracker: XRTracker = anchors[tracker_name]
		if tracker is OpenXRMarkerTracker:
			_try_spawn_visual_for_tracker(tracker_name, tracker)

	if marcadores_ativos.is_empty():
		return

	var agora_ms := Time.get_ticks_msec()
	var ativos: Array = marcadores_ativos.keys()
	for tracker_name in ativos:
		if not ultimo_update_marcador_ms.has(tracker_name):
			continue

		var ultimo_ms: int = int(ultimo_update_marcador_ms[tracker_name])
		var sem_update_s: float = float(agora_ms - ultimo_ms) / 1000.0
		if sem_update_s > tempo_para_apagar_segundos:
			_remover_visual(tracker_name, "timeout sem update")

func _try_spawn_visual_for_tracker(tracker_name: StringName, marker_tracker: OpenXRMarkerTracker) -> void:
	if not _marker_bate_com_filtro(marker_tracker):
		_contagem_visivel_por_tracker.erase(tracker_name)
		if marcadores_ativos.has(tracker_name):
			_remover_visual(tracker_name, "marker nao bate com filtro")
		return

	if not _marker_esta_visivel(marker_tracker):
		var contagem_invisivel_atual: int = int(_contagem_invisivel_por_tracker.get(tracker_name, 0)) + 1
		_contagem_invisivel_por_tracker[tracker_name] = contagem_invisivel_atual
		_contagem_visivel_por_tracker[tracker_name] = 0

		if marcadores_ativos.has(tracker_name) and contagem_invisivel_atual >= max(1, frames_invisiveis_para_remover):
			_remover_visual(tracker_name, "tracking instavel/invisivel")
		return

	_contagem_invisivel_por_tracker.erase(tracker_name)

	var contagem_visivel_atual: int = int(_contagem_visivel_por_tracker.get(tracker_name, 0)) + 1
	_contagem_visivel_por_tracker[tracker_name] = contagem_visivel_atual
	if contagem_visivel_atual < max(1, frames_visiveis_para_spawn):
		return

	ultimo_update_marcador_ms[tracker_name] = Time.get_ticks_msec()

	if marcadores_ativos.has(tracker_name):
		return

	var nova_imagem: Node = cena_da_imagem.instantiate()
	if not (nova_imagem is XRAnchor3D):
		push_error("[ERRO] 'cena_da_imagem' precisa ter XRAnchor3D na raiz.")
		nova_imagem.queue_free()
		return

	nova_imagem.tracker = tracker_name
	add_child(nova_imagem)
	marcadores_ativos[tracker_name] = nova_imagem
	print("[DEBUG] Visual criado para marker alvo.")

func _marker_esta_visivel(marker_tracker: OpenXRMarkerTracker) -> bool:
	var bounds: Vector2 = marker_tracker.bounds_size
	var tem_bounds: bool = bounds.length_squared() > 0.0

	if filtrar_tamanho_qrcode and marker_tracker.marker_type == OpenXRSpatialComponentMarkerList.MARKER_TYPE_QRCODE:
		var lado: float = max(bounds.x, bounds.y)
		if lado < qrcode_lado_min_m or lado > qrcode_lado_max_m:
			print("[DEBUG] Ignorando QR por tamanho fora da faixa. lado=", lado,
				" | faixa=[", qrcode_lado_min_m, ", ", qrcode_lado_max_m, "]")
			return false

	if marker_tracker is OpenXRSpatialEntityTracker:
		var spatial_tracker: OpenXRSpatialEntityTracker = marker_tracker
		return spatial_tracker.spatial_tracking_state == OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_TRACKING and tem_bounds

	return tem_bounds

func _marker_bate_com_filtro(marker_tracker: OpenXRMarkerTracker) -> bool:
	match tipo_marker_alvo:
		0: # AprilTag
			return marker_tracker.marker_type == OpenXRSpatialComponentMarkerList.MARKER_TYPE_APRIL_TAG \
				and marker_tracker.marker_id == id_tag_alvo
		1: # Aruco
			return marker_tracker.marker_type == OpenXRSpatialComponentMarkerList.MARKER_TYPE_ARUCO \
				and marker_tracker.marker_id == id_tag_alvo
		2: # QRCode
			if marker_tracker.marker_type != OpenXRSpatialComponentMarkerList.MARKER_TYPE_QRCODE:
				return false

			var texto_detectado: String = _extrair_texto_qrcode(marker_tracker)
			if exigir_texto_qrcode and qrcode_texto_alvo.is_empty():
				print("[DEBUG] qrcode_texto_alvo vazio com exigir_texto_qrcode=true. Ignorando marcador.")
				return false

			if qrcode_texto_alvo.is_empty():
				return true

			return texto_detectado == qrcode_texto_alvo.strip_edges()
		_:
			return false

func _extrair_texto_qrcode(marker_tracker: OpenXRMarkerTracker) -> String:
	var data: Variant = marker_tracker.get_marker_data()
	if typeof(data) == TYPE_STRING:
		return String(data).strip_edges()
	if typeof(data) == TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray(data).get_string_from_utf8().strip_edges()
	return ""

func _on_tracker_removed(tracker_name: StringName, type: int):
	if type != XRServer.TRACKER_ANCHOR:
		return

	_contagem_visivel_por_tracker.erase(tracker_name)
	_contagem_invisivel_por_tracker.erase(tracker_name)
	ultimo_update_marcador_ms.erase(tracker_name)

	if marcadores_ativos.has(tracker_name):
		print("[DEBUG] A câmera perdeu a tag de vista. Removendo...")
		var imagem_para_remover = marcadores_ativos[tracker_name]
		if is_instance_valid(imagem_para_remover):
			imagem_para_remover.queue_free()
		marcadores_ativos.erase(tracker_name)

func _on_tracker_updated(tracker_name: StringName, type: int):
	if type != XRServer.TRACKER_ANCHOR:
		return

	var tracker: XRTracker = XRServer.get_tracker(tracker_name)
	if tracker == null:
		_remover_visual(tracker_name, "tracker nulo no update")
		return

	if tracker is OpenXRMarkerTracker:
		var marker_tracker: OpenXRMarkerTracker = tracker
		_try_spawn_visual_for_tracker(tracker_name, marker_tracker)

	if not marcadores_ativos.has(tracker_name):
		return

	if not (tracker is OpenXRSpatialEntityTracker):
		return

func _remover_visual(tracker_name: StringName, motivo: String) -> void:
	if not marcadores_ativos.has(tracker_name):
		return

	print("[DEBUG] Removendo visual de ", tracker_name, " | motivo: ", motivo)
	var imagem_para_remover = marcadores_ativos[tracker_name]
	if is_instance_valid(imagem_para_remover):
		imagem_para_remover.queue_free()
	marcadores_ativos.erase(tracker_name)
	ultimo_update_marcador_ms.erase(tracker_name)
	_contagem_visivel_por_tracker.erase(tracker_name)
	_contagem_invisivel_por_tracker.erase(tracker_name)
