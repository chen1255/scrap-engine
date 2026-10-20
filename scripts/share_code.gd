class_name ShareCode
extends RefCounted
## 存档分享码：把一份完整存档快照编码成一段可复制、可粘贴的纯文本，在另一台机器 /
## 另一个槽位还原同样的进度（阶段九）。
##
## 格式：`SCRAP9:<存档版本>:<校验和>:<base64>`
##   - payload  = JSON.stringify(存档字典, "", false)  紧凑、无缩进；
##   - 压缩     = gzip（存档 JSON 约 2~4 KB → 约 0.5~1 KB）；
##   - 校验和   = **压缩载荷**的 sha256 前 16 位，防手改 / 复制截断；
##   - 前缀     = SCRAP9（与本版本对应，便于以后区分格式）。
##
## 这里只有静态函数：不新增 autoload、不改 project.godot，由设置页按需调用。

## 分享码前缀（本阶段格式标识）
const PREFIX := "SCRAP9"
## 校验和取 sha256 十六进制的前 N 位
const SUM_LEN := 16
## 解压上限：正常存档远小于此值，超过即视为损坏（防解压炸弹 / 误贴大段文本）
const MAX_PLAIN_BYTES := 1 << 20

# ---------------- 编码 ----------------

## 把一份存档字典编码成分享码。版本号取自字典的 version 字段（缺省用当前存档版本）。
static func encode(save: Dictionary) -> String:
	var version := int(save.get("version", GameState.SAVE_VERSION))
	var payload := JSON.stringify(save, "", false)
	var packed := payload.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return "%s:%d:%s:%s" % [PREFIX, version, checksum(packed), Marshalls.raw_to_base64(packed)]

## 校验和：压缩载荷的 sha256 十六进制前 16 位。
## 取「压缩后」的字节而不是解压后的文本，是为了让解码能**先校验、后解压**——
## 被截断 / 被手改的码在文本层就被拒，既不会把垃圾数据扔给解压器，也不会写坏任何存档。
static func checksum(packed: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(packed)
	return ctx.finish().hex_encode().substr(0, SUM_LEN)

# ---------------- 解码 ----------------

## 解码分享码。任何一步失败都返回 { ok: false, reason }，绝不半写入（调用方据此拒绝导入）。
## 成功时返回 { ok: true, reason: "", save: 存档字典, version: 存档版本 }。
static func decode(code: String) -> Dictionary:
	# 允许聊天工具 / 邮件折行粘贴：先剔除全部空白再解析
	var text := _strip_space(code)
	if text == "" or not text.begins_with(PREFIX + ":"):
		return _fail("不是有效的分享码")

	var parts := text.split(":")
	if parts.size() != 4:
		return _fail("分享码已损坏（无法解压）")

	var ver_txt := parts[1]
	if not ver_txt.is_valid_int():
		return _fail("分享码已损坏（无法解压）")
	var ver := ver_txt.to_int()
	if ver > GameState.SAVE_VERSION:
		return _fail("分享码来自更高版本（v%d），请先更新游戏" % ver)

	if parts[2].length() != SUM_LEN:
		return _fail("分享码校验不通过（内容可能被改动或被截断）")

	# 先做纯文本层校验（字符集 + gzip 魔数 + 校验和）：粘贴进来的垃圾文本与改写过的码
	# 在这里就被挡住，不必把明显不合法的数据扔给解压器。
	if not _is_base64(parts[3]):
		return _fail("分享码已损坏（无法解压）")
	var packed := Marshalls.base64_to_raw(parts[3])
	if packed.size() < 2 or packed[0] != 0x1f or packed[1] != 0x8b:
		return _fail("分享码已损坏（无法解压）")
	if checksum(packed) != parts[2]:
		return _fail("分享码校验不通过（内容可能被改动或被截断）")

	var plain := packed.decompress_dynamic(MAX_PLAIN_BYTES, FileAccess.COMPRESSION_GZIP)
	if plain.is_empty() or plain.size() > MAX_PLAIN_BYTES:
		return _fail("分享码已损坏（无法解压）")

	var payload := plain.get_string_from_utf8()
	var d: Variant = JSON.parse_string(payload)
	if typeof(d) != TYPE_DICTIONARY:
		return _fail("分享码内容无效")

	var save: Dictionary = d
	var bad := _check_fields(save)
	if bad != "":
		return _fail(bad)

	# 头部版本与内容版本都不得高于当前版本（头部可手改，内容才是权威）
	var save_ver := int(save.get("version", ver))
	if save_ver > GameState.SAVE_VERSION:
		return _fail("分享码来自更高版本（v%d），请先更新游戏" % save_ver)
	return { "ok": true, "reason": "", "save": save, "version": save_ver }

# ---------------- 摘要 ----------------

## 一行摘要（供设置页展示）：信用点 · 体力 · 物品总数 · 图鉴进度。
static func describe(save: Dictionary) -> String:
	var items := 0
	var inv: Variant = save.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		for id in (inv as Dictionary):
			var v: Variant = (inv as Dictionary)[id]
			items += int(v.get("n", 0)) if typeof(v) == TYPE_DICTIONARY else int(v)
	var found := 0
	var cx: Variant = save.get("codex", {})
	if typeof(cx) == TYPE_DICTIONARY:
		found = (cx as Dictionary).size()
	return "₡%d · ⚡%d · 物品 %d · 图鉴 %d/%d" % [
		int(save.get("credits", 0)), int(save.get("energy", 0)),
		items, found, GameData.item_order.size(),
	]

# ---------------- 内部 ----------------

## 结构校验：必填字段必须存在且类型正确，可选字段若存在则类型必须正确。
static func _check_fields(save: Dictionary) -> String:
	if not _is_num(save.get("credits", null)) or not _is_num(save.get("energy", null)):
		return "分享码字段不完整"
	if typeof(save.get("inventory", null)) != TYPE_DICTIONARY:
		return "分享码字段不完整"

	for k in ["codex", "achievements", "achievement_rewards", "goals", "tutorial", "pity", "stats"]:
		if save.has(k) and typeof(save[k]) != TYPE_DICTIONARY:
			return "分享码字段不完整"
	if save.has("calibrator_level") and not _is_num(save["calibrator_level"]):
		return "分享码字段不完整"
	if save.has("version") and not _is_num(save["version"]):
		return "分享码字段不完整"

	# 库存条目：{ n, cs } 结构，或旧存档的「只有数量」写法
	var inv: Dictionary = save["inventory"]
	for id in inv:
		var v: Variant = inv[id]
		if typeof(v) == TYPE_DICTIONARY:
			if not _is_num((v as Dictionary).get("n", null)):
				return "分享码字段不完整"
			if (v as Dictionary).has("cs") and not _is_num((v as Dictionary)["cs"]):
				return "分享码字段不完整"
		elif not _is_num(v):
			return "分享码字段不完整"
	return ""

static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

## base64 标准字母表校验：先把「粘贴进来的普通文字」挡在这里，避免解压器报错刷屏。
static func _is_base64(s: String) -> bool:
	if s.length() < 4:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or (c >= 48 and c <= 57) or c == 43 or c == 47 or c == 61
		if not ok:
			return false
	return true

## 剔除全部空白与换行（分享码的字符集里不含空白，剔除是安全的）。
static func _strip_space(s: String) -> String:
	var out := ""
	for ch in s:
		if ch == " " or ch == "\n" or ch == "\r" or ch == "\t":
			continue
		out += ch
	return out

static func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason, "save": {}, "version": 0 }
