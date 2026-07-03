# 实验关停状态清单

Status: historical inventory

执行备注：2026-07-03 已按 `docs/experiment_shutdown_delete_record_20260703.md` 删除关停实验。本文件保留为删除前盘点记录，不代表当前数据库状态。

盘点时间：2026-07-02  
数据来源：`moodly_server` 当前数据库 `experiments` / `experiment_assignments` / `experiment_exposures` / `experiment_overrides`，并交叉检查 `moodly_server` 与 `moodly-chat-svr` 代码引用。

## 结论摘要

当前非 `running` 实验共 33 个，状态包含 `draft`、`paused`、`stopped`。

删除风险说明：`experiment_assignments`、`experiment_exposures`、`experiment_overrides` 对 `experiments.experiment_key` 是级联删除关系。物理删除实验定义会同时删除历史分组、曝光和 override 数据。

建议优先级：

1. 可直接删除：没有历史数据、没有代码引用的误写或空实验。
2. 可归档：客户端或服务端已不消费，但还有历史分析数据。
3. 先别删：代码默认配置或运行时代码仍引用，删除前需要先改代码或配置。

## 可直接删除候选

| 实验 key | 状态 | domain | assignment | exposure | override | 建议 |
|---|---:|---|---:|---:|---:|---|
| `chat_inner_os_price_1_8_1_202606` | draft | chat | 0 | 0 | 0 | 可直接删除，疑似误写 key |

## 建议归档，不建议直接物理删除

这些实验已经不应继续下发，但仍有历史数据。建议先改为 `archived` 或保持关停状态，等确认报表不再需要后再考虑物理删除。

| 实验 key | 状态 | domain | assignment | exposure | override | 备注 |
|---|---:|---|---:|---:|---:|---|
| `candy_wallet_entry_non_vip_visibility_1_1_2` | paused | billing | 32329 | 669 | 0 | 客户端已移除消费代码，有现成 `archive_candy_wallet_entry_non_vip_visibility_experiment.sql` |
| `android_vip_catalog_copy_year_anchor_v1` | paused | billing | 737 | 0 | 0 | Android 会员页历史实验 |
| `android_vip_price_catalog_20260625` | paused | billing | 735 | 2632 | 0 | Android 旧价格实验 |
| `android_vip_price_catalog_20260625_v2` | paused | billing | 619 | 3033 | 0 | 已判负下线，服务端不再消费 Android 价格实验 key |
| `ios_vip_price_catalog_20260625` | paused | billing | 176 | 715 | 0 | iOS 旧价格实验 |
| `chat_inner_os_price_1_0_8_1_202606` | draft | chat | 34 | 1264 | 0 | 旧内心 OS 价格实验，已有曝光历史 |
| `chat_message_candy_cost_new_users_20260630` | stopped | chat | 500 | 0 | 0 | 已被 `chat_message_candy_cost_new_users_20260701` 替代 |

## 先别删，代码仍有引用

这些实验当前不是 `running`，但代码或默认配置仍引用。删除前需要先改代码、环境变量或确认运行时不会再解析。

| 实验 key | 状态 | domain | assignment | exposure | override | 引用位置 / 原因 |
|---|---:|---|---:|---:|---:|---|
| `candy_first_6_recharge_bonus_100pct_20260629` | stopped | billing | 907 | 2815 | 0 | `moodly_server/src/modules/candy/candy.service.ts` 仍先尝试 resolve 该 key，再 fallback |
| `ios_vip_price_catalog_20260625_v2` | paused | billing | 771 | 4657 | 0 | `moodly_server/src/modules/vip/vip.service.ts` 仍作为 iOS VIP catalog experiment key |
| `chat_dynamic_decide_recent_context_registered_user_20260609` | paused | chat | 49 | 1017 | 0 | `moodly-chat-svr/src/config/env.ts` 默认值仍指向该 key |
| `chat_dynamic_reply_shape_zero_example_v3_20260622` | stopped | chat | 8097 | 469227 | 1 | `moodly-chat-svr/src/config/env.ts` 默认值仍指向该 key |
| `chat_inner_os_prompt_v2_examples_20260628` | paused | chat | 861 | 0 | 0 | `moodly-chat-svr/src/config/env.ts` 默认值仍指向该 key |

## 历史 chat 实验

这些实验都已非 `running`，且有历史 assignment 或 exposure。建议作为历史分析数据保留；如需清理，先导出相关分组和曝光数据。

| 实验 key | 状态 | assignment | exposure | override |
|---|---:|---:|---:|---:|
| `chat_basic_persona_prompt_5050_20260518` | paused | 113 | 1559 | 0 |
| `chat_basic_persona_prompt_5050_v2_20260519` | paused | 207 | 1567 | 0 |
| `chat_basic_persona_prompt_5050_v3_20260519` | paused | 297 | 3011 | 0 |
| `chat_basic_persona_prompt_5050_v4_20260520` | paused | 4253 | 77240 | 0 |
| `chat_character_tone_prompt_v2_20260518` | paused | 0 | 4912 | 0 |
| `chat_cold_persona_prompt_5050_20260518` | paused | 280 | 4082 | 0 |
| `chat_cold_persona_prompt_5050_v2_20260520` | paused | 2683 | 67857 | 0 |
| `chat_dynamic_reply_shape_bubble_cap_minus1_202606` | paused | 61 | 918 | 0 |
| `chat_dynamic_reply_shape_bubble_cap_minus1_v2_20260618` | paused | 2744 | 91620 | 0 |
| `chat_generate_model_deepseek_pro_flash_202605` | paused | 580 | 13289 | 0 |
| `chat_generate_reply_prompt_3arm_20260515` | paused | 1169 | 40027 | 0 |
| `chat_generate_reply_prompt_v2_20260514` | paused | 674 | 12080 | 0 |
| `chat_generate_reply_sticker_delivery_202605` | paused | 170 | 3625 | 0 |
| `chat_personality_recipe_inject_20260517` | paused | 107 | 1609 | 0 |
| `chat_dynamic_reply_shape_zero_example_v4_new_users_20260629` | stopped | 30 | 183 | 0 |
| `chat_generate_reply_dynamic_prompt_ab_20260624` | stopped | 1716 | 55536 | 0 |
| `chat_generate_reply_dynamic_prompt_three_arm_20260627` | stopped | 1602 | 43229 | 0 |

## 其他 draft 实验

这些是非运行状态的 billing draft，但已有 assignment 或 override，不建议不看历史就删。

| 实验 key | 状态 | domain | assignment | exposure | override | 备注 |
|---|---:|---|---:|---:|---:|---|
| `android_vip_plan_catalog_v1` | draft | billing | 4988 | 0 | 1 | 旧 Android 商品目录实验 |
| `android_vip_price_new_user_v2` | draft | billing | 2924 | 0 | 0 | 旧 Android 新用户价格实验 |
| `android_vip_price_new_user_v3` | draft | billing | 1000 | 0 | 0 | 旧 Android 新用户价格实验 |

## 状态冲突

| 实验 key | 数据库状态 | 文档口径 | 建议 |
|---|---:|---|---|
| `android_candy_catalog_18_38_88_128_20260613` | running | 文档写已关闭 | 先核实是否应下线。如果确实已关闭，需更新数据库状态；如果仍运行，需修正文档 |
| `ios_vip_price_catalog_20260625_v2` | paused | 部分文档写 running，代码仍引用 | 先确认 iOS 价格实验是否要恢复；不恢复则应改代码和文档，再归档 |

## 建议下一步

1. 直接删除 `chat_inner_os_price_1_8_1_202606`。
2. 对 `candy_wallet_entry_non_vip_visibility_1_1_2` 执行归档脚本，而不是物理删除。
3. 先处理仍被代码引用的 5 个 key，再讨论删除。
4. 核实 `android_candy_catalog_18_38_88_128_20260613` 和 `ios_vip_price_catalog_20260625_v2` 的数据库状态与文档状态冲突。
