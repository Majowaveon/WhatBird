class_name HeronAudio
extends Node

const SOUND_ROOT: String = "res://assets/Resources/Sounds/"
const SFX: Dictionary = {
	"heron": ["Heron1", "Heron2", "Heron3", "Heron4"],
	"mallard": ["Mallard1", "Mallard2"],
	"penguin": ["GuGuGaGa1", "GuGuGaGa2", "GuGuGaGa3", "GuGuGaGa4"],
	"woodpecker": ["WoodPecker1", "WoodPecker2"],
	"drum": ["WoodPecker-Drumming1", "WoodPecker-Drumming2"],
	"land": ["SFXLand1", "SFXLand2", "SFXLand3"],
	"splash": ["SFXSplash1", "SFXSplash2"],
	"spring": ["JumpPad"],
	"step": ["SFXStepGrass1", "SFXStepGrass2", "SFXStepGrass3", "SFXStepGrass4"],
	"swim": ["SFXSwimPaddle1", "SFXSwimPaddle2"],
}
var music: AudioStreamPlayer
var glide: AudioStreamPlayer
var ambient: Array[AudioStreamPlayer] = []
var previous: Dictionary = {}
var music_fade: Tween

func _ready() -> void:
	music = AudioStreamPlayer.new()
	add_child(music)
	music.volume_db = -15.0
	glide = AudioStreamPlayer.new()
	add_child(glide)
	glide.volume_db = -13.0
	music.finished.connect(_next_music)

func start_music(environment: bool = true) -> void:
	if not music.playing:
		_next_music()
	if environment and ambient.is_empty():
		for path: String in ["Ambient/AmbentGrass", "Ambient/AmbientBird"]:
			var node := AudioStreamPlayer.new()
			add_child(node)
			node.stream = load(SOUND_ROOT + path + ".wav") as AudioStream
			node.volume_db = -22.0
			node.finished.connect(node.play)
			node.play()
			ambient.append(node)

func stop_environment() -> void:
	for node: AudioStreamPlayer in ambient:
		node.queue_free()
	ambient.clear()
	glide.stop()

func shutdown() -> void:
	if music_fade and music_fade.is_valid():
		music_fade.kill()
	for node: Node in get_children():
		if node is AudioStreamPlayer:
			var audio_player: AudioStreamPlayer = node
			audio_player.stop()
			audio_player.stream = null
	ambient.clear()

func _exit_tree() -> void:
	shutdown()

func _next_music() -> void:
	var tracks: Array[String] = ["761294__rotlily__melancholic-piano-loop", "832628__rotlily__calm-ambient-piano-loop"]
	if music_fade and music_fade.is_valid():
		music_fade.kill()
	music.stream = load(SOUND_ROOT + tracks.pick_random() + ".wav") as AudioStream
	music.volume_db = -60.0
	music.play()
	music_fade = create_tween()
	music_fade.tween_property(music, "volume_db", -15.0, 0.5)

func play_sound(kind: String) -> void:
	if kind in ["glide_stop", "stop_glide"]:
		glide.stop()
		return
	if kind in ["glide", "glide_start"]:
		_one_shot("SFXWing")
		glide.stream = load(SOUND_ROOT + "SFX/SFXGlide.wav") as AudioStream
		glide.play()
		return
	if kind.begins_with("transform_"):
		kind = kind.trim_prefix("transform_")
	if not SFX.has(kind):
		return
	var samples: Array = SFX[kind]
	var choices: Array = samples.duplicate()
	if choices.size() > 1:
		choices.erase(previous.get(kind, ""))
	var sample: String = choices.pick_random()
	previous[kind] = sample
	_one_shot(sample)

func _one_shot(sample: String) -> void:
	var path: String = SOUND_ROOT + "SFX/" + sample + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing exported audio: " + path)
		return
	var node := AudioStreamPlayer.new()
	add_child(node)
	node.stream = load(path) as AudioStream
	node.volume_db = -9.0
	node.finished.connect(node.queue_free)
	node.play(0.015 if sample.begins_with("SFXLand") else 0.0)
