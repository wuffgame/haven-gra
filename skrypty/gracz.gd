extends CharacterBody2D

enum State { AIMING, MOVING }
var current_state = State.MOVING

@export var max_drag_distance: float = 220.0
@export var max_power: float = 1400.0
@export var gravity: float = 700.0
@export var aiming_slowmo_factor: float = 0.12

@export var normal_zoom: Vector2 = Vector2(1.0, 1.0)
@export var max_aim_zoom: Vector2 = Vector2(1.5, 1.5)
@export var zoom_speed: float = 10.0

var drag_start_pos: Vector2 = Vector2.ZERO
var launch_vector: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2(1, 1)
var dots: Array[ColorRect] = []

@onready var drag_line: Line2D = $Line2D
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	drag_line.visible = false
	create_aim_dots()
	original_scale = scale
	velocity = Vector2(400, -300)

func create_aim_dots() -> void:
	for i in range(8):
		var dot = ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.pivot_offset = dot.size / 2.0
		dot.color = Color(1, 1, 1, 1.0 - (float(i) / 8.0))
		dot.visible = false
		add_child(dot)
		dots.append(dot)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			current_state = State.AIMING
			drag_start_pos = global_position
			drag_line.visible = true
		elif current_state == State.AIMING:
			shoot()

func _process(delta: float) -> void:
	if current_state == State.AIMING:
		drag_start_pos = global_position
		var current_mouse_pos = get_global_mouse_position()
		var raw_drag = drag_start_pos - current_mouse_pos
		launch_vector = raw_drag.limit_length(max_drag_distance)
		update_aim_visuals()

	var target_zoom = normal_zoom
	if current_state == State.AIMING:
		var pull_ratio = launch_vector.length() / max_drag_distance
		target_zoom = normal_zoom.lerp(max_aim_zoom, float(pull_ratio))
	
	if camera:
		camera.zoom = camera.zoom.lerp(target_zoom, zoom_speed * delta)

func update_aim_visuals() -> void:
	var pull_ratio = launch_vector.length() / max_drag_distance
	var direction = launch_vector.normalized()
	
	drag_line.points = [Vector2.ZERO, -launch_vector * 0.5]
	
	for i in range(dots.size()):
		dots[i].visible = pull_ratio > 0.05
		var distance = (i + 1) * 25.0 * pull_ratio
		dots[i].position = (direction * distance) - (dots[i].size / 2.0)

func shoot() -> void:
	hide_aim_visuals()
	var pull_ratio = launch_vector.length() / max_drag_distance
	if pull_ratio > 0.05:
		velocity = launch_vector.normalized() * (pull_ratio * max_power)
	current_state = State.MOVING

func hide_aim_visuals() -> void:
	drag_line.visible = false
	for dot in dots:
		dot.visible = false

func play_squash_animation(hit_normal: Vector2) -> void:
	var tween = create_tween().set_parallel(false)
	var squash_scale = Vector2(1.3, 0.7)
	
	if abs(hit_normal.x) > 0.5:
		squash_scale = Vector2(0.7, 1.3)
	else:
		squash_scale = Vector2(1.3, 0.7)
		
	scale = squash_scale * original_scale
	tween.tween_property(self, "scale", original_scale, 0.25)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

func handle_collision(collision: KinematicCollision2D) -> void:
	var normal = collision.get_normal()
	velocity = velocity.bounce(normal) * 0.85
	play_squash_animation(normal)

func _physics_process(delta: float) -> void:
	if current_state == State.MOVING:
		velocity.y += gravity * delta
		var collision = move_and_collide(velocity * delta)
		if collision:
			handle_collision(collision)
				
	elif current_state == State.AIMING:
		velocity.y += (gravity * aiming_slowmo_factor) * delta
		var slow_velocity = velocity * aiming_slowmo_factor
		var collision = move_and_collide(slow_velocity * delta)
		if collision:
			handle_collision(collision)
