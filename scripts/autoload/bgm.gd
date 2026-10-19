extends Node
## 背景音乐与环境音：运行期循环播放 assets/audio 下的合成 BGM，按视图交叉淡切。
##
## 设计要点：
##   * 音频由 tools/gen_bgm.tscn 离线合成，尾音做了「回卷」，整段信号严格以时长为周期，
##     因此可直接用 LOOP_FORWARD 无缝循环；
##   * 循环点在运行期按采样帧数设置，不依赖手写 .import 参数；
##   * 双播放器 0.8s 交叉淡入淡出，切换视图时不做硬切；
##   * 无音频资源 / headless / 音乐关闭时全部安全降级为 no-op，不影响玩法。
##
## 加载顺序：必须排在 Settings 之后（读取 settings.music_enabled 与 Music 总线）。

const DIR := "res://assets/audio/"
const FADE := 0.8
const TARGET_DB := -9.0          # BGM 基准音量（相对 Music 总线）
const SILENT_DB := -60.0
const AMBIENT_DB := -20.0        # 环境铺底更轻

## 曲目表：逻辑名 → 文件名
const TRACKS := {
	"lobby": "bgm_lobby",
	"workshop": "bgm_workshop",
	"exchange": "bgm_exchange",
}

## 视图 → 曲目（key 与 main.gd 的视图 id 对齐）
const VIEW_TRACK := {
	"market": "lobby",
	"inventory": "lobby",
	"codex": "lobby",
	"steam": "lobby",
	"settings": "lobby",
	"disassembly": "workshop",
	"promotion": "workshop",
	"repair": "workshop",
	"exchange": "exchange",
}

const AMBIENT := "amb_hangar"

var _streams: Dictionary = {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _use_b := false
var _cur_key := ""
var _enabled := true
var _tw_in: Tween
var _tw_out: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		_enabled = bool(settings.get("music_enabled"))

	var bus := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_a = _make_player(bus)
	_b = _make_player(bus)
	_ambient = _make_player(bus)
	_load_all()
	if _enabled:
		_start_ambient()

func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = SILENT_DB
	add_child(p)
	return p

# ---------------- 资源加载 ----------------

func _load_all() -> void:
	for key in TRACKS:
		var w := _load_looped(str(TRACKS[key]))
		if w != null:
			_streams[key] = w
	var amb := _load_looped(AMBIENT)
	if amb != null:
		_streams["ambient"] = amb

## 载入一段 WAV 并把它配置成首尾无缝循环。文件缺失时返回 null（静默降级）。
func _load_looped(fname: String) -> AudioStreamWAV:
	var path := DIR + fname + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if not (res is AudioStreamWAV):
		return null
	var w: AudioStreamWAV = res
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = _frame_count(w)
	return w

## 采样帧数。优先用引擎算出的时长 × 采样率（对 PCM / ADPCM / QOA 都成立）。
func _frame_count(w: AudioStreamWAV) -> int:
	var by_len := int(round(w.get_length() * float(w.mix_rate)))
	if by_len > 0:
		return by_len
	match w.format:
		AudioStreamWAV.FORMAT_16_BITS:
			return maxi(1, w.data.size() / 2)
		AudioStreamWAV.FORMAT_IMA_ADPCM:
			return maxi(1, w.data.size() * 2)
		_:
			return maxi(1, w.data.size())

# ---------------- 查询 ----------------

func has_track(key: String) -> bool:
	return _streams.has(key)

func has_ambient() -> bool:
	return _streams.has("ambient")

## 取曲目流资源（自测与调试用；不存在时返回 null）。
func get_stream(key: String) -> AudioStream:
	return _streams.get(key, null)

func current_track() -> String:
	return _cur_key

func is_enabled() -> bool:
	return _enabled

func track_keys() -> Array:
	return TRACKS.keys()

func view_track(view_id: String) -> String:
	return str(VIEW_TRACK.get(view_id, "lobby"))

# ---------------- 播放控制 ----------------

## 按视图切换 BGM；未知视图回落到大厅曲目。
func play_view(view_id: String) -> void:
	_cur_key = ""
	if not _enabled:
		return
	_play_track(view_track(view_id))

func play_track(key: String) -> void:
	if not _enabled:
		return
	_play_track(key)

func _play_track(key: String) -> void:
	if not _streams.has(key):
		return
	if key == _cur_key and (_a.playing or _b.playing):
		return
	_cur_key = key

	var from := _b if _use_b else _a
	var to := _a if _use_b else _b
	_use_b = not _use_b

	to.stream = _streams[key]
	to.volume_db = SILENT_DB
	to.play()
	if _tw_in != null and _tw_in.is_valid():
		_tw_in.kill()
	_tw_in = create_tween()
	_tw_in.tween_property(to, "volume_db", TARGET_DB, FADE).set_trans(Tween.TRANS_SINE)

	if _tw_out != null and _tw_out.is_valid():
		_tw_out.kill()
	if from.playing:
		_tw_out = create_tween()
		_tw_out.tween_property(from, "volume_db", SILENT_DB, FADE).set_trans(Tween.TRANS_SINE)
		_tw_out.tween_callback(from.stop)

func _start_ambient() -> void:
	if not _streams.has("ambient") or _ambient == null:
		return
	if _ambient.playing:
		return
	_ambient.stream = _streams["ambient"]
	_ambient.volume_db = AMBIENT_DB
	_ambient.play()

func set_enabled(v: bool) -> void:
	if _enabled == v:
		return
	_enabled = v
	if not v:
		_stop_all()
	else:
		_start_ambient()
		var k := _cur_key
		_cur_key = ""
		if k != "":
			_play_track(k)

func _stop_all() -> void:
	if _tw_in != null and _tw_in.is_valid():
		_tw_in.kill()
	if _tw_out != null and _tw_out.is_valid():
		_tw_out.kill()
	_a.stop()
	_b.stop()
	_ambient.stop()

## 退出时释放播放器持有的流引用与游离的 Tween，避免退出期资源占用告警。
func _exit_tree() -> void:
	_stop_all()
	_a.stream = null
	_b.stream = null
	_ambient.stream = null
	_streams.clear()
