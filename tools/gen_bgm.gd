extends Node
## 离线 BGM / 环境音合成工具（无需渲染设备，可直接 --headless 运行）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tools/gen_bgm.tscn
##
## 复用 tools/gen_sfx.gd 的合成原语（_buf / _note / _write_wav），并对 BGM 开启「尾音回卷」：
## 越过缓冲末尾的音符尾音折回开头，于是整段信号严格以 dur 为周期 —— 循环接缝听不出断续。
## 运行期由 Bgm 单例载入，并在内存里把 AudioStreamWAV 置为 LOOP_FORWARD。
##
## 固定随机种子，重跑产物完全一致；4 段合计约 7MB。美术后期想换真实音乐，用同名 .wav 覆盖即可。

const Synth := preload("res://tools/gen_sfx.gd")
const OUT_DIR := "res://assets/audio"
const SR := 44100.0

func _ready() -> void:
	await get_tree().process_frame
	seed(20261019)

	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		print("[失败] 无法创建目录 %s（错误 %d）" % [abs_dir, mk])
		get_tree().quit(1)
		return

	var ok := 0
	var recipes: Array = _recipes()
	for r in recipes:
		var nm := str(r["name"])
		var buf: PackedFloat32Array = r["buf"]
		if Synth._write_wav(abs_dir.path_join(nm + ".wav"), buf):
			ok += 1
			print("  [ok] %s.wav (%.1f 秒)" % [nm, float(buf.size()) / SR])
		else:
			print("  [失败] %s.wav" % nm)

	print("BGM 合成完成：%d / %d -> %s" % [ok, recipes.size(), OUT_DIR])
	get_tree().quit(0 if ok == recipes.size() else 1)

# ---------------- 曲目清单 ----------------

func _recipes() -> Array:
	return [
		{ "name": "bgm_lobby",    "buf": _bgm_lobby() },
		{ "name": "bgm_workshop", "buf": _bgm_workshop() },
		{ "name": "bgm_exchange", "buf": _bgm_exchange() },
		{ "name": "amb_hangar",   "buf": _amb_hangar() },
	]

# ---------------- 合成配方 ----------------

## 大厅：缓慢的大调和弦铺底 + 稀疏铃音。用于黑市 / 仓库 / 图鉴 / 设置 / Steam 页。
func _bgm_lobby() -> PackedFloat32Array:
	var dur := 24.0
	var b: PackedFloat32Array = Synth._buf(dur)
	var chords := [
		[220.00, 261.63, 329.63],   # Am
		[174.61, 220.00, 261.63],   # F
		[261.63, 329.63, 392.00],   # C
		[196.00, 246.94, 293.66],   # G
	]
	var seg := dur / float(chords.size())
	for i in range(chords.size()):
		var t0 := float(i) * seg
		var ch: Array = chords[i]
		var root := float(ch[0])
		Synth._note(b, t0, seg, root * 0.5, 0.16, "sine", 1.2, 1.0, 0.0, true)
		for f in ch:
			Synth._note(b, t0, seg, float(f), 0.10, "sine", 1.0, 1.0, 0.0, true)
			Synth._note(b, t0, seg, float(f) * 2.0, 0.028, "tri", 1.4, 1.0, 0.0, true)
		Synth._note(b, t0 + seg * 0.45, 3.2, root * 4.0, 0.055, "sine", 0.01, 3.2, 0.0, true)
		Synth._note(b, t0 + seg * 0.80, 2.6, root * 6.0, 0.032, "sine", 0.01, 3.4, 0.0, true)
	return b

## 工坊：机械低音脉冲 + 金属 tick + 气噪。用于拆解台 / 熔炉 / 维修台。
func _bgm_workshop() -> PackedFloat32Array:
	var dur := 24.0
	var b: PackedFloat32Array = Synth._buf(dur)
	var step := 0.75                       # 32 步
	var bass := [110.0, 110.0, 146.83, 110.0, 98.0, 98.0, 130.81, 98.0]
	var steps := int(dur / step)
	for s in range(steps):
		var t := float(s) * step
		var f := float(bass[s % bass.size()])
		Synth._note(b, t, step * 0.95, f, 0.17, "tri", 0.01, 2.2)
		if s % 2 == 0:
			Synth._note(b, t, 0.06, 1180.0 + float(s % 4) * 90.0, 0.05, "square", 0.0008, 20.0)
		if s % 8 == 4:
			Synth._note(b, t, 0.22, 0.0, 0.05, "noise", 0.006, 8.0, 0.0, true)
	Synth._note(b, 0.0, dur, 55.0, 0.10, "tri", 1.6, 1.0, 0.0, true)
	Synth._note(b, 0.0, dur, 82.41, 0.05, "sine", 1.8, 1.0, 0.0, true)
	return b

## 交易所：十六分音符方波琶音 + 周期性噪声上扬。略带压迫感。
func _bgm_exchange() -> PackedFloat32Array:
	var dur := 16.0
	var b: PackedFloat32Array = Synth._buf(dur)
	var step := 0.25
	var seq := [220.0, 261.63, 329.63, 392.0, 329.63, 261.63, 246.94, 293.66]
	var steps := int(dur / step)
	for s in range(steps):
		var t := float(s) * step
		var f := float(seq[s % seq.size()])
		Synth._note(b, t, 0.22, f, 0.062, "square", 0.002, 9.0)
		if s % 4 == 0:
			Synth._note(b, t, 0.5, f * 0.5, 0.13, "tri", 0.01, 3.0)
	for k in range(4):
		Synth._note(b, float(k) * 4.0, 1.2, 200.0, 0.05, "noise", 0.05, 3.0, 4000.0, true)
	Synth._note(b, 0.0, dur, 65.41, 0.08, "sine", 1.5, 1.0, 0.0, true)
	return b

## 环境底噪：两路极低频拍频 + 疏落机械脉冲，常驻铺底（音量很低）。
func _amb_hangar() -> PackedFloat32Array:
	var dur := 16.0
	var b: PackedFloat32Array = Synth._buf(dur)
	Synth._note(b, 0.0, dur, 41.2, 0.34, "sine", 2.0, 1.0, 0.0, true)
	Synth._note(b, 0.0, dur, 41.55, 0.30, "sine", 2.0, 1.0, 0.0, true)
	Synth._note(b, 0.0, dur, 82.41, 0.10, "sine", 2.4, 1.0, 0.0, true)
	Synth._note(b, 0.0, dur, 123.5, 0.035, "tri", 2.6, 1.0, 0.0, true)
	for k in range(4):
		Synth._note(b, float(k) * 4.0 + 1.5, 0.9, 0.0, 0.03, "noise", 0.2, 3.0, 0.0, true)
	return b
