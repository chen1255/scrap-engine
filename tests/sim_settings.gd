extends Node
## headless 设置 / 音频 / 存档槽位自测：
##   1) 音频总线：Master → Music / SFX 三级结构已建立，音量线性值正确映射到分贝；
##   2) BGM：4 段曲目全部加载，且循环点按采样帧数配置（首尾无缝）；
##   3) 设置往返：改值 → 落盘 → 重新读取一致；色盲配色与字号缩放可作用于 UIKit；
##   4) 存档槽位：切换 / 存档 / 摘要 / 删除，且 Steam 云文件名随槽位变化。
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_settings.tscn
##
## 说明：本测试只使用槽 2 / 槽 3 做读写验证，绝不改写槽 1 的真实存档；结束后恢复默认设置。

var _fails := 0
var _start_slot := 1

func _ready() -> void:
	print("==================== 废料引擎 · 设置与音频自测 ====================")
	_start_slot = GameState.save_slot
	_test_buses()
	_test_bgm()
	_test_settings_roundtrip()
	_test_palette_and_scale()
	_test_slots()
	print("=================================================================")
	_restore()
	if _fails == 0:
		print("[PASS] 设置 / 音频 / 存档槽位自测全部通过。")
	else:
		print("[FAIL] 存在 %d 项断言失败。" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 1) 音频总线 ----------------

func _test_buses() -> void:
	print("\n---- 1) 音频总线 ----")
	_check(Settings.has_bus("Music"), "Music 总线已建立")
	_check(Settings.has_bus("SFX"), "SFX 总线已建立")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == "Master", "Music 挂到 Master")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == "Master", "SFX 挂到 Master")

	Settings.set_master_vol(0.5)
	var idx := AudioServer.get_bus_index("Master")
	var db := AudioServer.get_bus_volume_db(idx)
	_check(absf(db - linear_to_db(0.5)) < 0.01, "主音量 0.5 → %.2f dB" % db)
	_check(not AudioServer.is_bus_mute(idx), "主音量非静音")

	Settings.set_master_vol(0.0)
	_check(AudioServer.is_bus_mute(idx), "主音量 0 → 静音")

	Settings.set_sfx_enabled(false)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "关闭音效 → SFX 总线静音")
	_check(Sfx.muted, "Sfx 单例同步为静音")
	Settings.set_sfx_enabled(true)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "重新开启音效 → 解除静音")
	_check(not Sfx.muted, "Sfx 单例同步解除静音")

# ---------------- 2) BGM ----------------

func _test_bgm() -> void:
	print("\n---- 2) BGM 曲目 ----")
	var keys := Bgm.track_keys()
	_check(keys.size() == 3, "曲目表 %d 段（大厅 / 车间 / 交易所）" % keys.size())
	_check(Bgm.has_ambient(), "环境音已加载")

	for k in keys:
		var key := str(k)
		_check(Bgm.has_track(key), "曲目 %s 已加载" % key)
		var stream: AudioStream = Bgm.get_stream(key)
		_check(stream is AudioStreamWAV, "曲目 %s 是 AudioStreamWAV" % key)
		if stream is AudioStreamWAV:
			var w: AudioStreamWAV = stream
			var frames := int(round(w.get_length() * float(w.mix_rate)))
			_check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "曲目 %s 循环模式 = FORWARD" % key)
			_check(w.loop_begin == 0, "曲目 %s 循环起点 = 0" % key)
			_check(w.loop_end == frames, "曲目 %s 循环终点 = %d 帧（%.1f 秒）" % [key, frames, w.get_length()])
			_check(frames > 0, "曲目 %s 帧数有效" % key)

	print("     视图映射：market→%s · repair→%s · exchange→%s"
		% [Bgm.view_track("market"), Bgm.view_track("repair"), Bgm.view_track("exchange")])
	_check(Bgm.view_track("market") == "lobby", "market 用大厅曲")
	_check(Bgm.view_track("repair") == "workshop", "repair 用车间曲")
	_check(Bgm.view_track("exchange") == "exchange", "exchange 用交易所曲")
	_check(Bgm.view_track("settings") == "lobby", "settings 用大厅曲")

	Bgm.play_view("repair")
	_check(Bgm.current_track() == "workshop", "play_view(repair) 切到车间曲")
	Bgm.play_track("")
	_check(Bgm.current_track() == "workshop", "空曲目名不改动当前曲目")

# ---------------- 3) 设置往返 ----------------

func _test_settings_roundtrip() -> void:
	print("\n---- 3) 设置往返 ----")
	Settings.set_master_vol(0.42)
	Settings.set_sfx_vol(0.66)
	Settings.set_music_vol(0.28)
	Settings.set_font_scale(1.15)
	Settings.set_colorblind(true)
	Settings.set_slot(2)

	var cf := ConfigFile.new()
	_check(cf.load(Settings.CFG_PATH) == OK, "设置文件已写出（%s）" % Settings.CFG_PATH)

	# 打乱内存值，再重新读取，验证持久化
	Settings.master_vol = 1.0
	Settings.sfx_vol = 1.0
	Settings.music_vol = 1.0
	Settings.font_scale = 1.0
	Settings.colorblind = false
	Settings.slot = 1
	Settings.load_config()

	_check(absf(Settings.master_vol - 0.42) < 0.001, "主音量往返 %.2f" % Settings.master_vol)
	_check(absf(Settings.sfx_vol - 0.66) < 0.001, "音效音量往返 %.2f" % Settings.sfx_vol)
	_check(absf(Settings.music_vol - 0.28) < 0.001, "BGM 音量往返 %.2f" % Settings.music_vol)
	_check(absf(Settings.font_scale - 1.15) < 0.001, "字号缩放往返 %.2f" % Settings.font_scale)
	_check(Settings.colorblind, "色盲开关往返 true")
	_check(Settings.slot == 2, "槽位选择往返 2")

	Settings.master_vol = 0.85
	Settings.sfx_vol = 0.90
	Settings.music_vol = 0.55
	Settings.font_scale = 1.0
	Settings.apply_all()
	Settings.save()

# ---------------- 4) 配色与字号 ----------------

func _test_palette_and_scale() -> void:
	print("\n---- 4) 配色与字号 ----")
	UIKit.apply_palette(false)
	var ok_default := UIKit.OK
	var bad_default := UIKit.BAD
	_check(ok_default.to_html(false) == "4fe38a", "默认 OK 色 = #4fe38a")
	_check(UIKit.map_color(Color("#4fe38a")).to_html(false) == "4fe38a", "未启用色盲时映射原样返回")

	UIKit.apply_palette(true)
	_check(UIKit.COLORBLIND, "已启用色盲模式")
	_check(UIKit.OK != ok_default, "色盲模式下 OK 色被替换（%s → %s）" % [ok_default.to_html(false), UIKit.OK.to_html(false)])
	_check(UIKit.BAD != bad_default, "色盲模式下 BAD 色被替换（%s → %s）" % [bad_default.to_html(false), UIKit.BAD.to_html(false)])
	_check(UIKit.BG.to_html(false) == "0b0e14", "背景主色不受色盲模式影响")

	UIKit.set_scale(1.0)
	_check(UIKit.fs(14) == 14, "字号 1.0× → 14")
	UIKit.set_scale(1.3)
	_check(UIKit.fs(14) == 18, "字号 1.3× → 18")
	UIKit.set_scale(9.0)
	_check(UIKit.SIZE_SCALE <= 1.6, "字号缩放被钳制在 1.6 以内（%.2f）" % UIKit.SIZE_SCALE)
	UIKit.set_scale(1.0)
	UIKit.apply_palette(false)
	_check(UIKit.OK.to_html(false) == "4fe38a", "关闭色盲后 OK 色还原")

# ---------------- 5) 存档槽位 ----------------

func _test_slots() -> void:
	print("\n---- 5) 存档槽位 ----")
	_check(GameState.SLOT_COUNT == 3, "槽位数量 = 3")
	_check(GameState.slot_path(1) == GameState.SAVE_PATH, "槽 1 沿用历史路径")
	_check(GameState.slot_path(2) != GameState.slot_path(3), "槽 2 / 槽 3 路径不同")

	# 只动槽 2：写入可识别的值
	GameState.use_slot(2, true)
	_check(GameState.save_slot == 2, "已切到槽 2")
	_check(GameState.current_path() == GameState.slot_path(2), "current_path 指向槽 2")
	_check(SteamService.cloud_name() == "scrap_engine_save_slot2.json", "云文件名跟随槽位（%s）" % SteamService.cloud_name())

	GameState.reset_new_game()
	GameState.add_credits(4242)
	GameState.add_item("mat_mech_t1_wire", 7)
	GameState.save_game()

	var sum2: Dictionary = GameState.slot_summary(2)
	_check(bool(sum2.get("exists", false)), "槽 2 存档文件已写出")
	_check(int(sum2.get("credits", 0)) == GameState.START_CREDITS + 4242, "槽 2 摘要信用点 = %d" % int(sum2.get("credits", 0)))
	_check(int(sum2.get("items", 0)) == GameState.total_items(), "槽 2 摘要物品数 = %d" % int(sum2.get("items", 0)))
	_check(bool(sum2.get("current", false)), "槽 2 标记为当前槽位")

	# 槽 3 独立、空槽位摘要安全返回
	var sum3: Dictionary = GameState.slot_summary(3)
	_check(typeof(sum3) == TYPE_DICTIONARY, "空槽位摘要返回字典")
	GameState.delete_slot(3)
	_check(not GameState.slot_exists(3), "删除空槽位后仍不存在")

	# 切回槽 1 不应破坏槽 2 文件
	GameState.use_slot(1, true)
	_check(GameState.save_slot == 1, "已切回槽 1")
	_check(GameState.slot_exists(2), "切走后槽 2 文件仍在")
	_check(SteamService.cloud_name() == "scrap_engine_save.json", "槽 1 云文件名 = scrap_engine_save.json")

	# 清理槽 2
	GameState.delete_slot(2)
	_check(not GameState.slot_exists(2), "已删除槽 2")

	# 恢复用户原本的槽位与存档
	GameState.use_slot(_start_slot, true)

# ---------------- 收尾 ----------------

func _restore() -> void:
	Settings.reset_defaults()
	Settings.set_slot(_start_slot)
	GameState.use_slot(_start_slot, true)

# ---------------- 断言 ----------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
