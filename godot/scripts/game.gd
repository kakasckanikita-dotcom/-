extends Node
## Глобальное состояние игры (автозагрузка «Game»): характеристики героя,
## деньги, розыск, время суток, звуки и сохранение.

signal toast(text: String, color: Color)

const SAVE_PATH := "user://save.json"
const CREAM := Color(0.953, 0.886, 0.753)
const GOLD := Color(1.0, 0.824, 0.478)
const GOOD := Color(0.62, 0.88, 0.54)
const BAD := Color(1.0, 0.54, 0.42)

var world: Node = null

# --- герой ---
var hp := 100.0
var focus := 100.0
var stam := 100.0
var clip := 6
var ammo := 36
var medkits := 2
var tonics := 1
var money := 40
var honor := 0
var kills := 0

# --- мир ---
var wanted := 0
var evade := 0.0
var game_time := 480.0 # минуты от полуночи
var day := 1
var bounty = null # {name, reward, camp, done}
var bank_cd := 0.0

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _light_tex: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_make_sounds()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func say(text: String, color := CREAM) -> void:
	toast.emit(text, color)


## 0 — день, 0.72 — глубокая ночь.
func darkness() -> float:
	var h := game_time / 60.0
	if h >= 7.0 and h < 18.0:
		return 0.0
	if h >= 18.0 and h < 21.0:
		return (h - 18.0) / 3.0 * 0.72
	if h >= 5.0 and h < 7.0:
		return (1.0 - (h - 5.0) / 2.0) * 0.72
	return 0.72


func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_light_tex = GradientTexture2D.new()
		_light_tex.gradient = g
		_light_tex.width = 256
		_light_tex.height = 256
		_light_tex.fill = GradientTexture2D.FILL_RADIAL
		_light_tex.fill_from = Vector2(0.5, 0.5)
		_light_tex.fill_to = Vector2(1.0, 0.5)
	return _light_tex


# ---------- управление ----------
func _setup_input() -> void:
	# physical_keycode — работает при любой раскладке (в том числе русской)
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E], "reload": [KEY_R], "focus": [KEY_SHIFT],
		"sprint": [KEY_SPACE], "whistle": [KEY_H], "medkit": [KEY_Q],
		"tonic": [KEY_F], "map": [KEY_M], "menu_close": [KEY_ESCAPE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", mb)


# ---------- звук (синтезируется при запуске, файлов не нужно) ----------
const RATE := 22050

func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sound]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func _make_sounds() -> void:
	_sounds["shot"] = _wav(_noise(0.22, 3.0, 0.35, 1.6))
	_sounds["click"] = _wav(_noise(0.03, 1.0, 0.9, 0.6))
	_sounds["reload"] = _wav(_concat([_noise(0.03, 1.0, 0.9, 0.5), _silence(0.12), _noise(0.03, 1.0, 0.9, 0.5), _silence(0.12), _noise(0.04, 1.0, 0.7, 0.6)]))
	_sounds["hurt"] = _wav(_tone(180.0, 90.0, 0.25, 0.5, true))
	_sounds["death"] = _wav(_tone(140.0, 50.0, 0.9, 0.5, true))
	_sounds["focus"] = _wav(_tone(160.0, 90.0, 0.5, 0.45, false))
	_sounds["mark"] = _wav(_tone(900.0, 900.0, 0.05, 0.3, true))
	_sounds["coin"] = _wav(_concat([_tone(990.0, 990.0, 0.06, 0.3, false), _tone(1320.0, 1320.0, 0.12, 0.3, false)]))
	_sounds["whistle"] = _wav(_concat([_tone(1400.0, 2100.0, 0.18, 0.35, false), _tone(2100.0, 1300.0, 0.25, 0.35, false)]))
	_sounds["horse"] = _wav(_tone(420.0, 520.0, 0.1, 0.3, false))
	_sounds["bounty"] = _wav(_concat([_tone(523.0, 523.0, 0.12, 0.3, false), _tone(659.0, 659.0, 0.12, 0.3, false), _tone(784.0, 784.0, 0.3, 0.3, false)]))


func _noise(dur: float, power: float, smooth: float, gain: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var a := PackedFloat32Array()
	a.resize(n)
	var prev := 0.0
	for i in n:
		var v := randf_range(-1.0, 1.0) * pow(1.0 - float(i) / n, power)
		prev = lerpf(prev, v, smooth)
		a[i] = prev * gain
	return a


func _tone(f0: float, f1: float, dur: float, vol: float, square: bool) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var s := sin(phase * TAU)
		if square:
			s = signf(s) * 0.6
		a[i] = s * vol * minf(1.0, (1.0 - t) * 4.0) * minf(1.0, t * 40.0)
	return a


func _silence(dur: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(RATE * dur))
	return a


func _concat(parts: Array) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for p in parts:
		a.append_array(p)
	return a


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	w.data = b
	return w


# ---------- сохранение ----------
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if world == null or world.player == null or world.player.dead:
		return
	var d := {
		"money": money, "honor": honor, "kills": kills, "ammo": ammo, "clip": clip,
		"medkits": medkits, "tonics": tonics, "game_time": game_time, "day": day,
		"x": world.player.global_position.x, "y": world.player.global_position.y,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	money = int(d.get("money", 40))
	honor = int(d.get("honor", 0))
	kills = int(d.get("kills", 0))
	ammo = int(d.get("ammo", 36))
	clip = int(d.get("clip", 6))
	medkits = int(d.get("medkits", 2))
	tonics = int(d.get("tonics", 1))
	game_time = float(d.get("game_time", 480.0))
	day = int(d.get("day", 1))
	world.place_player(Vector2(float(d.get("x", 1100.0)), float(d.get("y", 1300.0))))
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
