extends Node
## 全局设置：音频总线（主音量 / 音效 / BGM）、画面（全屏 / 分辨率）、
## 界面（字号缩放 / 色盲友好配色）、存档槽位选择。
##
## 设计要点：
##   * 音频总线在**运行期创建**（不落 .tres 资源），Master → Music / SFX 三级结构；
##   * 全部设置持久化到 user://scrap_settings.cfg，任何一次改动立即落盘；
##   * 本单例必须排在 Sfx / Bgm 之前自动加载，保证它们 _ready 时总线已就绪；
##   * 不依赖任何 addon / 音频设备：headless 与无声卡环境下所有调用安全降级。

signal changed(kind: String)   # kind: audio / video / ui / slot / all

const CFG_PATH := "user://scrap_settings.cfg"

## 可选分辨率（窗口模式用）
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1360, 820),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

## 可选字号缩放档位
const FONT_SCALES := [0.9, 1.0, 1.15, 1.3]

# ---------------- 音频 ----------------
var master_vol := 0.85
var sfx_vol := 0.90
var music_vol := 0.55
var sfx_enabled := true
var music_enabled := true

# ---------------- 画面 ----------------
var fullscreen := false
var resolution := Vector2i(1360, 820)

# ---------------- 界面 ----------------
var font_scale := 1.0
var colorblind := false

# ---------------- 存档 ----------------
var slot := 1

var _bus_ready := false

func _ready() -> void:
	_ensure_buses()
	load_config()
	# GameState 先于本单例 _ready，会先按槽 1 载入；这里把用户上次选的槽位同步过去。
	var gs := get_node_or_null("/root/GameState")
	if gs != null and slot != int(gs.get("save_slot")):
		gs.call("use_slot", slot, true)
	apply_all()

# ---------------- 音频总线 ----------------

## 确保 Master → Music / SFX 三级总线存在。重复调用安全。
func _ensure_buses() -> void:
	_make_bus("Music")
	_make_bus("SFX")
	_bus_ready = AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0

func _make_bus(name: String) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func has_bus(name: String) -> bool:
	return AudioServer.get_bus_index(name) >= 0

## 写一条总线的音量与静音状态：音量线性值 0~1 → 分贝；0 或未启用即静音。
func _apply_bus(name: String, linear: float, enabled: bool) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		return
	var audible: bool = enabled and linear > 0.001
	AudioServer.set_bus_mute(idx, not audible)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.001, 1.0)))

func apply_audio() -> void:
	_apply_bus("Master", master_vol, true)
	_apply_bus("Music", music_vol, music_enabled)
	_apply_bus("SFX", sfx_vol, sfx_enabled)
	# 让音效层同步静音快路径，避免仍去调度播放
	var sfx_node := get_node_or_null("/root/Sfx")
	if sfx_node != null and sfx_node.has_method("set_muted"):
		sfx_node.call("set_muted", not sfx_enabled)
	var bgm_node := get_node_or_null("/root/Bgm")
	if bgm_node != null and bgm_node.has_method("set_enabled"):
		bgm_node.call("set_enabled", music_enabled)

# ---------------- 画面 ----------------

func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win == null:
		return
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.mode = Window.MODE_WINDOWED
		win.size = resolution
		_center_window(win)

func _center_window(win: Window) -> void:
	var screen := DisplayServer.screen_get_size()
	var pos := (screen - win.size) / 2
	win.position = Vector2i(maxi(pos.x, 0), maxi(pos.y, 0))

# ---------------- 界面 ----------------

func apply_ui() -> void:
	UIKit.set_scale(font_scale)
	UIKit.apply_palette(colorblind)

# ---------------- 汇总应用 ----------------

func apply_all() -> void:
	apply_audio()
	apply_video()
	apply_ui()

# ---------------- 变更入口（改完即存盘） ----------------

func set_master_vol(v: float) -> void:
	master_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save()
	changed.emit("audio")

func set_sfx_vol(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save()
	changed.emit("audio")

func set_music_vol(v: float) -> void:
	music_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save()
	changed.emit("audio")

func set_sfx_enabled(v: bool) -> void:
	sfx_enabled = v
	apply_audio()
	save()
	changed.emit("audio")

func toggle_sfx() -> bool:
	set_sfx_enabled(not sfx_enabled)
	return sfx_enabled

func set_music_enabled(v: bool) -> void:
	music_enabled = v
	apply_audio()
	save()
	changed.emit("audio")

func toggle_music() -> bool:
	set_music_enabled(not music_enabled)
	return music_enabled

func set_fullscreen(v: bool) -> void:
	fullscreen = v
	apply_video()
	save()
	changed.emit("video")

func set_resolution(r: Vector2i) -> void:
	resolution = r
	apply_video()
	save()
	changed.emit("video")

func set_font_scale(s: float) -> void:
	font_scale = clampf(s, 0.85, 1.6)
	apply_ui()
	save()
	changed.emit("ui")

func set_colorblind(v: bool) -> void:
	colorblind = v
	apply_ui()
	save()
	changed.emit("ui")

func set_slot(n: int) -> void:
	slot = clampi(n, 1, 3)
	save()
	changed.emit("slot")

## 恢复出厂设置（不改动当前存档内容与所选槽位）。
func reset_defaults() -> void:
	master_vol = 0.85
	sfx_vol = 0.90
	music_vol = 0.55
	sfx_enabled = true
	music_enabled = true
	fullscreen = false
	resolution = Vector2i(1360, 820)
	font_scale = 1.0
	colorblind = false
	apply_all()
	save()
	changed.emit("all")

# ---------------- 持久化 ----------------

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master_vol", master_vol)
	cf.set_value("audio", "sfx_vol", sfx_vol)
	cf.set_value("audio", "music_vol", music_vol)
	cf.set_value("audio", "sfx_enabled", sfx_enabled)
	cf.set_value("audio", "music_enabled", music_enabled)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "resolution", resolution)
	cf.set_value("ui", "font_scale", font_scale)
	cf.set_value("ui", "colorblind", colorblind)
	cf.set_value("save", "slot", slot)
	cf.save(CFG_PATH)

func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return   # 首次运行 / 文件损坏：沿用默认值
	master_vol = clampf(float(cf.get_value("audio", "master_vol", master_vol)), 0.0, 1.0)
	sfx_vol = clampf(float(cf.get_value("audio", "sfx_vol", sfx_vol)), 0.0, 1.0)
	music_vol = clampf(float(cf.get_value("audio", "music_vol", music_vol)), 0.0, 1.0)
	sfx_enabled = bool(cf.get_value("audio", "sfx_enabled", sfx_enabled))
	music_enabled = bool(cf.get_value("audio", "music_enabled", music_enabled))
	fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))
	var res: Variant = cf.get_value("video", "resolution", resolution)
	if res is Vector2i:
		resolution = res
	font_scale = clampf(float(cf.get_value("ui", "font_scale", font_scale)), 0.85, 1.6)
	colorblind = bool(cf.get_value("ui", "colorblind", colorblind))
	slot = clampi(int(cf.get_value("save", "slot", slot)), 1, 3)
