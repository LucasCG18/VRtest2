extends XROrigin3D

func _ready():
	print("=== Iniciando XR ===")
	
	var xr_interface = XRServer.find_interface("OpenXR")
	
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR OK!")
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		get_viewport().transparent_bg = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		print("OpenXR não inicializado pelo sistema!")
		print("Tentando forçar...")
		if xr_interface and xr_interface.initialize():
			get_viewport().use_xr = true
			print("OpenXR forçado com sucesso!")
		else:
			print("Falha total no OpenXR")
