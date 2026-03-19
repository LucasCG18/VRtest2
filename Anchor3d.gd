extends XRAnchor3D

@export var cena_da_imagem: PackedScene 

var marcadores_ativos = {}

func _ready():
	print("\n[DEBUG] ======= INICIANDO SPATIAL MANAGER =======")
	
	# Validação número 1: Você lembrou de arrastar a cena no Inspetor?
	if not cena_da_imagem:
		push_error("[ERRO GRAVE] Você não arrastou a 'cena_da_imagem' no Inspetor do Godot!")
	else:
		print("[DEBUG] Cena da imagem carregada com sucesso: ", cena_da_imagem.resource_path)

	print("[DEBUG] Criando configuracao para AprilTag 36H11...")
	var config_april = OpenXRSpatialCapabilityConfigurationAprilTag.new()
	config_april.april_dict = OpenXRSpatialCapabilityConfigurationAprilTag.APRIL_TAG_DICT_36H11
	
	print("[DEBUG] Chamando OpenXRSpatialEntityExtension.create_spatial_context()...")
	# Tenta iniciar a câmera para ler as tags
	var contexto_criado = OpenXRSpatialEntityExtension.create_spatial_context([config_april])
	print("[DEBUG] Retorno do create_spatial_context (deve ser true/ok): ", contexto_criado)
	
	print("[DEBUG] Conectando sinais do XRServer...")
	XRServer.tracker_added.connect(_on_tracker_added)
	XRServer.tracker_removed.connect(_on_tracker_removed)
	
	print("[DEBUG] ======= SPATIAL MANAGER PRONTO! AGUARDANDO HEADSET =======\n")

func _on_tracker_added(tracker_name: StringName, type: int):
	print("\n[DEBUG-EVENTO] >>> SINAL tracker_added DISPARADO! <<<")
	print("[DEBUG] Nome do tracker recebido: ", tracker_name)
	
	# Tenta recuperar o objeto que acabou de ser detectado
	var tracker = XRServer.get_tracker(tracker_name)
	
	if tracker == null:
		print("[ERRO] XRServer.get_tracker retornou null para o nome: ", tracker_name)
		return
		
	print("[DEBUG] Objeto rastreado com sucesso. Classe nativa: ", tracker.get_class())
	
	# O XRServer rastreia TUDO (Headset, Controles da mão, etc).
	# Precisamos ter certeza de que o que ele achou foi uma TAG visual.
	if tracker is OpenXRMarkerTracker:
		print("[DEBUG] SUCESSO! O tracker É um marcador visual (OpenXRMarkerTracker)!")
		
		# Vamos imprimir o que ele achou pra ver se ele não está achando que é um QR Code
		print("[DEBUG] Tipo de marcador (marker_type): ", tracker.marker_type)
		print("[DEBUG] ID da tag lido (marker_id): ", tracker.marker_id)
		
		var id_da_tag = tracker.marker_id
		
		if id_da_tag == 586:
			print("[DEBUG] 🔥 MATCH PERFEITO! AprilTag 586 encontrada na câmera!")
			
			# Evita spawnar duas imagens na mesma tag se houver um glitch na câmera
			if marcadores_ativos.has(tracker_name):
				print("[DEBUG] AVISO: Já existe uma imagem nesta tag. Ignorando...")
				return
			
			print("[DEBUG] Instanciando a cena da imagem...")
			var nova_imagem = cena_da_imagem.instantiate()
			add_child(nova_imagem)
			
			print("[DEBUG] Configurando a propriedade 'tracker' do XRAnchor3D para grudar no real...")
			nova_imagem.tracker = tracker_name
			
			marcadores_ativos[tracker_name] = nova_imagem
			print("[DEBUG] Spawn 100% finalizado! Marcadores ativos no momento: ", marcadores_ativos.size())
			
		else:
			print("[DEBUG] A tag lida NÃO é a 586. Ignorando esse spawn.")
	else:
		# Quando você mexe as mãos ou a cabeça, ele vai printar isso aqui. É normal!
		print("[DEBUG] O tracker encontrado não é um marcador (provavelmente é a cabeça ou controle). Ignorando...")

func _on_tracker_removed(tracker_name: StringName, type: int):
	print("\n[DEBUG-EVENTO] <<< SINAL tracker_removed DISPARADO! <<<")
	print("[DEBUG] Rastreador perdido pela câmera: ", tracker_name)
	
	if marcadores_ativos.has(tracker_name):
		print("[DEBUG] A câmera perdeu de vista a nossa AprilTag 586! Deletando a imagem 3D...")
		var imagem_para_remover = marcadores_ativos[tracker_name]
		
		if is_instance_valid(imagem_para_remover):
			imagem_para_remover.queue_free()
			print("[DEBUG] Nó da imagem destruído com sucesso (queue_free).")
			
		marcadores_ativos.erase(tracker_name)
		print("[DEBUG] Tag removida do dicionário. Marcadores ativos: ", marcadores_ativos.size())
