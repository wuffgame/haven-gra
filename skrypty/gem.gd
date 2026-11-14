extends Area2D



func collect() -> void:
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	
	
	await tween.finished
	queue_free()
	

	gamemanager.gem_collected()
