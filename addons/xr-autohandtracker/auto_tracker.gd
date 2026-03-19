extends Node3D

# The autotracker is swapped onto the xr_controller_node when hand-tracking is active 
# so that we can insert in our own button and float signals from the hand gestures, 
# as well as setting the pose from the xr_aimpose (which is filtered by the system during hand tracking)
# Calling set_pose emits a pose_changed signal that copies its values into the xr_controller_node 
var xr_autotracker : XRPositionalTracker = null
var xr_autopose : XRPose = null
var autotrackeractive = false
var hand_side : String = "right"  # Será definido automaticamente no setupautotracker()
var hand_is_left : bool = false   # Recebe do HandTracker
@export var target_button_path : NodePath
var target_button : Area3D = null

var graspsqueezer = SqueezeButton.new()
var pinchsqueezer = SqueezeButton.new()

# ==========================================
# NOVAS VARIÁVEIS PARA DEBUG
# ==========================================
@export var debug_print_gestures : bool = true  # Ativa/Desativa os prints
@export var debug_min_change : float = 0.15     # Mudança mínima para printar (0.0 a 1.0)
@export var debug_cooldown : float = 0.2        # Tempo mínimo entre prints (segundos)

var _debug_timers = {}  # Armazena o tempo do último print por gesto
var _debug_last_values = {}  # Armazena o último valor printado por gesto

# ==========================================
# FUNÇÕES DE DEBUG
# ==========================================
func _debug_print_gesture(gesture_name, value, is_button=false):
	if not debug_print_gestures:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var last_time = _debug_timers.get(gesture_name, -999.0)
	var last_value = _debug_last_values.get(gesture_name, -999.0)
	
	# Verifica se passou o tempo de cooldown
	if current_time - last_time < debug_cooldown:
		return
	
	# Se for analógico, verifica se a mudança é significativa
	if not is_button:
		if abs(value - last_value) < debug_min_change:
			return
	
	# Atualiza memória
	_debug_timers[gesture_name] = current_time
	_debug_last_values[gesture_name] = value

# Called when the node enters the scene tree for the first time.
func _ready():
	$ThumbstickBoundaries/InnerRing.mesh.outer_radius = innerringrad
	$ThumbstickBoundaries/InnerRing.mesh.inner_radius = 0.95*innerringrad
	$ThumbstickBoundaries/OuterRing.mesh.outer_radius = outerringrad
	$ThumbstickBoundaries/OuterRing.mesh.inner_radius = 0.95*outerringrad
	$ThumbstickBoundaries/UpDisc.transform.origin.y = updowndistbutton
	$ThumbstickBoundaries/DownDisc.transform.origin.y = -updowndistbutton
	print("✅ AutoTracker pronto. Debug de gestos: ", "ATIVADO" if debug_print_gestures else "DESATIVADO")
	if target_button_path:
		var node = get_node_or_null(target_button_path)
		if node and node is Area3D:
			target_button = node
			print("✅ Botão conectado: ", target_button.name)
		else:
			print("❌ Erro: Nó não encontrado ou não é Area3D")
			print("   Nó encontrado: ", node)
	else:
		print("⚠️ Target Button Path não configurado")
	print("🖐️ AutoTracker configurado para mão: ", hand_side.to_upper())

func setupautotracker(tracker_nhand, islefthand, xr_controller_node):
	xr_autotracker = XRPositionalTracker.new()
	xr_autotracker.hand = tracker_nhand
	xr_autotracker.name = "left_autohand" if islefthand else "right_autohand"
	xr_autotracker.profile = "/interaction_profiles/autohand" # "/interaction_profiles/none"
	xr_autotracker.type = 2

	xr_autotracker.set_pose(xr_controller_node.pose, Transform3D(), Vector3(), Vector3(), XRPose.TrackingConfidence.XR_TRACKING_CONFIDENCE_NONE)
	xr_autopose = xr_autotracker.get_pose(xr_controller_node.pose)

	hand_is_left = islefthand
	hand_side = "left" if islefthand else "right"
	print("🖐️ AutoTracker configurado para mão: ", hand_side.to_upper())
	# Passa a referência de debug para os squeezers
	graspsqueezer.setinputstrings(xr_autotracker, "grip", "", "grip_click")
	graspsqueezer.set_debug(self, "GRIP (Agarrar)")
	
	pinchsqueezer.setinputstrings(xr_autotracker, "trigger", "trigger_touch", "trigger_click")
	pinchsqueezer.set_debug(self, "PINCH (Gatilho)")
	
	XRServer.add_tracker(xr_autotracker)
	print("🔧 AutoTracker configurado para mão: ", "ESQUERDA" if islefthand else "DIREITA")

func activateautotracker(xr_controller_node):
	xr_controller_node.set_tracker(xr_autotracker.name)
	autotrackeractive = true
	#print("✅ AutoTracker ATIVADO")
	
func deactivateautotracker(xr_controller_node, xr_tracker):
	visible = false
	setaxbybuttonstatus(0)
	graspsqueezer.applysqueeze(graspsqueezer.touchbuttondistance + 1)	
	pinchsqueezer.applysqueeze(pinchsqueezer.touchbuttondistance + 1)	
	xr_controller_node.set_tracker(xr_tracker.name)
	autotrackeractive = false
	#print("⚠️ AutoTracker DESATIVADO (Hand Tracking perdido ou desligado)")

func autotrackgestures(oxrjps, xrt, xr_camera_node):
	thumbsticksimulation(oxrjps, xrt, xr_camera_node)

	# detect forming a fist
	var middleknuckletip = (oxrjps[OpenXRInterface.HAND_JOINT_MIDDLE_TIP] - oxrjps[OpenXRInterface.HAND_JOINT_MIDDLE_PROXIMAL]).length()
	var ringknuckletip = (oxrjps[OpenXRInterface.HAND_JOINT_RING_TIP] - oxrjps[OpenXRInterface.HAND_JOINT_RING_PROXIMAL]).length()
	var littleknuckletip = (oxrjps[OpenXRInterface.HAND_JOINT_LITTLE_TIP] - oxrjps[OpenXRInterface.HAND_JOINT_LITTLE_PROXIMAL]).length()
	var avgknuckletip = (middleknuckletip + ringknuckletip + littleknuckletip)/3
	graspsqueezer.applysqueeze(avgknuckletip)

	# detect the finger pinch
	var pinchdist = (oxrjps[OpenXRInterface.HAND_JOINT_INDEX_TIP] - oxrjps[OpenXRInterface.HAND_JOINT_THUMB_TIP]).length()
	pinchsqueezer.applysqueeze(pinchdist*2)

	#$GraspMarker.global_transform.origin = xrt*oxrjps[OpenXRInterface.HAND_JOINT_MIDDLE_TIP] 
	#$GraspMarker.visible = buttoncurrentlyclicked
	
	
	
var thumbstickstartpt = null
const thumbdistancecontact = 0.025
const thumbdistancerelease = 0.045
const innerringrad = 0.05
const outerringrad = 0.22
const updowndisttouch = 0.08
const updowndistbutton = 0.12
var thumbsticktouched = false
var axbybuttonstatus = 0 # -2:by_button, -1:by_touch, 1:ax_touch, 1:ax_button
var by_is_up = true

	
func setaxbybuttonstatus(newaxbybuttonstatus):
	if axbybuttonstatus == newaxbybuttonstatus:
		return
	
	# Debug para botões A/B/X/Y
	var button_names = {
		2: "A_BUTTON", -2: "B_BUTTON",
		1: "A_TOUCH", -1: "B_TOUCH",
		0: "NONE"
	}
	if axbybuttonstatus != 0:
		_debug_print_gesture(button_names.get(abs(axbybuttonstatus), "UNKNOWN"), false, true)
	
	if abs(axbybuttonstatus) == 2:
		xr_autotracker.set_input("ax_button" if axbybuttonstatus > 0 else "by_button", false)
		axbybuttonstatus = 1 if axbybuttonstatus > 0 else -1
	if axbybuttonstatus == newaxbybuttonstatus:
		return
	xr_autotracker.set_input("ax_touch" if axbybuttonstatus > 0 else "by_touch", false)
	axbybuttonstatus = 0
	if axbybuttonstatus == newaxbybuttonstatus:
		return
	xr_autotracker.set_input("ax_touch" if newaxbybuttonstatus > 0 else "by_touch", true)
	axbybuttonstatus = 1 if newaxbybuttonstatus > 0 else -1
	if axbybuttonstatus == newaxbybuttonstatus:
		return
	xr_autotracker.set_input("ax_button" if newaxbybuttonstatus > 0 else "by_button", true)
	axbybuttonstatus = newaxbybuttonstatus
	
	# Debug ao ativar novo botão
	if newaxbybuttonstatus != 0:
		_debug_print_gesture(button_names.get(abs(newaxbybuttonstatus), "UNKNOWN"), true, true)

func thumbsticksimulation(oxrjps, xrt, xr_camera_node):
	var middletip = oxrjps[OpenXRInterface.HAND_JOINT_MIDDLE_TIP]
	var thumbtip = oxrjps[OpenXRInterface.HAND_JOINT_THUMB_TIP]
	var ringtip = oxrjps[OpenXRInterface.HAND_JOINT_RING_TIP]
	var tipcen = (middletip + thumbtip + ringtip)/3.0
	var middleknuckle = oxrjps[OpenXRInterface.HAND_JOINT_MIDDLE_PROXIMAL]
	var thumbdistance = max((middletip - tipcen).length(), (thumbtip - tipcen).length(), (ringtip - tipcen).length())
	if thumbstickstartpt == null:
		if thumbdistance < thumbdistancecontact and middleknuckle.y < tipcen.y - 0.029:
			thumbstickstartpt = tipcen
			visible = true
			global_transform.origin = xrt*tipcen
			$ThumbstickBoundaries.global_transform.origin = xrt*thumbstickstartpt
			_debug_print_gesture("THUMBSTICK_ATIVADO", 1.0, true)
	else:
		if thumbdistance > thumbdistancerelease:
			thumbstickstartpt = null
			if thumbsticktouched:
				xr_autotracker.set_input("primary", Vector2(0.0, 0.0))
				xr_autotracker.set_input("primary_touch", true)
				thumbsticktouched = false
			setaxbybuttonstatus(0)
			_debug_print_gesture("THUMBSTICK_DESATIVADO", 0.0, true)

	visible = (thumbstickstartpt != null)
	if thumbstickstartpt != null:
		$DragRod.global_transform = sticktransformB(xrt*thumbstickstartpt, xrt*tipcen)
		var facingangle = Vector2(xr_camera_node.transform.basis.z.x, xr_camera_node.transform.basis.z.z).angle() if xr_camera_node != null else 0.0
		var hvec = Vector2(tipcen.x - thumbstickstartpt.x, tipcen.z - thumbstickstartpt.z)
		var hv = hvec.rotated(deg_to_rad(90) - facingangle)
		var hvlen = hv.length()
		if not thumbsticktouched:
			var frat = hvlen/max(hvlen, innerringrad)
			frat = frat*frat*frat 
			$ThumbstickBoundaries/InnerRing.get_surface_override_material(0).albedo_color.a = frat
			$ThumbstickBoundaries/OuterRing.get_surface_override_material(0).albedo_color.a = frat
			if hvlen > innerringrad:
				xr_autotracker.set_input("primary_touch", true)
				thumbsticktouched = true
				_debug_print_gesture("THUMBSTICK_TOUCH", 1.0, true)
			
		if thumbsticktouched:
			var hvN = hv/max(hvlen, outerringrad)
			xr_autotracker.set_input("primary", Vector2(hvN.x, -hvN.y))
			# Debug da intensidade do analógico (média dos eixos)
			var stick_intensity = (abs(hvN.x) + abs(hvN.y)) / 2.0
			_debug_print_gesture("THUMBSTICK_ANALOG", stick_intensity, false)

		var ydist = (tipcen.y - thumbstickstartpt.y)
		var rawnewaxbybuttonstatus = 0
		if ydist > updowndisttouch:
			$ThumbstickBoundaries/UpDisc.visible = true
			$ThumbstickBoundaries/UpDisc.get_surface_override_material(0).albedo_color.a = (ydist - updowndisttouch)/(updowndistbutton - updowndisttouch)*0.5 if ydist < updowndistbutton else 1.0
			rawnewaxbybuttonstatus = 2 if ydist > updowndistbutton else 1
		else:
			$ThumbstickBoundaries/UpDisc.visible = false
		if ydist < -updowndisttouch:
			$ThumbstickBoundaries/DownDisc.visible = true
			$ThumbstickBoundaries/DownDisc.get_surface_override_material(0).albedo_color.a = (-ydist - updowndisttouch)/(updowndistbutton - updowndisttouch)*0.5 if -ydist < updowndistbutton else 1.0
			rawnewaxbybuttonstatus = -2 if -ydist > updowndistbutton else -1
		else:
			$ThumbstickBoundaries/DownDisc.visible = false
		setaxbybuttonstatus(rawnewaxbybuttonstatus*(1 if by_is_up else -1))


class SqueezeButton:
	const touchbuttondistance = 0.07
	const depressbuttondistance = 0.04
	const clickbuttononratio = 0.95
	const clickbuttonoffratio = 0.85

	var xr_autotracker = null
	var squeezestring = ""
	var touchstring = ""
	var clickstring = ""
	
	var buttoncurrentlyclicked = false
	var buttoncurrentlytouched = false
	var button_trigger_sent = false
	# Variáveis de Debug
	var debug_parent = null
	var gesture_name = ""
	
	func set_debug(parent, name):
		debug_parent = parent
		gesture_name = name
	
	func setinputstrings(lxr_autotracker, lsqueezestring, ltouchstring, lclickstring):
		xr_autotracker = lxr_autotracker
		squeezestring = lsqueezestring
		touchstring = ltouchstring
		clickstring = lclickstring
	
	func xrsetinput(name, value):
		if xr_autotracker and name:
			xr_autotracker.set_input(name, value)

	func applysqueeze(squeezedistance):
		var buttonratio = min(inverse_lerp(touchbuttondistance, depressbuttondistance, squeezedistance), 1.0)
		if buttonratio < 0.0:
			if buttoncurrentlytouched:
				xrsetinput(squeezestring, 0.0)
				xrsetinput(touchstring, false)
				buttoncurrentlytouched = false
				if debug_parent:
					debug_parent._debug_print_gesture(gesture_name, 0.0, false)
		else:
			xrsetinput(squeezestring, buttonratio)
			if not buttoncurrentlytouched:
				xrsetinput(touchstring, true)
				buttoncurrentlytouched = true
				if debug_parent:
					debug_parent._debug_print_gesture(gesture_name + "_TOUCH", 1.0, true)
			
			# Debug da intensidade analógica
			if debug_parent:
				debug_parent._debug_print_gesture(gesture_name, buttonratio, false)
				
		var buttonclicked = (buttonratio > (clickbuttonoffratio if buttoncurrentlyclicked else clickbuttononratio))
		if buttonclicked != buttoncurrentlyclicked:
			xrsetinput(clickstring, buttonclicked)
			buttoncurrentlyclicked = buttonclicked
			if debug_parent:
				debug_parent._debug_print_gesture(gesture_name + "_CLICK", buttonclicked, true)
			if buttonclicked and debug_parent and debug_parent.target_button:
				var should_turn_on = 1 if debug_parent.hand_side == "right" else 0
				# Aciona apenas quando o clique é PRESSIONADO (não quando é solto)
				debug_parent.target_button.toggle_button("pinça (mão " + debug_parent.hand_side + ")", should_turn_on)
				#print("🎯 Botão ", "ATIVADO" if should_turn_on == 1 else "DESATIVADO", " via pinça (mão ", debug_parent.hand_side, ")!")
				button_trigger_sent = true
		if not buttonclicked and button_trigger_sent:
			button_trigger_sent = false


const stickradius = 0.01
static func sticktransformB(j1, j2):
	var v = j2 - j1
	var vlen = v.length()
	var b
	if vlen != 0:
		var vy = v/vlen
		var vyunaligned = Vector3(0,1,0) if abs(vy.y) < abs(vy.x) + abs(vy.z) else Vector3(1,0,0)
		var vz = vy.cross(vyunaligned)
		var vx = vy.cross(vz)
		b = Basis(vx*stickradius, v, vz*stickradius)
	else:
		b = Basis().scaled(Vector3(0.01, 0.0, 0.01))
	return Transform3D(b, (j1 + j2)*0.5)
