extends Node
## 音效总线：统一加载 assets/audio/ 下的合成音效，用一组播放器做混播。
## 所有界面都通过语义化入口调用（play_click / play_reveal / play_outcome ...），
## 没有音频资源或处于 headless 时静默降级，不影响任何游戏逻辑。
##
## 音源由 tools/gen_sfx.tscn 离线合成，见该脚本顶部说明。

const DIR := "res://assets/audio/"
const VOICES := 10          # 混播声部数量
const BASE_DB := -7.0       # 总线基准音量

## 全部音效名（与 assets/audio/ 下的文件名一一对应）
const NAMES := [
	"click", "open", "flip",
	"reveal_t1", "reveal_t2", "reveal_t3", "reveal_t4", "reveal_t5",
	"promote_spin", "promote_success", "promote_hold", "promote_damage", "promote_breakdown",
	"disassemble", "trade", "error",
]

var muted := false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.volume_db = BASE_DB
		add_child(p)
		_players.append(p)
	_load_all()

func _load_all() -> void:
	for n in NAMES:
		var path: String = DIR + str(n) + ".wav"
		if not ResourceLoader.exists(path):
			continue
		var s: Resource = load(path)
		if s is AudioStream:
			_streams[n] = s

# ---------------- 基础播放 ----------------

func has_sound(name: String) -> bool:
	return _streams.has(name)

## 播放。delay > 0 时延迟触发（用于与动画对齐）。
func play(name: String, pitch := 1.0, delay := 0.0, extra_db := 0.0) -> void:
	if muted or not _streams.has(name):
		return
	if delay > 0.0:
		var t := get_tree().create_timer(delay, true, false, true)
		t.timeout.connect(func(): _fire(name, pitch, extra_db))
		return
	_fire(name, pitch, extra_db)

func _fire(name: String, pitch: float, extra_db: float) -> void:
	if muted or not _streams.has(name) or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.volume_db = BASE_DB + extra_db
	p.play()

# ---------------- 语义化入口 ----------------

## 按钮点击 / 通用交互反馈
func play_click() -> void:
	play("click", randf_range(0.97, 1.05))

## 按键失败、信用点不足等负反馈
func play_error() -> void:
	play("error")

## 物品揭晓：按阶次选择音效
func play_reveal(tier: int, delay := 0.0) -> void:
	play("reveal_t%d" % clampi(tier, 1, 5), 1.0, delay)

## 晋升结果：成功 / 稳定 / 损伤 / 崩解
func play_outcome(key: String, delay := 0.0) -> void:
	match key:
		"success":   play("promote_success", 1.0, delay)
		"hold":      play("promote_hold", 1.0, delay)
		"damage":    play("promote_damage", 1.0, delay)
		"breakdown": play("promote_breakdown", 1.0, delay)
		_:           play("error", 1.0, delay)

# ---------------- 静音开关 ----------------

func set_muted(v: bool) -> void:
	muted = v
	if muted:
		for p in _players:
			p.stop()

func toggle_mute() -> bool:
	set_muted(not muted)
	return muted
