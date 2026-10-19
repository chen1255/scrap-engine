extends Node
## 共享规则引擎：把「达成条件」抽象成数据驱动的小规则。
## 成就（Achievements）与目标（Objectives）共用同一套语义，避免两处判定漂移。
##
## 规则类型（rule.type）：
##   stat              —— GameState.stats[key] >= at_least
##   credits           —— GameState.credits >= at_least
##   codex_count       —— 图鉴已收录 >= found
##   codex_family_all  —— 某族系图鉴全收齐
##   own_kind_tier     —— 持有某 kind / 阶位的数量 >= count
##   calibrator_max    —— 概率校准器满级
##   calibrator_level  —— 概率校准器等级 >= level
##
## meets / progress 对未知 type 一律返回「未达成 / [0, 0]」，旧档缺字段时安全。

## 条件是否已达成
func meets(rule: Dictionary) -> bool:
	match str(rule.get("type", "")):
		"stat":
			return int(GameState.stats.get(str(rule.get("key", "")), 0)) >= int(rule.get("at_least", 1))
		"credits":
			return GameState.credits >= int(rule.get("at_least", 0))
		"codex_count":
			return int(GameState.codex_progress()[0]) >= int(rule.get("found", 0))
		"codex_family_all":
			var fp: Array = GameState.codex_progress_of(str(rule.get("family", "")))
			return int(fp[1]) > 0 and int(fp[0]) >= int(fp[1])
		"own_kind_tier":
			return count_kind_tier(str(rule.get("kind", "")), int(rule.get("tier", 0))) >= int(rule.get("count", 1))
		"calibrator_max":
			return CraftSystem.calibrator_maxed()
		"calibrator_level":
			return GameState.calibrator_level >= int(rule.get("level", 1))
	return false

## 当前进度：[当前值, 目标值]，供 UI 进度条显示
func progress(rule: Dictionary) -> Array:
	match str(rule.get("type", "")):
		"stat":
			var t := int(rule.get("at_least", 1))
			return [mini(int(GameState.stats.get(str(rule.get("key", "")), 0)), t), t]
		"credits":
			var t2 := int(rule.get("at_least", 0))
			return [mini(GameState.credits, t2), t2]
		"codex_count":
			return [int(GameState.codex_progress()[0]), int(rule.get("found", 0))]
		"codex_family_all":
			var fp: Array = GameState.codex_progress_of(str(rule.get("family", "")))
			return [int(fp[0]), int(fp[1])]
		"own_kind_tier":
			var c := int(rule.get("count", 1))
			return [mini(count_kind_tier(str(rule.get("kind", "")), int(rule.get("tier", 0))), c), c]
		"calibrator_max":
			var mx := int(GameData.calibrator.get("max_level", 5))
			return [mini(GameState.calibrator_level, mx), mx]
		"calibrator_level":
			var lv := int(rule.get("level", 1))
			return [mini(GameState.calibrator_level, lv), lv]
	return [0, 0]

## 持有某 kind / 阶位的物品总数
func count_kind_tier(kind: String, tier: int) -> int:
	var n := 0
	for id in GameData.items_matching({ "kind": kind, "tier": tier }):
		n += GameState.count_of(id)
	return n
