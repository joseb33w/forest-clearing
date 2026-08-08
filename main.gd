extends Node3D
## Forest Clearing — a small, cozy exploration game. One clearing, a wooden cabin,
## trees, rocks, a pond, and a treasure chest hidden behind the cabin. Find it.
## Mobile-web: Compatibility/WebGL2, nothreads. Touch joystick + drag-look, WASD + mouse.

const MOVE_SPEED := 6.0
const WALK_SPEED := 3.2
const LOOK_SENS := 0.005
const GRAVITY := 22.0
const JUMP_SPEED := 8.5
const STEP_MAX := 1.2
const CAM_DIST := 6.5
const CAM_PITCH_MIN := -1.25
const CAM_PITCH_MAX := 0.6

const CLEARING_R := 19.0          # playable radius; treeline ring sits just beyond
const POND_C := Vector3(-10.0, 0.0, 6.0)
const POND_R := 4.6
const CABIN_POS := Vector3(0.0, 0.0, -6.0)
const CHEST_POS := Vector3(1.2, 0.0, -11.6)

var player: CharacterBody3D
var hero: Node3D                   # the visible character model (child of player)
var hero_anim: AnimationPlayer
var cam_spring: SpringArm3D
var camera: Camera3D
var weather: Weather3D
var started := false
var chest_found := false
var chest_node: Node3D
var _cur_clip := ""
var _was_airborne := false
var _js_set_time_cb = null
var _js_get_player_cb = null
var _js_solids_cb = null
var _yaw := 0.0
var _pitch := -0.42
var _jump_queued := false

var _move_index := -1
var _move_origin := Vector2.ZERO
var _move_vec := Vector2.ZERO
var _look_index := -1


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X
	_build_world()
	_setup_web_time_hooks()
	_build_touch_ui()
	_show_tap_to_start()


func _physics_process(delta: float) -> void:
	if not started or player == null:
		return
	var v := _keyboard_vector() + _move_vec
	if v.length() > 1.0:
		v = v.normalized()
	if chest_found:
		v = Vector2.ZERO
	var dir := Basis(Vector3.UP, _yaw) * Vector3(v.x, 0.0, v.y)
	var spd := MOVE_SPEED if v.length() > 0.6 else WALK_SPEED
	player.velocity.x = dir.x * spd
	player.velocity.z = dir.z * spd
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif _jump_queued:
		player.velocity.y = JUMP_SPEED
		AudioManager.play_sfx("ui", -8.0, 1.3)
	else:
		player.velocity.y = -1.0
	_jump_queued = false
	player.move_and_slide()
	_step_up_assist(dir)
	player.rotation.y = _yaw
	if cam_spring:
		cam_spring.rotation.x = _pitch
	_update_hero(dir, v.length(), delta)


## Face the model along the move direction and drive idle/walk/run clips.
## KayKit models face +Z, so atan2(dir.x, dir.z) is the correct global yaw (no PI offset).
func _update_hero(dir: Vector3, mag: float, delta: float) -> void:
	if hero == null:
		return
	if chest_found:
		return   # let the one-shot "pickup" clip play out during the win moment
	var moving := mag > 0.05
	if moving and dir.length() > 0.01:
		var target := atan2(dir.x, dir.z) - _yaw
		hero.rotation.y = lerp_angle(hero.rotation.y, target, 12.0 * delta)
	var clip := "idle"
	if moving:
		clip = "run" if mag > 0.6 else "walk"
	_play_clip(clip)
	if _was_airborne and player.is_on_floor():
		_land_puff()
	_was_airborne = not player.is_on_floor()


func _play_clip(clip: String) -> void:
	if hero_anim == null or clip == _cur_clip:
		return
	if hero_anim.has_animation(clip):
		hero_anim.play(clip, 0.18)
		_cur_clip = clip


func _land_puff() -> void:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.4
	p.one_shot = true
	p.emitting = true
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -3, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.25
	p.mesh = SphereMesh.new()
	(p.mesh as SphereMesh).radius = 0.05
	(p.mesh as SphereMesh).height = 0.1
	p.material_override = _mat(Color(0.75, 0.7, 0.6))
	p.position = player.global_position + Vector3(0, 0.1, 0)
	add_child(p)
	var t := p.create_tween()
	t.tween_interval(1.0)
	t.tween_callback(p.queue_free)


func _step_up_assist(dir: Vector3) -> void:
	if player == null or dir.length() < 0.1:
		return
	if not (player.is_on_wall() and player.is_on_floor()):
		return
	var into := dir.normalized()
	if into.dot(-player.get_wall_normal()) < 0.3:
		return
	var feet := player.global_position.y
	var ahead := player.global_position + into * 0.6
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(ahead.x, feet + STEP_MAX + 0.1, ahead.z),
		Vector3(ahead.x, feet - 0.5, ahead.z), 1)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var step := float(hit["position"].y) - feet
	if step > 0.05 and step <= STEP_MAX:
		player.global_position.y = float(hit["position"].y) + 0.02


func _input(event: InputEvent) -> void:
	if not started:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		_jump_queued = true
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and _move_index == -1:
				_move_index = event.index
				_move_origin = event.position
				_move_vec = Vector2.ZERO
			elif event.position.x >= half and _look_index == -1:
				_look_index = event.index
		else:
			if event.index == _move_index:
				_move_index = -1
				_move_vec = Vector2.ZERO
			elif event.index == _look_index:
				_look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == _move_index:
			_move_vec = ((event.position - _move_origin) / 80.0).limit_length(1.0)
		elif event.index == _look_index:
			_apply_look(event.relative)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _move_index == -1 and _look_index == -1:
		_apply_look(event.relative)


func _apply_look(d: Vector2) -> void:
	_yaw -= d.x * LOOK_SENS
	_pitch = clampf(_pitch - d.y * LOOK_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v


# ---------------------------------------------------------------- world build

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	weather = Weather3D.new()
	add_child(weather)

	_build_ground()
	_build_boundary()

	# The cabin — the clearing's landmark, in clear sight of spawn.
	var cabin := _place("res://models/building_home_A_red.glb", CABIN_POS, {"footprint": 7.0, "yaw": 180.0, "collider": "box"})
	if cabin == null:
		push_warning("cabin failed to load")

	_build_chest()
	_build_pond()
	_build_campfire()
	_build_flora_and_rocks()
	_build_player()

	weather.setup(env, sun, camera)
	weather.apply({"time": "day", "weather": "clear"})


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 48.0)
	ground.mesh = plane
	ground.material_override = ground_material("grass")
	var gbody := StaticBody3D.new()
	gbody.collision_layer = 1
	gbody.add_to_group("gogi_terrain")
	var gcs := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(48.0, 0.2, 48.0)
	gcs.shape = gshape
	gcs.position.y = -0.1
	gbody.add_child(gcs)
	ground.add_child(gbody)
	add_child(ground)


## Invisible walls just inside the treeline so the player can't leave the clearing.
func _build_boundary() -> void:
	var w := CLEARING_R + 0.5
	var specs: Array = [
		[Vector3(0, 2, -w), Vector3(2.0 * w + 4.0, 4.0, 1.0)],
		[Vector3(0, 2, w), Vector3(2.0 * w + 4.0, 4.0, 1.0)],
		[Vector3(-w, 2, 0), Vector3(1.0, 4.0, 2.0 * w + 4.0)],
		[Vector3(w, 2, 0), Vector3(1.0, 4.0, 2.0 * w + 4.0)],
	]
	for s: Array in specs:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s[1]
		cs.shape = box
		body.add_child(cs)
		body.position = s[0]
		add_child(body)


func _build_chest() -> void:
	chest_node = _place("res://models/Chest_Wood.glb", CHEST_POS, {"footprint": 1.15, "yaw": 205.0, "collider": "box"})
	# A soft golden sparkle so the chest reads as "the goal" once spotted.
	var spark := CPUParticles3D.new()
	spark.amount = 8
	spark.lifetime = 1.4
	spark.emitting = true
	spark.direction = Vector3.UP
	spark.spread = 30.0
	spark.initial_velocity_min = 0.4
	spark.initial_velocity_max = 0.9
	spark.gravity = Vector3.ZERO
	spark.scale_amount_min = 0.04
	spark.scale_amount_max = 0.1
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	spark.mesh = sm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.85, 0.3)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.8, 0.25)
	em.emission_energy_multiplier = 2.5
	spark.material_override = em
	spark.position = CHEST_POS + Vector3(0, 1.0, 0)
	add_child(spark)
	# Trigger: fires for the layer-2 player (mask 2 — the mask/layer rule).
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.1
	cs.shape = sph
	area.add_child(cs)
	area.position = CHEST_POS + Vector3(0, 0.8, 0)
	area.body_entered.connect(_on_chest_reached)
	add_child(area)


## A circular pond: radial water disc (toon-water shader, depth baked into COLOR.r —
## foam at the rim, deeper teal at the centre), ringed with cattails and stones.
func _build_pond() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var segs := 28
	for ri in rings:
		var r0 := POND_R * float(ri) / float(rings)
		var r1 := POND_R * float(ri + 1) / float(rings)
		var d0 := 1.0 - float(ri) / float(rings)
		var d1 := 1.0 - float(ri + 1) / float(rings)
		for si in segs:
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float(si + 1) / float(segs)
			var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			_water_tri(st, p00, d0, p10, d1, p11, d1)
			_water_tri(st, p00, d0, p11, d1, p01, d0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = GWater.make_material({
		"shallow": [0.30, 0.62, 0.60], "deep": [0.07, 0.30, 0.42],
		"wave_amp": 0.05, "wave_speed": 0.9})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = POND_C + Vector3(0, 0.07, 0)
	add_child(mi)
	# Rim dressing: cattails + a couple of stones.
	var rim: Array = [0.3, 1.25, 2.2, 3.4, 4.3, 5.5]
	for a: float in rim:
		var pos := POND_C + Vector3(cos(a), 0, sin(a)) * (POND_R + 0.7)
		_place("res://models/Cattail_1.glb", pos, {"height": 1.0, "yaw": randf() * 360.0})
	_place("res://models/Rock_2.glb", POND_C + Vector3(POND_R + 0.9, 0, -1.6), {"footprint": 1.2, "collider": "box"})
	_place("res://models/Rock_Moss_1.glb", POND_C + Vector3(-POND_R - 0.6, 0, 1.2), {"footprint": 1.5, "collider": "box"})


func _water_tri(st: SurfaceTool, a: Vector3, da: float, b: Vector3, db: float, c: Vector3, dc: float) -> void:
	for v: Array in [[a, da], [b, db], [c, dc]]:
		st.set_color(Color(float(v[1]), 0.0, 0.0, 1.0))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2((v[0] as Vector3).x * 0.05, (v[0] as Vector3).z * 0.05))
		st.add_vertex(v[0] as Vector3)


func _build_campfire() -> void:
	var fire := _place("res://models/Campfire_Teepee.glb", Vector3(4.2, 0, -2.2), {"footprint": 1.0, "collider": "box"})
	if fire != null:
		var flame := CPUParticles3D.new()
		flame.amount = 14
		flame.lifetime = 0.7
		flame.emitting = true
		flame.direction = Vector3.UP
		flame.spread = 12.0
		flame.initial_velocity_min = 0.8
		flame.initial_velocity_max = 1.4
		flame.gravity = Vector3(0, 1.5, 0)
		flame.scale_amount_min = 0.08
		flame.scale_amount_max = 0.22
		var fm := SphereMesh.new()
		fm.radius = 0.07
		fm.height = 0.14
		flame.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.55, 0.15)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.45, 0.1)
		fmat.emission_energy_multiplier = 3.0
		flame.material_override = fmat
		flame.position = fire.position + Vector3(0, 0.45, 0)
		add_child(flame)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.7, 0.4)
		lamp.light_energy = 1.4
		lamp.omni_range = 6.0
		lamp.position = fire.position + Vector3(0, 0.9, 0)
		add_child(lamp)
		AudioManager.attach_loop(fire, load("res://audio/fire.wav"), -14.0, 12.0)
	# A stump and a mossy log make it a sitting spot.
	_place("res://models/TreeStump.glb", Vector3(5.6, 0, -1.2), {"footprint": 1.0, "collider": "box"})
	_place("res://models/WoodLog_Moss.glb", Vector3(3.0, 0, -0.8), {"footprint": 1.6, "yaw": 40.0, "collider": "box"})


func _build_flora_and_rocks() -> void:
	# Solid in-clearing trees (trunk colliders so canopies never block walking).
	var trees: Array = [
		["PineTree_1", Vector3(-6, 0, -13), 8.5], ["CommonTree_1", Vector3(8, 0, -11), 7.5],
		["PineTree_2", Vector3(13, 0, -3), 9.0], ["BirchTree_1", Vector3(-14, 0, -6), 7.0],
		["PineTree_1", Vector3(-15, 0, 12), 8.0], ["BirchTree_1", Vector3(6, 0, 9), 7.5],
		["CommonTree_1", Vector3(15, 0, 11), 8.0], ["PineTree_2", Vector3(-4, 0, 15), 8.5],
	]
	for t: Array in trees:
		_place("res://models/%s.glb" % t[0], t[1], {"height": t[2], "yaw": randf() * 360.0, "collider": "trunk"})
	# Rock clusters.
	_place("res://models/Rock_1.glb", Vector3(10, 0, 3), {"footprint": 1.7, "collider": "box"})
	_place("res://models/Rock_2.glb", Vector3(11.2, 0, 3.8), {"footprint": 0.9})
	_place("res://models/Rock_Moss_1.glb", Vector3(-8, 0, -10), {"footprint": 1.9, "collider": "box"})
	_place("res://models/Rock_1.glb", Vector3(-6.9, 0, -9.2), {"footprint": 0.8})
	_place("res://models/Rock_2.glb", Vector3(-15, 0, 15), {"footprint": 1.4, "collider": "box"})
	# The treeline that encloses the clearing (MultiMesh — one draw call per mesh).
	_scatter_ring("res://models/PineTree_1.glb", 34, CLEARING_R + 1.5, CLEARING_R + 6.0, 0.9, 1.5)
	_scatter_ring("res://models/PineTree_2.glb", 28, CLEARING_R + 1.0, CLEARING_R + 5.5, 0.85, 1.4)
	_scatter_ring("res://models/CommonTree_1.glb", 20, CLEARING_R + 1.2, CLEARING_R + 5.0, 0.8, 1.3)
	# Ground dressing: grass tufts + flowers, keeping the pond + cabin clear.
	_scatter_disc("res://models/Grass_Wispy_Tall.glb", 170, 17.5, 0.8, 1.5)
	_scatter_disc("res://models/Flower_3_Single.glb", 46, 16.5, 0.9, 1.4)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.floor_max_angle = deg_to_rad(55)
	player.position = Vector3(0.0, 0.0, 10.0)
	add_child(player)
	var pcs := CollisionShape3D.new()
	var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4
	pcap.height = 1.6
	pcs.shape = pcap
	pcs.position.y = 0.85
	player.add_child(pcs)

	var packed = load("res://models/kk_Ranger.glb")
	if packed is PackedScene:
		hero = (packed as PackedScene).instantiate() as Node3D
		player.add_child(hero)
		hero.rotation.y = PI   # rest facing = away from the camera (matches first forward step)
		_seat_local(hero)
		hero_anim = AnimRig.attach(hero, {
			"idle": "Idle_A", "walk": "Walking_A", "run": "Running_A", "pickup": "PickUp",
		}, ["idle", "walk", "run"])
		if hero_anim != null:
			hero_anim.play("idle")
			_cur_clip = "idle"
	else:
		var pbody := MeshInstance3D.new()
		var pmesh := CapsuleMesh.new()
		pmesh.radius = 0.4
		pmesh.height = 1.6
		pbody.mesh = pmesh
		pbody.position.y = 0.85
		pbody.material_override = _mat(Color(0.35, 0.6, 0.95))
		player.add_child(pbody)

	cam_spring = SpringArm3D.new()
	cam_spring.spring_length = CAM_DIST
	cam_spring.collision_mask = 1
	cam_spring.margin = 0.3
	cam_spring.position.y = 1.4
	cam_spring.rotation.x = _pitch
	player.add_child(cam_spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	cam_spring.add_child(camera)


# ---------------------------------------------------------------- chest / win

func _on_chest_reached(body: Node3D) -> void:
	if chest_found or body != player:
		return
	chest_found = true
	AudioManager.play_sfx("pickup")
	_play_clip("pickup")
	if chest_node != null:
		var t := chest_node.create_tween()
		t.tween_property(chest_node, "scale", chest_node.scale * 1.25, 0.12).set_trans(Tween.TRANS_BACK)
		t.tween_property(chest_node, "scale", chest_node.scale, 0.18)
	_gold_burst(CHEST_POS + Vector3(0, 0.9, 0))
	_shake_camera()
	var timer := get_tree().create_timer(0.9)
	timer.timeout.connect(_show_win_panel)


func _gold_burst(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 1.1
	p.one_shot = true
	p.emitting = true
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	p.mesh = sm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.85, 0.3)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.75, 0.2)
	em.emission_energy_multiplier = 3.0
	p.material_override = em
	p.position = at
	add_child(p)
	var t := p.create_tween()
	t.tween_interval(2.0)
	t.tween_callback(p.queue_free)


func _shake_camera() -> void:
	if camera == null:
		return
	var t := camera.create_tween()
	for i in 4:
		t.tween_property(camera, "h_offset", randf_range(-0.09, 0.09), 0.05)
		t.tween_property(camera, "v_offset", randf_range(-0.06, 0.06), 0.05)
	t.tween_property(camera, "h_offset", 0.0, 0.06)
	t.tween_property(camera, "v_offset", 0.0, 0.06)


func _show_win_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WinPanel"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "You found the treasure!"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.87, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "The old cabin kept its secret well."
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var btn := Button.new()
	btn.text = "Play Again"
	btn.add_theme_font_size_override("font_size", 30)
	btn.custom_minimum_size = Vector2(240, 76)
	btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui")
		get_tree().reload_current_scene())
	var wrap := CenterContainer.new()
	wrap.add_child(btn)
	box.add_child(wrap)
	layer.add_child(box)
	add_child(layer)
	box.scale = Vector2(0.7, 0.7)
	box.pivot_offset = box.size * 0.5
	var t := box.create_tween()
	t.tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- UI

func _build_touch_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var jbtn := Button.new()
	jbtn.text = "JUMP"
	jbtn.custom_minimum_size = Vector2(110, 110)
	jbtn.anchor_left = 1.0
	jbtn.anchor_right = 1.0
	jbtn.anchor_top = 1.0
	jbtn.anchor_bottom = 1.0
	jbtn.offset_left = -140.0
	jbtn.offset_right = -30.0
	jbtn.offset_top = -150.0
	jbtn.offset_bottom = -40.0
	jbtn.pressed.connect(func() -> void: _jump_queued = true)
	layer.add_child(jbtn)


func _show_objective_toast() -> void:
	var layer := get_node_or_null("HUD")
	if layer == null:
		return
	var lbl := Label.new()
	lbl.text = "A treasure chest is hidden somewhere in this clearing..."
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.anchor_left = 0.06
	lbl.anchor_right = 0.94
	lbl.anchor_top = 0.06
	lbl.anchor_bottom = 0.06
	lbl.offset_bottom = 96.0
	lbl.grow_vertical = Control.GROW_DIRECTION_END
	layer.add_child(lbl)
	var t := lbl.create_tween()
	t.tween_interval(4.5)
	t.tween_property(lbl, "modulate:a", 0.0, 1.0)
	t.tween_callback(lbl.queue_free)


func _show_tap_to_start() -> void:
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.name = "TapToStart"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.85)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "Forest Clearing"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var label := Label.new()
	label.text = "Tap to start"
	label.add_theme_font_size_override("font_size", 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var hint := Label.new()
	hint.text = "Left side: move   |   Right side: drag to look\nWASD + mouse on desktop"
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	panel.add_child(box)
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed():
			started = true
			AudioManager.unlock()
			AudioManager.play_music(load("res://audio/music_clearing.ogg"), -9.0)
			AudioManager.play_ambient(load("res://audio/forest_birds.ogg"), -10.0)
			get_tree().paused = false
			_show_objective_toast()
			layer.queue_free())
	layer.add_child(panel)
	add_child(layer)


# ---------------------------------------------------------------- placement helpers

## Instance a .glb, scale it (target "footprint" max XZ or "height" Y), ground its feet,
## optionally give it a collider: "box" (whole AABB) or "trunk" (narrow cylinder).
func _place(path: String, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("missing model: " + path)
		return null
	var packed = load(path)
	if not (packed is PackedScene):
		return null
	var n := (packed as PackedScene).instantiate() as Node3D
	if n == null:
		return null
	add_child(n)
	n.position = pos
	if opts.has("yaw"):
		n.rotation.y = deg_to_rad(float(opts["yaw"]))
	var aabb := _subtree_aabb(n)
	var s := 1.0
	if opts.has("footprint"):
		var foot := maxf(aabb.size.x, aabb.size.z)
		if foot > 0.001:
			s = float(opts["footprint"]) / foot
	elif opts.has("height"):
		if aabb.size.y > 0.001:
			s = float(opts["height"]) / aabb.size.y
	n.scale = Vector3.ONE * s
	_seat_local(n)
	var kind := String(opts.get("collider", ""))
	if kind != "":
		_add_collider(n, kind)
	return n


## Collider derived from the instanced + scaled mesh AABB (world space), added at root
## level so parent scale never double-applies. "trunk" = narrow cylinder for trees.
func _add_collider(model: Node3D, kind: String) -> void:
	var aabb := _subtree_aabb(model)   # world-space (global transforms baked in)
	if aabb.size.length() < 0.01:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	if kind == "trunk":
		var cyl := CylinderShape3D.new()
		cyl.radius = clampf(maxf(aabb.size.x, aabb.size.z) * 0.07, 0.2, 0.5)
		cyl.height = minf(aabb.size.y, 4.0)
		cs.shape = cyl
		cs.position = Vector3(model.global_position.x, aabb.position.y + cyl.height * 0.5, model.global_position.z)
	else:
		var box := BoxShape3D.new()
		box.size = aabb.size
		cs.shape = box
		cs.position = aabb.get_center()
	body.add_child(cs)
	add_child(body)


## Scatter one .glb as MultiMesh instances in a ring around the origin (treeline).
func _scatter_ring(path: String, count: int, r_min: float, r_max: float, s_min: float, s_max: float) -> void:
	var xforms: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(path) + count
	for i in count:
		var a := rng.randf() * TAU
		var rad := rng.randf_range(r_min, r_max)
		var t := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s_min, s_max)),
			Vector3(cos(a) * rad, 0, sin(a) * rad))
		xforms.append(t)
	_multimesh_from_glb(path, xforms)


## Scatter inside a disc, avoiding the pond, cabin and campfire spots.
func _scatter_disc(path: String, count: int, r_max: float, s_min: float, s_max: float) -> void:
	var xforms: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(path) * 7 + count
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 8:
		guard += 1
		var a := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * r_max
		var p := Vector3(cos(a) * rad, 0, sin(a) * rad)
		if p.distance_to(POND_C) < POND_R + 1.2:
			continue
		if p.distance_to(CABIN_POS) < 4.5:
			continue
		if p.distance_to(Vector3(4.2, 0, -2.2)) < 1.6:
			continue
		xforms.append(Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s_min, s_max)), p))
		placed += 1
	_multimesh_from_glb(path, xforms)


## Build MultiMesh instances for EVERY MeshInstance3D inside the .glb (some models split
## trunk/leaves into separate meshes — one MultiMesh per mesh, same instance transforms).
func _multimesh_from_glb(path: String, xforms: Array) -> void:
	if xforms.is_empty() or not ResourceLoader.exists(path):
		return
	var packed = load(path)
	if not (packed is PackedScene):
		return
	var src := (packed as PackedScene).instantiate() as Node3D
	var parts: Array = []
	_collect_meshes(src, Transform3D.IDENTITY, parts)
	src.free()
	for part: Array in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * (part[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _collect_meshes(n: Node, xf: Transform3D, out: Array) -> void:
	var local := xf
	if n is Node3D:
		local = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, local])
	for c in n.get_children():
		_collect_meshes(c, local, out)


# ---------------------------------------------------------------- shared utils

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Seat a model so its mesh bottom rests at its parent's floor height (parents here are
## unrotated/unscaled at build time, so parent world y = global y minus local y).
func _seat_local(node: Node3D) -> void:
	var bottom := _subtree_aabb(node).position.y
	var parent_world_y := node.global_position.y - node.position.y
	node.position.y -= bottom - parent_world_y


func _subtree_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# ---------------- web time-of-day hooks (window.gogiSetTime / gogiGetTime) ----------------

func _setup_web_time_hooks() -> void:
	if not OS.has_feature("web") or weather == null:
		return
	_js_set_time_cb = JavaScriptBridge.create_callback(_on_gogi_set_time)
	var win = JavaScriptBridge.get_interface("window")
	if win != null:
		win.gogiSetTime = _js_set_time_cb
	JavaScriptBridge.eval("window.__gogiTime='%s';window.gogiGetTime=function(){return window.__gogiTime;};" % weather.time_state, true)
	_js_get_player_cb = JavaScriptBridge.create_callback(_on_gogi_get_player)
	_js_solids_cb = JavaScriptBridge.create_callback(_on_gogi_solids)
	if win != null:
		win.__gogiGetPlayerRaw = _js_get_player_cb
		win.__gogiSolidsRaw = _js_solids_cb
	JavaScriptBridge.eval(
		"window.gogiGetPlayer=function(){var s=window.__gogiGetPlayerRaw();return s?JSON.parse(s):null;};" +
		"window.gogiSolids=function(){var s=window.__gogiSolidsRaw();return s?JSON.parse(s):[];};", true)


func _on_gogi_set_time(args: Array) -> void:
	if weather == null or args.is_empty():
		return
	var state := String(args[0])
	weather.set_time(state)
	JavaScriptBridge.eval("window.__gogiTime='%s';" % weather.time_state, true)
	print("GOGI_TIME ", weather.time_state)


func _on_gogi_get_player(_args: Array) -> String:
	if player == null or not is_instance_valid(player):
		return "null"
	var p := player.global_position
	return JSON.stringify({"x": p.x, "y": p.y, "z": p.z, "in_vehicle": false, "on_floor": player.is_on_floor(), "chest_found": chest_found})


func _on_gogi_solids(_args: Array) -> String:
	var out: Array = []
	var scene := get_tree().current_scene
	if scene != null:
		_collect_solids(scene, out)
	return JSON.stringify(out)


func _collect_solids(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is StaticBody3D and not (c as Node).is_in_group("gogi_terrain"):
			var ab := _body_world_aabb(c as StaticBody3D)
			if ab.size.length() > 0.01:
				out.append({
					"min": [ab.position.x, ab.position.y, ab.position.z],
					"max": [ab.end.x, ab.end.y, ab.end.z]})
		_collect_solids(c, out)


func _body_world_aabb(body: StaticBody3D) -> AABB:
	var merged := AABB()
	var first := true
	for cs in body.get_children():
		if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
			var dm := (cs as CollisionShape3D).shape.get_debug_mesh()
			if dm == null:
				continue
			var wa: AABB = (cs as CollisionShape3D).global_transform * dm.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# GROUND material presets — tiled procedural normal map for real surface relief.
const GROUND_PRESETS := {
	"grass":    {"color": [0.30, 0.48, 0.23], "rough": 1.0,  "tiling": 13.0, "bump": 0.45},
	"dirt":     {"color": [0.40, 0.31, 0.22], "rough": 0.98, "tiling": 11.0, "bump": 0.5},
}


func ground_material(spec) -> StandardMaterial3D:
	var color := Color(0.3, 0.4, 0.28)
	var rough := 0.95
	var tiling := 10.0
	var bump := 0.4
	if typeof(spec) == TYPE_STRING and GROUND_PRESETS.has(String(spec).to_lower()):
		var pr: Dictionary = GROUND_PRESETS[String(spec).to_lower()]
		color = Color(pr["color"][0], pr["color"][1], pr["color"][2])
		rough = pr["rough"]
		tiling = pr["tiling"]
		bump = pr["bump"]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.uv1_scale = Vector3(tiling, tiling, tiling)
	m.normal_enabled = true
	m.normal_texture = _noise_normal(int(tiling * 7.0) + int(color.r * 255.0), bump)
	m.normal_scale = clampf(bump, 0.0, 1.0)
	return m


func _noise_normal(seed_i: int, bump: float) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.05
	fn.seed = seed_i
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = maxf(0.6, bump * 16.0)
	nt.noise = fn
	return nt
