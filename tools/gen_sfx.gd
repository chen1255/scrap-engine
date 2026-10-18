extends Node
## 离线音效合成工具（无需渲染设备，可直接 --headless 运行）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tools/gen_sfx.tscn
##
## 用纯代码把一批短音效合成为 16-bit / 44.1kHz / 单声道的标准 WAV，落盘到 assets/audio/。
## 运行游戏时由 Sfx 自动加载。零外部依赖、可离线、可版本化，没有版权问题。
## 美术后期想换成真实录音，只要用同名 .wav 覆盖即可，代码不用动。
##
## 波形随机（噪声）用固定种子播种，保证每次运行产出的文件完全一致，避免无意义的 git 变更。

const OUT_DIR := "res://assets/audio"
const SR := 44100.0

func _ready() -> void:
	await get_tree().process_frame
	seed(20261018)

	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		print("[失败] 无法创建目录 %s（错误 %d）" % [abs_dir, mk])
		get_tree().quit(1)
		return

	var ok := 0
	var recipes: Array = _recipes()
	for r in recipes:
		var name := str(r["name"])
		if _write_wav(abs_dir.path_join(name + ".wav"), r["buf"]):
			ok += 1
			print("  [ok] %s.wav" % name)
		else:
			print("  [失败] %s.wav" % name)

	print("音效合成完成：%d / %d -> %s" % [ok, recipes.size(), OUT_DIR])
	get_tree().quit(0 if ok == recipes.size() else 1)

# ---------------- 音效清单 ----------------

func _recipes() -> Array:
	return [
		{ "name": "click",            "buf": _sfx_click() },
		{ "name": "open",             "buf": _sfx_open() },
		{ "name": "flip",             "buf": _sfx_flip() },
		{ "name": "reveal_t1",        "buf": _sfx_reveal(1) },
		{ "name": "reveal_t2",        "buf": _sfx_reveal(2) },
		{ "name": "reveal_t3",        "buf": _sfx_reveal(3) },
		{ "name": "reveal_t4",        "buf": _sfx_reveal(4) },
		{ "name": "reveal_t5",        "buf": _sfx_reveal(5) },
		{ "name": "promote_spin",     "buf": _sfx_spin() },
		{ "name": "promote_success",  "buf": _sfx_success() },
		{ "name": "promote_hold",     "buf": _sfx_hold() },
		{ "name": "promote_damage",   "buf": _sfx_damage() },
		{ "name": "promote_breakdown","buf": _sfx_breakdown() },
		{ "name": "disassemble",      "buf": _sfx_disassemble() },
		{ "name": "trade",            "buf": _sfx_trade() },
		{ "name": "error",            "buf": _sfx_error() },
	]

# ---------------- 合成配方 ----------------

## UI 点击：极短的金属脆响
func _sfx_click() -> PackedFloat32Array:
	var b := _buf(0.05)
	_note(b, 0.0, 0.045, 1000.0, 0.34, "sine", 0.0008, 16.0, 720.0)
	_note(b, 0.0, 0.018, 0.0, 0.12, "noise", 0.0008, 24.0)
	return b

## 开箱启动：机械开盖，低频下坠 + 两段噪声
func _sfx_open() -> PackedFloat32Array:
	var b := _buf(0.32)
	_note(b, 0.0, 0.28, 340.0, 0.30, "saw", 0.004, 3.0, 90.0)
	_note(b, 0.02, 0.10, 0.0, 0.18, "noise", 0.004, 9.0)
	_note(b, 0.15, 0.12, 0.0, 0.12, "noise", 0.004, 12.0)
	return b

## 翻牌：短促上扬方波
func _sfx_flip() -> PackedFloat32Array:
	var b := _buf(0.07)
	_note(b, 0.0, 0.055, 700.0, 0.24, "square", 0.0008, 15.0, 1150.0)
	return b

## 揭晓：阶次越高，琶音越长越亮
func _sfx_reveal(tier: int) -> PackedFloat32Array:
	var seq_by_tier := {
		1: [330.0],
		2: [440.0],
		3: [523.25, 659.25],
		4: [587.33, 783.99, 987.77],
		5: [659.25, 880.0, 1108.73, 1318.51],
	}
	var seq: Array = seq_by_tier[tier]
	var b := _buf(0.34 + 0.05 * float(tier))
	var amp := 0.24 + 0.045 * float(tier)
	for i in range(seq.size()):
		var f := float(seq[i])
		var at := float(i) * 0.055
		_note(b, at, 0.26, f, amp, "sine", 0.003, 4.5)
		_note(b, at, 0.26, f * 2.0, amp * 0.38, "sine", 0.003, 6.5)
	if tier >= 4:
		_note(b, 0.0, 0.30, 0.0, 0.09, "noise", 0.02, 6.0)
	return b

## 抽签滚动：密集的短 tick
func _sfx_spin() -> PackedFloat32Array:
	var b := _buf(0.06)
	_note(b, 0.0, 0.05, 900.0, 0.22, "square", 0.0008, 18.0, 1080.0)
	return b

## 晋升成功：上扬大三和弦琶音 + 微亮噪声
func _sfx_success() -> PackedFloat32Array:
	var b := _buf(0.75)
	var seq := [523.25, 659.25, 783.99, 1046.5]
	for i in range(seq.size()):
		var f := float(seq[i])
		_note(b, float(i) * 0.055, 0.52, f, 0.26, "sine", 0.003, 3.4)
		_note(b, float(i) * 0.055, 0.52, f * 2.0, 0.09, "sine", 0.003, 5.5)
	_note(b, 0.0, 0.34, 0.0, 0.06, "noise", 0.02, 7.0)
	return b

## 稳定：同音重复，克制的中性反馈
func _sfx_hold() -> PackedFloat32Array:
	var b := _buf(0.5)
	_note(b, 0.0, 0.40, 440.0, 0.24, "tri", 0.004, 4.2)
	_note(b, 0.09, 0.40, 440.0, 0.20, "tri", 0.004, 4.2)
	return b

## 损伤：下坠锯齿 + 噪声
func _sfx_damage() -> PackedFloat32Array:
	var b := _buf(0.6)
	_note(b, 0.0, 0.50, 440.0, 0.26, "saw", 0.004, 4.0, 300.0)
	_note(b, 0.04, 0.20, 0.0, 0.12, "noise", 0.004, 9.0)
	return b

## 崩解：爆裂噪声 + 深下坠
func _sfx_breakdown() -> PackedFloat32Array:
	var b := _buf(0.85)
	_note(b, 0.0, 0.62, 0.0, 0.34, "noise", 0.0008, 5.0)
	_note(b, 0.0, 0.58, 220.0, 0.30, "saw", 0.002, 4.0, 55.0)
	return b

## 拆解：上行锯齿 + 噪声，热解剥离感
func _sfx_disassemble() -> PackedFloat32Array:
	var b := _buf(0.5)
	_note(b, 0.0, 0.42, 180.0, 0.28, "saw", 0.003, 4.5, 520.0)
	_note(b, 0.05, 0.35, 0.0, 0.16, "noise", 0.006, 7.0)
	return b

## 成交：两下上行方波，收银感
func _sfx_trade() -> PackedFloat32Array:
	var b := _buf(0.3)
	_note(b, 0.0, 0.12, 880.0, 0.26, "square", 0.0008, 11.0)
	_note(b, 0.09, 0.16, 1320.0, 0.24, "square", 0.0008, 9.0)
	return b

## 失败 / 不足：低频拍频嗡鸣
func _sfx_error() -> PackedFloat32Array:
	var b := _buf(0.32)
	_note(b, 0.0, 0.24, 160.0, 0.28, "square", 0.002, 6.0)
	_note(b, 0.0, 0.24, 158.0, 0.20, "square", 0.002, 6.0)
	return b

# ---------------- 合成原语 ----------------

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * SR))
	b.fill(0.0)
	return b

## 往缓冲里叠加一个音符：指数衰减包络 + 可选线性扫频
func _note(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp := 0.5,
		wave := "sine", attack := 0.004, decay := 5.0, pitch_end := 0.0) -> void:
	var n := buf.size()
	var i0 := int(start * SR)
	var ln := maxi(1, int(dur * SR))
	for k in range(ln):
		var i := i0 + k
		if i < 0 or i >= n:
			continue
		var t := float(k) / SR
		var env := minf(1.0, t / maxf(0.0005, attack)) * exp(-decay * t / maxf(0.0005, dur))
		var f := freq if pitch_end <= 0.0 else lerpf(freq, pitch_end, float(k) / float(ln))
		var ph := TAU * f * t
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if sin(ph) >= 0.0 else -1.0
			"tri":
				s = asin(sin(ph)) * 0.6366198
			"saw":
				s = fposmod(f * t, 1.0) * 2.0 - 1.0
			"noise":
				s = randf() * 2.0 - 1.0
			_:
				s = sin(ph)
		buf[i] += s * amp * env

# ---------------- 写出 WAV ----------------

## 归一化并写成 16-bit PCM 单声道 WAV
func _write_wav(path: String, buf: PackedFloat32Array) -> bool:
	var mx := 0.0
	for v in buf:
		mx = maxf(mx, absf(v))
	if mx < 0.0001:
		mx = 1.0
	var scale := 0.92 / mx

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("  [失败] 无法写入 %s（错误 %d）" % [path, FileAccess.get_open_error()])
		return false

	var data_bytes := buf.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_bytes)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)                       # fmt 块长度
	f.store_16(1)                        # PCM
	f.store_16(1)                        # 单声道
	f.store_32(int(SR))                  # 采样率
	f.store_32(int(SR) * 2)              # 字节率
	f.store_16(2)                        # 块对齐
	f.store_16(16)                       # 位深
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_bytes)
	for v in buf:
		f.store_16(int(clampf(v * scale, -1.0, 1.0) * 32767.0))
	f.close()
	return true
