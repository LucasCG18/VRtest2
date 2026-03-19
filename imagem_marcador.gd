class_name OpenXRSpatialAnchor3D2
extends XRAnchor3D

var anchor_tracker: OpenXRAnchorTracker
var child_scene: Node
var made_persistent: bool = false

## Return the scene path for our UUID.
func get_scene_path(p_uuid: String) -> String:
	# Placeholder, implement this.
	return ""


## Store our scene path for our UUID.
func set_scene_path(p_uuid: String, p_scene_path: String):
	# Placeholder, implement this.
	pass


## Remove info related to our UUID.
func remove_uuid(p_uuid: String):
	# Placeholder, implement this.
	pass


## Set our child scene for this anchor, call this when creating a new anchor.
func set_child_scene(p_child_scene_path: String):
	var packed_scene: PackedScene = load(p_child_scene_path)
	if not packed_scene:
		return

	child_scene = packed_scene.instantiate()
	if not child_scene:
		return

	add_child(child_scene)


# Called when our tracking state changes.
func _on_spatial_tracking_state_changed(new_state) -> void:
	if new_state == OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_TRACKING and not made_persistent:
		# Only attempt to do this once.
		made_persistent = true

		# This warning is optional if you don't want to rely on persistence.
		if not OpenXRSpatialAnchorCapability.is_spatial_persistence_supported():
			push_warning("Persistent spatial anchors are not supported on this device!")
			return

		# Make this persistent, this will notify that the UUID changed on the anchor,
		# we can then store our scene path which we've already applied to our
		# tracked scene.
		OpenXRSpatialAnchorCapability.persist_anchor(anchor_tracker, RID(), Callable())


func _on_uuid_changed() -> void:
	if anchor_tracker.uuid != "":
		made_persistent = true

		if child_scene:
			# If we already have a subscene, save that with the UUID.
			set_scene_path(anchor_tracker.uuid, child_scene.scene_file_path)
		else:
			# If we do not, look up the UUID in our stored cache.
			var scene_path: String = get_scene_path(anchor_tracker.uuid)
			if scene_path.is_empty():
				# Give a warning that we don't have a scene file stored for this UUID.
				push_warning("Unknown UUID given, can't determine child scene.")

				# Load a default scene so we can at least see something.
				set_child_scene("res://unknown_anchor.tscn")
				return

			set_child_scene(scene_path)


func _ready():
	anchor_tracker = XRServer.get_tracker(tracker)
	if anchor_tracker:
		_on_uuid_changed()

		anchor_tracker.spatial_tracking_state_changed.connect(_on_spatial_tracking_state_changed)
		anchor_tracker.uuid_changed.connect(_on_uuid_changed)
		


## Create a new spatial anchor with the associated child scene.
## If persistent anchors are supported, this will be created as a persistent node
## and we will store the child scene path with the anchor's UUID for future recreation.
func create_spatial_anchor(p_transform: Transform3D, p_child_scene_path: String):
	# Do we have anchor support?
	if not OpenXRSpatialAnchorCapability.is_spatial_anchor_supported():
		push_error("Spatial anchors are not supported on this device!")
		return

	# Adjust our transform to local space.
	var t: Transform3D = global_transform.inverse() * p_transform

	# Create anchor on our current manager.
	var new_anchor = OpenXRSpatialAnchorCapability.create_new_anchor(t, RID())
	if not new_anchor:
		push_error("Couldn't create an anchor for %s." % [ p_child_scene_path ])
		return

	# Creating a new anchor should have resulted in an XRAnchor being added to the scene
	# by our manager. We can thus continue assuming this has happened.

	var anchor_scene = get_tracked_scene(new_anchor)
	if not anchor_scene:
		push_error("Couldn't locate anchor scene for %s, has the manager been configured with an applicable anchor scene?" % [ new_anchor.name ])
		return
	if not anchor_scene is OpenXRSpatialAnchor3D:
		push_error("Anchor scene for %s is not an OpenXRSpatialAnchor3D scene, has the manager been configured with an applicable anchor scene?" % [ new_anchor.name ])
		return

	anchor_scene.set_child_scene(p_child_scene_path)


## Removes this spatial anchor from our scene.
## If the spatial anchor is persistent, the associated UUID will be cleared.
func remove_spatial_anchor(p_anchor: XRAnchor3D):
	# Do we have anchor support?
	if not OpenXRSpatialAnchorCapability.is_spatial_anchor_supported():
		push_error("Spatial anchors are not supported on this device!")
		return

	var tracker: XRTracker = XRServer.get_tracker(p_anchor.tracker)
	if tracker and tracker is OpenXRAnchorTracker:
		var anchor_tracker: OpenXRAnchorTracker = tracker
		if anchor_tracker.has_uuid() and OpenXRSpatialAnchorCapability.is_spatial_persistence_supported():
			# If we have a UUID we should first make the anchor unpersistent
			# and then remove it on its callback.
			remove_uuid(anchor_tracker.uuid)
			OpenXRSpatialAnchorCapability.unpersist_anchor(anchor_tracker, RID(), _on_unpersist_complete)
		else:
			# Otherwise we can just remove it.
			# This will remove it from the XRServer, which in turn will trigger cleaning up our node.
			OpenXRSpatialAnchorCapability.remove_anchor(tracker)


func _on_unpersist_complete(p_tracker: XRTracker):
	# Our tracker is now no longer persistent, we can remove it.
	OpenXRSpatialAnchorCapability.remove_anchor(p_tracker)


## Retrieve the scene we've added for a given tracker (if any).
func get_tracked_scene(p_tracker: XRTracker) -> XRNode3D:
	for node in get_children():
		if node is XRNode3D and node.tracker == p_tracker.name:
			return node

	return null
	
