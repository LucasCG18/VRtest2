class_name SpatialEntitiesManager
extends Node3D
## Signals a new spatial entity node was added.
signal added_spatial_entity(node: XRNode3D)

## Signals a spatial entity node is about to be removed.
signal removed_spatial_entity(node: XRNode3D)

## Scene to instantiate for spatial anchor entities.
@export var spatial_anchor_scene: PackedScene

## Scene to instantiate for plane tracking spatial entities.
@export var plane_tracker_scene: PackedScene

## Scene to instantiate for marker tracking spatial entities.
@export var marker_tracker_scene: PackedScene

# Trackers we manage nodes for.
var _managed_nodes: Dictionary[XRTracker, XRAnchor3D]

# Enter tree is called whenever our node is added to our scene.
func _enter_tree():
	# Connect to signals that inform us about tracker changes.
	XRServer.tracker_added.connect(_on_tracker_added)
	XRServer.tracker_updated.connect(_on_tracker_updated)
	XRServer.tracker_removed.connect(_on_tracker_removed)

	# Set up existing trackers.
	var trackers : Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANCHOR)
	for tracker_name in trackers:
		var tracker: XRTracker = trackers[tracker_name]
		if tracker and tracker is OpenXRSpatialEntityTracker:
			_add_tracker(tracker)


# Exit tree is called whenever our node is removed from our scene.
func _exit_tree():
	# Clean up our signals.
	XRServer.tracker_added.disconnect(_on_tracker_added)
	XRServer.tracker_updated.disconnect(_on_tracker_updated)
	XRServer.tracker_removed.disconnect(_on_tracker_removed)

	# Clean up trackers.
	for tracker in _managed_nodes:
		removed_spatial_entity.emit(_managed_nodes[tracker])
		remove_child(_managed_nodes[tracker])
		_managed_nodes[tracker].queue_free()

	_managed_nodes.clear()


# See if this tracker should be managed by us and add it.
func _add_tracker(tracker: OpenXRSpatialEntityTracker):
	var new_node: XRAnchor3D

	if _managed_nodes.has(tracker):
		# Already being managed by us!
		return

	if tracker is OpenXRAnchorTracker:
		# Note: Generally spatial anchors are controlled by the developer and
		# are unlikely to be handled by our manager.
		# But just for completeness we'll add it in.
		if spatial_anchor_scene:
			var new_scene = spatial_anchor_scene.instantiate()
			if new_scene is XRAnchor3D:
				new_node = new_scene
			else:
				push_error("Spatial anchor scene doesn't have an XRAnchor3D as a root node and can't be used!")
				new_scene.free()
	elif tracker is OpenXRPlaneTracker:
		if plane_tracker_scene:
			var new_scene = plane_tracker_scene.instantiate()
			if new_scene is XRAnchor3D:
				new_node = new_scene
			else:
				push_error("Plane tracking scene doesn't have an XRAnchor3D as a root node and can't be used!")
				new_scene.free()
	elif tracker is OpenXRMarkerTracker:
		if marker_tracker_scene:
			var new_scene = marker_tracker_scene.instantiate()
			if new_scene is XRAnchor3D:
				new_node = new_scene
			else:
				push_error("Marker tracking scene doesn't have an XRAnchor3D as a root node and can't be used!")
				new_scene.free()
	else:
		# Type of spatial entity tracker we're not supporting?
		push_warning("OpenXR Spatial Entities: Unsupported anchor tracker " + tracker.get_name() + " of type " + tracker.get_class())

	if not new_node:
		# No scene defined or able to be instantiated? We're done!
		return

	# Set up and add to our scene.
	new_node.tracker = tracker.name
	new_node.pose = "default"
	_managed_nodes[tracker] = new_node
	add_child(new_node)

	added_spatial_entity.emit(new_node)


# A new tracker was added to our XRServer.
func _on_tracker_added(tracker_name: StringName, type: int):
	if type == XRServer.TRACKER_ANCHOR:
		var tracker: XRTracker = XRServer.get_tracker(tracker_name)
		if tracker and tracker is OpenXRSpatialEntityTracker:
			_add_tracker(tracker)


# A tracked managed by XRServer was changed.
func _on_tracker_updated(_tracker_name: StringName, _type: int):
	# For now we ignore this, there aren't any changes here we need to react
	# to and the instanced scene can react to this itself if needed.
	pass


# A tracker was removed from our XRServer.
func _on_tracker_removed(tracker_name: StringName, type: int):
	if type == XRServer.TRACKER_ANCHOR:
		var tracker: XRTracker = XRServer.get_tracker(tracker_name)
		if _managed_nodes.has(tracker):
			# We emit this right before we remove it!
			removed_spatial_entity.emit(_managed_nodes[tracker])

			# Remove the node.
			remove_child(_managed_nodes[tracker])

			# Queue free the node.
			_managed_nodes[tracker].queue_free()

			# And remove from our managed nodes.
			_managed_nodes.erase(tracker)
			
			
			
