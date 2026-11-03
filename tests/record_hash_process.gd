extends SceneTree
## Shared cases also run through the actual release executable diagnostic route.

func _initialize() -> void:
	root.add_child.call_deferred(RecordHashProcess.new())
