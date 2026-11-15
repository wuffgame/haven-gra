extends CharacterBody2D

enum State { AIMING, MOVING, GAME_OVER }
var current_state = State.MOVING

const GEM_PARTICLES_SCENE = preload("res://sceny/cpu_particles_2d.tscn")

@export var max_drag_distance: float = 220.0
@export var max_power: float = 1400.0
@export var gravity: float = 700.0
@export var aiming_slowmo_factor: float = 0.12
@export var slowmo_duration: float = 3.0

@onready var boing: AudioStreamPlayer2D = $boing
@onready var coin: AudioStreamPlayer2D = $coin


@export var normal_zoom: Vector2 = Vector2(1.0, 1.0)
@export var max_aim_zoom: Vector2 = Vector2(1.5, 1.5)
@export var zoom_speed: float = 10.0

var drag_start_pos: Vector2 = Vector2.ZERO
var launch_vector: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2(1, 1)
var dots: Array[ColorRect] = []

var aim_timer: float = 0.0

var total_gems: int = 0 # ile w danym lvl
var collected_gems: int = Global.collected_gems # ile zebranych
var max_moves: int = 0
var current_moves: int = max_moves
var collected_gems_now: int = 0

@onready var drag_line: Line2D = $Line2D
@onready var camera: Camera2D = $Camera2D
@onready var gam_label: Label = $CanvasLayer/HBoxContainer/ilosc_gemow
@onready var move_label: Label = $CanvasLayer/ilosc_ruchow
@onready var lvl_panel_label: Label = $CanvasLayer/Panel/Label
@onready var lvl_panel: Panel = $CanvasLayer/Panel
@onready var anim_player: AnimationPlayer = $CanvasLayer/Panel/AnimationPlayer
@onready var hit_particles: GPUParticles2D = $GPUParticles2D
@onready var gems_particles: GPUParticles2D = $GPUParticles2D2

func _ready() -> void:
	lvl_panel_label.text = "level" + str(Global.lvl_number)
	anim_player.play("show_lvl_baner")
	drag_line.visible = false
	create_aim_dots()
	original_scale = scale
	velocity = Vector2(400, -300)
	
	if hit_particles: hit_particles.emitting = false
	if gems_particles: gems_particles.emitting = false

	await get_tree().create_timer(0.01).timeout
	if Global:
		max_moves = Global.max_moves
		current_moves = max_moves
		total_gems = Global.total_gems
	if move_label:
		move_label.text = str(current_moves - 1) + "/" + str(max_moves - 1)
	if gam_label:
		gam_label.text = str(collected_gems)
	
	#call_deferred("count_gems_on_level")

#func count_gems_on_level() -> void:
	#total_gems = get_tree().get_nodes_in_group("gems").size()

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
	if current_state == State.GAME_OVER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			current_state = State.AIMING
			aim_timer = 0.0
			drag_start_pos = global_position
			drag_line.visible = true
		elif current_state == State.AIMING:
			shoot()

func _process(delta: float) -> void:
	if current_state == State.AIMING:
		aim_timer += delta
		drag_start_pos = global_position
		var current_mouse_pos = get_global_mouse_position()
		var raw_drag = drag_start_pos - current_mouse_pos
		launch_vector = raw_drag.limit_length(max_drag_distance)
		update_aim_visuals()

	var target_zoom = normal_zoom
	if current_state == State.AIMING:
		var progress = min(aim_timer / slowmo_duration, 1.0)
		var current_slowmo = lerp(aiming_slowmo_factor, 1.0, progress)
		
		var pull_ratio = launch_vector.length() / max_drag_distance
		var effective_max_zoom = normal_zoom.lerp(max_aim_zoom, pull_ratio)
		target_zoom = effective_max_zoom.lerp(normal_zoom, progress)
	
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
		update_moves()
	if current_state != State.GAME_OVER:
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
	boing.play()
	play_squash_animation(normal)
	if hit_particles:
		hit_particles.global_position = collision.get_position()
		hit_particles.rotation = normal.angle()
		hit_particles.restart()
		hit_particles.emitting = true

func _on_collector_hitbox_area_entered(area: Area2D) -> void:
	if not is_instance_valid(area) or not area.is_in_group("gems"):
		return
	coin.play()
	collected_gems_now += 1
	update_gems()
	
	var tree = get_tree()
	if GEM_PARTICLES_SCENE and tree and tree.current_scene:
		var particles = GEM_PARTICLES_SCENE.instantiate()
		tree.current_scene.add_child(particles)
		particles.global_position = area.global_position
	
	var gem_tween = create_tween().set_parallel(true)
	gem_tween.tween_property(area, "scale", Vector2(1.5, 1.5), 0.1)
	gem_tween.tween_property(area, "modulate:a", 0.0, 0.1)
	gem_tween.chain().tween_callback(func():
		if is_instance_valid(area):
			area.queue_free()
	)

func _physics_process(delta: float) -> void:
	if current_state == State.GAME_OVER:
		return
	if current_state == State.MOVING:
		velocity.y += gravity * delta
		var collision = move_and_collide(velocity * delta)
		if collision:
			handle_collision(collision)

	elif current_state == State.AIMING:
		var progress = min(aim_timer / slowmo_duration, 1.0)
		var current_slowmo = lerp(aiming_slowmo_factor, 1.0, progress)
		
		velocity.y += (gravity * current_slowmo) * delta
		var slow_velocity = velocity * current_slowmo
		var collision = move_and_collide(slow_velocity * delta)
		if collision:
			handle_collision(collision)
			
func update_moves() -> void:
	current_moves -= 1
	move_label.text = str(current_moves - 1) + "/" + str(max_moves - 1)
	if current_moves <= 0:
		move_label.text =  "0/" + str(max_moves - 1)
		current_state = State.GAME_OVER
		hide_aim_visuals()

		lvl_panel_label.text = "no moves"
		anim_player.play("show_lvl_baner")

		await anim_player.animation_finished

		get_tree().reload_current_scene()

func update_gems() -> void:
	gam_label.text = str(collected_gems + collected_gems_now)
	if collected_gems_now >= total_gems:
		collected_gems = collected_gems + collected_gems_now
		Global.collected_gems = collected_gems
		Global.lvl_number += 1
		var _next_scene = "res://sceny/lvl_" + str(Global.lvl_number) + ".tscn"
		if FileAccess.file_exists(_next_scene):
			get_tree().change_scene_to_file(_next_scene)
		else:
			get_tree().change_scene_to_file("res://sceny/Thx_for_play.tscn")
