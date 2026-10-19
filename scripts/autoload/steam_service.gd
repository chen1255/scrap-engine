extends Node
## Steam 集成（GodotSteam GDExtension）：成就同步 + 云存档 + 状态查询。
##
## 设计要点：**绝不直接写 `Steam.xxx` 标识符**——缺少 addon 时 GDScript 会在解析期报错。
## 统一由 Engine.has_singleton("Steam") / Engine.get_singleton("Steam") 动态访问，
## 因此「没有 addon」或「Steam 客户端未运行」时，本单例整体降级为 no-op，游戏照常可玩。
##
## 本地存档始终是权威状态；Steam 侧仅做 best-effort 同步，任何调用失败都不影响玩法。

const SAVE_PATH := "user://scrap_engine_save.json"
const CLOUD_NAME := "scrap_engine_save.json"   # 云端文件名（与本地同名）
const APPID_FILE := "res://steam_appid.txt"
const DEFAULT_APP_ID := 480                     # Spacewar：Valve 公共测试 app

var _steam: Object = null                       # Steam 单例（缺失时为 null）
var _available := false
var _reason := ""
var _app_id := DEFAULT_APP_ID
var _persona := ""
var _steam_id := 0
var _auto_upload := false
var _last_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		_reason = "未安装 GodotSteam 扩展（addons/godotsteam 缺失）"
		return
	_steam = Engine.get_singleton("Steam")
	_app_id = _read_app_id()
	_init_steam()
	GameState.saved.connect(_on_saved)
	if _available:
		_auto_upload = true   # 默认开启自动上传（面板里可关闭）

func _process(_delta: float) -> void:
	if _available and _steam != null and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")

func _read_app_id() -> int:
	if not FileAccess.file_exists(APPID_FILE):
		return DEFAULT_APP_ID
	var txt := FileAccess.get_file_as_string(APPID_FILE).strip_edges()
	return int(txt) if txt.is_valid_int() else DEFAULT_APP_ID

func _init_steam() -> void:
	# 不使用 embed_callbacks：改由 _process 每帧 pump run_callbacks，避免与引擎主循环耦合
	var res: Variant = _steam.call("steamInitEx", _app_id, false)
	if typeof(res) == TYPE_DICTIONARY:
		var r: Dictionary = res
		var status := int(r.get("status", -1))
		if status != 0:
			_reason = "Steam 初始化失败（%d）：%s" % [status, str(r.get("verbal", ""))]
			return
	elif not bool(_steam.call("steamInit", _app_id, false)):
		_reason = "Steam 初始化失败"
		return
	_available = true
	_reason = ""
	if _steam.has_method("getPersonaName"):
		_persona = str(_steam.call("getPersonaName"))
	if _steam.has_method("getSteamID"):
		_steam_id = int(_steam.call("getSteamID"))
	# 初始化成功后，把本地已解锁成就补推一次（best-effort）
	call_deferred("_push_all_unlocked")

# ---------------- 状态查询 ----------------

func is_available() -> bool:
	return _available

func unavailable_reason() -> String:
	return _reason

func persona_name() -> String:
	return _persona

func steam_id() -> int:
	return _steam_id

func app_id() -> int:
	return _app_id

func last_error() -> String:
	return _last_error

func is_auto_upload() -> bool:
	return _auto_upload

func set_auto_upload(v: bool) -> void:
	_auto_upload = v

# ---------------- 成就桥 ----------------

## 把一条成就推给 Steam（steam_name 为空或未启用时静默跳过）。
## 说明：Spacewar(480) 未在后台定义这些成就名，setAchievement 可能不生效——属预期，
## 本地解锁状态才是权威；换成自有 App ID 并在 Steamworks 后台定义同名成就后即可完整生效。
func push_achievement(steam_name: String) -> bool:
	if not _available or steam_name == "":
		return false
	var ok := bool(_steam.call("setAchievement", steam_name))
	if _steam.has_method("storeStats"):
		_steam.call("storeStats")
	if not ok:
		_last_error = "setAchievement(%s) 未生效（后台未定义该成就名？）" % steam_name
	return ok

func _push_all_unlocked() -> void:
	if not _available:
		return
	for a in Achievements.defs:
		if GameState.achievements.has(str(a["id"])):
			push_achievement(str(a.get("steam", "")))

# ---------------- 云存档 ----------------

func cloud_upload() -> Dictionary:
	if not _available:
		return { "ok": false, "reason": unavailable_reason() }
	if not FileAccess.file_exists(SAVE_PATH):
		return { "ok": false, "reason": "本地没有存档文件" }
	var bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	if bytes.is_empty():
		return { "ok": false, "reason": "本地存档为空" }
	var ok := bool(_steam.call("fileWrite", CLOUD_NAME, bytes, bytes.size()))
	if not ok:
		_last_error = "Steam 云写入失败"
	return { "ok": ok, "reason": "" if ok else "Steam 云写入失败", "size": bytes.size() }

func cloud_info() -> Dictionary:
	if not _available:
		return { "available": false, "reason": unavailable_reason() }
	var exists := bool(_steam.call("fileExists", CLOUD_NAME))
	var size := 0
	var ts := 0
	if exists:
		if _steam.has_method("getFileSize"):
			size = int(_steam.call("getFileSize", CLOUD_NAME))
		if _steam.has_method("getFileTimestamp"):
			ts = int(_steam.call("getFileTimestamp", CLOUD_NAME))
	var quota: Dictionary = {}
	if _steam.has_method("getQuota"):
		var q: Variant = _steam.call("getQuota")
		if typeof(q) == TYPE_DICTIONARY:
			quota = q
	var cloud_on := false
	if _steam.has_method("isCloudEnabledForAccount"):
		cloud_on = bool(_steam.call("isCloudEnabledForAccount"))
	return {
		"available": true, "exists": exists, "size": size, "timestamp": ts,
		"quota_total": int(quota.get("total_bytes", 0)),
		"quota_free": int(quota.get("available_bytes", 0)),
		"cloud_enabled": cloud_on,
	}

## 从云端拉取存档写回本地并重载。force=false 时遵循「新者优先」：本地不比云端旧就跳过。
func cloud_download(force: bool = false) -> Dictionary:
	if not _available:
		return { "ok": false, "reason": unavailable_reason() }
	if not bool(_steam.call("fileExists", CLOUD_NAME)):
		return { "ok": false, "reason": "云端没有存档" }
	if not force and FileAccess.file_exists(SAVE_PATH):
		var local_ts := int(FileAccess.get_modified_time(SAVE_PATH))
		var cloud_ts := int(_steam.call("getFileTimestamp", CLOUD_NAME))
		if cloud_ts > 0 and local_ts >= cloud_ts:
			return { "ok": false, "skipped": true, "reason": "本地存档更新，已跳过下载" }

	var buf := _read_cloud_bytes()
	if buf.is_empty():
		return { "ok": false, "reason": "云端存档为空或读取失败" }

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "reason": "无法写入本地存档" }
	f.store_buffer(buf)
	f.close()

	GameState.load_game()
	GameState.emit_inventory()
	GameState.credits_changed.emit(GameState.credits)
	GameState.energy_changed.emit(GameState.energy)
	GameState.market_tick.emit(MarketSystem.tick)
	return { "ok": true, "size": buf.size() }

func _read_cloud_bytes() -> PackedByteArray:
	var rd: Variant = _steam.call("fileRead", CLOUD_NAME, 0)   # 0 = 整读
	var buf: PackedByteArray = PackedByteArray()
	if typeof(rd) == TYPE_DICTIONARY:
		buf = (rd as Dictionary).get("buffer", PackedByteArray())
	if buf.is_empty() and _steam.has_method("getFileSize"):
		var sz := int(_steam.call("getFileSize", CLOUD_NAME))
		if sz > 0:
			rd = _steam.call("fileRead", CLOUD_NAME, sz)
			if typeof(rd) == TYPE_DICTIONARY:
				buf = (rd as Dictionary).get("buffer", PackedByteArray())
	return buf

func _on_saved() -> void:
	if _available and _auto_upload:
		cloud_upload()
