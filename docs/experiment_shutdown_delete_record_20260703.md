# 关停实验删除执行记录

Status: implementation record

执行时间：2026-07-03 18:06:35 CST  
执行人：Codex  
关联方案：`docs/experiment_shutdown_cleanup_plan_20260703.md`  
删除前快照：`docs/experiment_shutdown_delete_snapshot_20260703.json`

恢复备注：2026-07-03 18:18 CST 按要求恢复 `chat_inner_os_prompt_v2_examples_20260628` 实验定义，并保持 `paused / client_visible=false / server_visible=false`。恢复后当前库为 10 个 `running` 实验 + 1 个 `paused` 实验。

追加删除：2026-07-03 18:22 CST 复查 `chat_message_candy_cost_new_users_20260701` 已为 `paused` 且 `ends_at=2026-07-03T10:19:40.270Z`，按要求删除该实验定义。删除前快照保存为 `docs/experiment_deleted_chat_message_candy_cost_20260701_snapshot.json`。删除后当前库为 9 个 `running` 实验 + 1 个 `paused` 实验。

追加删除：2026-07-03 18:25 CST 按要求暂停并删除 `chat_inner_os_prompt_v2_20260627`，同时删除此前恢复为 paused 的 `chat_inner_os_prompt_v2_examples_20260628`。删除前快照保存为 `docs/experiment_deleted_inner_os_prompt_20260703_snapshot.json`。删除后当前库为 8 个 `running` 实验，无 paused 实验定义。

追加确认：2026-07-03 18:28 CST 复查 `chat_dynamic_reply_shape_zero_example_v5_new_users_20260629` 已在此前批量删除中移除实验定义，当前 `experiments` 表中无该 key；当前库中仅剩 1 个 running reply-shape 实验：`chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703`。该 v5 key 当前历史表残留 assignment 1,855、exposure 0、override 0，不参与线上解析。同步删除 chat-svr 中会重新启动旧 reply-shape v3 三臂实验的 SQL 脚本，并将旧方案文档标记为 historical / deleted，避免误用。

追加代码清理：2026-07-03 18:48 CST 按“主要还有些代码业务也可以跟随实验干净安全删除”的要求，继续清理 `moodly-chat-svr` 中已关停实验的运行时代码、prompt、env 与旧启动脚本。清理口径是保留当前默认 / 对照行为，删除已关停 treatment 分支和重启入口；当前仍 running 的实验没有删除。

本次追加清理包括：

- reply-shape：删除旧 `bubble_cap_minus1`、`rewritten_examples`、`zero_examples` treatment snippet 文件；旧 variant 不再解析为可用实验分支，只保留 current / control 口径。当前 running 的 `chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703` 未删除。
- dynamic decide recent-context：删除 `chat-dynamic-decide-context-experiment` 模块与 `dynamic_decide_no_recent_context` prompt；当前 `chat/dynamic_decide` 固定只消费角色标签与本轮用户消息，不再保留已关停 recent-context 实验分流代码。
- generate-reply dynamic prompt：删除 A/B/三臂动态 prompt 实验模块与 `generate_reply_dynamic_prompt_a/b` prompt；生成回复固定走当前线上 prompt 名。
- message candy cost：删除 `chat-message-candy-cost-experiment` 模块，普通消息 / regenerate 计费固定走当前整数糖果价格策略。因历史表 `chat_message_candy_charge_events=15,227`、`chat_message_candy_charge_states=501` 仍可能需要退款兼容，保留历史 metered refund 读取逻辑，不再保留主动半糖扣费入口。
- inner OS prompt：删除 `chat-inner-os-prompt-experiment` 模块、`inner_os_on_demand_v2` prompt 与 examples prompt；内心 OS 生成固定走 `chat/inner_os_on_demand` / `inner_os_on_demand_v1`。注意：动态注入 / 按需内心 OS 的 running 实验 `chat_inner_os_on_demand_202606` 未删除。
- env / scripts：删除已关停实验的 env key 默认项和旧 launch / force SQL 脚本，避免误配置后把旧实验重新打开。

## 执行范围

本次删除范围为：

1. `experiments.status != 'running'` 的关停实验。
2. 文档已确认关闭、运行时代码已不消费，但数据库仍残留为 `running` 的 Android 糖果档位实验：`android_candy_catalog_18_38_88_128_20260613`。

删除前已先清理仍会影响业务的运行时代码引用：

| 仓库 | 文件 | 处理 |
|---|---|---|
| `moodly_server` | `src/modules/candy/candy.service.ts` | 移除 stopped 的 `candy_first_6_recharge_bonus_100pct_20260629` 解析；保留 2026-06-29 后新用户不走旧首充实验的固定口径 |
| `moodly_server` | `src/modules/vip/vip.service.ts` | iOS VIP 目录不再尝试解析 paused 的 `ios_vip_price_catalog_20260625_v2`，固定走当前目录 |
| `moodly-chat-svr` | `src/config/env.ts` | 将 3 个已关停 chat 实验默认 key 改为空，默认启动不再查旧实验 |
| `moodly_server` / `moodly-chat-svr` | 相关测试 | 将真实已删实验 key 改为固定口径断言或合成测试 key |

## 数据库删除方式

使用 Prisma 事务删除 `experiments` 表中的目标实验定义：

```ts
await prisma.$transaction(async (tx) => {
  await tx.experiment.deleteMany({
    where: { experimentKey: { in: keysFromSnapshot } },
  });
});
```

执行后复查发现，当前数据库中的历史明细行并未被物理级联删除；删除动作实际清理的是 `experiments` 定义行，历史表中仍保留相同 `experiment_key` 的记录。恢复 `chat_inner_os_prompt_v2_examples_20260628` 后，该 key 的 861 条 assignment 重新与实验定义关联。

历史表包括：

- `experiment_assignments`
- `experiment_exposures`
- `experiment_overrides`

## 删除结果

| 项目 | 数量 |
|---|---:|
| 请求删除实验定义 | 36 |
| 实际删除实验定义 | 36 |
| 删除前涉及 assignment | 74,776 |
| 删除前涉及 exposure | 919,355 |
| 删除前涉及 override | 2 |
| 删除后实验定义 remaining 校验 | 0 |
| 2026-07-03 18:18 恢复实验定义 | 1 |

## 已删除实验

| 实验 key | 删除前状态 | domain | assignment | exposure | override |
|---|---:|---|---:|---:|---:|
| `android_vip_plan_catalog_v1` | draft | billing | 4988 | 0 | 1 |
| `android_vip_price_new_user_v2` | draft | billing | 2924 | 0 | 0 |
| `android_vip_price_new_user_v3` | draft | billing | 1000 | 0 | 0 |
| `chat_inner_os_price_1_0_8_1_202606` | draft | chat | 34 | 1264 | 0 |
| `chat_inner_os_price_1_8_1_202606` | draft | chat | 0 | 0 | 0 |
| `android_vip_catalog_copy_year_anchor_v1` | paused | billing | 737 | 0 | 0 |
| `android_vip_price_catalog_20260625` | paused | billing | 735 | 2632 | 0 |
| `android_vip_price_catalog_20260625_v2` | paused | billing | 619 | 3033 | 0 |
| `candy_wallet_entry_non_vip_visibility_1_1_2` | paused | billing | 32329 | 669 | 0 |
| `ios_vip_price_catalog_20260625` | paused | billing | 176 | 715 | 0 |
| `ios_vip_price_catalog_20260625_v2` | paused | billing | 771 | 4657 | 0 |
| `chat_basic_persona_prompt_5050_20260518` | paused | chat | 113 | 1559 | 0 |
| `chat_basic_persona_prompt_5050_v2_20260519` | paused | chat | 207 | 1567 | 0 |
| `chat_basic_persona_prompt_5050_v3_20260519` | paused | chat | 297 | 3011 | 0 |
| `chat_basic_persona_prompt_5050_v4_20260520` | paused | chat | 4253 | 77240 | 0 |
| `chat_character_tone_prompt_v2_20260518` | paused | chat | 0 | 4912 | 0 |
| `chat_cold_persona_prompt_5050_20260518` | paused | chat | 280 | 4082 | 0 |
| `chat_cold_persona_prompt_5050_v2_20260520` | paused | chat | 2683 | 67857 | 0 |
| `chat_dynamic_decide_recent_context_registered_user_20260609` | paused | chat | 49 | 1017 | 0 |
| `chat_dynamic_reply_shape_bubble_cap_minus1_202606` | paused | chat | 61 | 918 | 0 |
| `chat_dynamic_reply_shape_bubble_cap_minus1_v2_20260618` | paused | chat | 2744 | 91620 | 0 |
| `chat_generate_model_deepseek_pro_flash_202605` | paused | chat | 580 | 13289 | 0 |
| `chat_generate_reply_prompt_3arm_20260515` | paused | chat | 1169 | 40027 | 0 |
| `chat_generate_reply_prompt_v2_20260514` | paused | chat | 674 | 12080 | 0 |
| `chat_generate_reply_sticker_delivery_202605` | paused | chat | 170 | 3625 | 0 |
| `chat_inner_os_prompt_v2_examples_20260628` | paused | chat | 861 | 0 | 0 |
| `chat_personality_recipe_inject_20260517` | paused | chat | 107 | 1609 | 0 |
| `android_candy_catalog_18_38_88_128_20260613` | running | billing | 1270 | 4997 | 0 |
| `candy_first_6_recharge_bonus_100pct_20260629` | stopped | billing | 907 | 2815 | 0 |
| `chat_dynamic_reply_shape_mode_examples_v1_new_users_20260702` | stopped | chat | 19 | 1043 | 0 |
| `chat_dynamic_reply_shape_zero_example_v3_20260622` | stopped | chat | 8097 | 469227 | 1 |
| `chat_dynamic_reply_shape_zero_example_v4_new_users_20260629` | stopped | chat | 30 | 183 | 0 |
| `chat_dynamic_reply_shape_zero_example_v5_new_users_20260629` | stopped | chat | 3815 | 139166 | 0 |
| `chat_generate_reply_dynamic_prompt_ab_20260624` | stopped | chat | 1716 | 55536 | 0 |
| `chat_generate_reply_dynamic_prompt_three_arm_20260627` | stopped | chat | 1602 | 43229 | 0 |
| `chat_message_candy_cost_new_users_20260630` | stopped | chat | 500 | 0 | 0 |

## 业务影响评估

### 付费 / 会员

不影响当前 Android 会员业务：

- Android 会员页已固定走当前套餐目录，不再解析 Android VIP 历史实验。
- 删除前已确认服务端代码不消费 Android VIP 实验 key。

不影响当前 iOS 会员业务：

- 删除前数据库中的 `ios_vip_price_catalog_20260625_v2` 已是 `paused`，线上实际不会下发实验目录。
- 代码已改为不再尝试解析该 key，继续走当前固定 iOS 目录和现有价格 override。

### 糖果

不影响当前糖果钱包目录：

- Android 糖果目录代码已固定返回 `6 / 18 / 38 / 128`。
- 删除 `android_candy_catalog_18_38_88_128_20260613` 只清理数据库残留，不改变目录。

不影响当前首充赠送口径：

- stopped 的 `candy_first_6_recharge_bonus_100pct_20260629` 已从代码移除。
- 保留 2026-06-29 09:04:38 UTC 后新用户不进入旧首充实验的逻辑，避免新用户赠送策略变化。
- 旧用户仍可按当前 running 的 `candy_recharge_bonus_100pct_20260626` 规则解析。

### 聊天

不影响当前聊天实验：

- 删除前 chat-svr 已将已关停的 prompt / 计费实验默认 key 改为空，默认启动不再解析旧 key。
- 保留当前仍 running 的聊天实验，例如 `chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703`、`chat_inner_os_on_demand_202606` 等。
- 实验解析框架未删除，未来显式配置新实验 key 仍可使用。

## 删除后剩余实验

截至 2026-07-03 18:25 CST，`experiments` 表当前剩余 8 个实验，全部为 `running`，无 paused 实验定义。

| 实验 key | domain | client_visible | server_visible |
|---|---|---:|---:|
| `candy_recharge_bonus_100pct_20260626` | billing | false | true |
| `chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703` | chat | false | true |
| `chat_gender_replay_default_model_deepseek_pro_flash_20260615` | chat | false | true |
| `chat_gender_replay_model_deepseek_pro_flash_202606` | chat | false | true |
| `chat_generate_reply_sticker_delivery_v2_20260513` | chat | false | true |
| `chat_inner_os_on_demand_202606` | chat | true | true |
| `chat_inner_os_price_1_0_8_1_20260601` | chat | false | true |
| `chat_raw_character_prompt_fields_20260626` | chat | false | true |

2026-07-03 18:22 已删除 `chat_message_candy_cost_new_users_20260701`。删除前该 key 有 assignment 2,357、exposure 0、override 0；删除实验定义后历史 assignment 仍保留在历史表中。

2026-07-03 18:25 已删除 `chat_inner_os_prompt_v2_20260627` 与 `chat_inner_os_prompt_v2_examples_20260628`。删除前分别有 assignment 855 / 861，exposure 均为 0，override 均为 0；删除实验定义后历史 assignment 仍保留在历史表中。

## 验证记录

已完成：

1. 删除事务返回 `deletedExperiments=36`。
2. 删除后按原 key 查询 `experiments`，`remaining=[]`。
3. 删除后 `experiments` 表剩余 10 个，全部为 `running`。
4. 搜索 `moodly_server/src` 与 `moodly-chat-svr/src`，真实已删 key 不再出现在运行时代码中。
5. 2026-07-03 18:18 恢复 `chat_inner_os_prompt_v2_examples_20260628` 后复查：
   - `status=paused`
   - `client_visible=false`
   - `server_visible=false`
   - 关联历史 assignment 861，exposure 0，override 0
6. `moodly_server` targeted tests 通过：
   - `npx vitest run src/modules/candy/candy.service.test.ts src/modules/vip/vip.service.test.ts src/modules/experiments/experiments.service.test.ts`
   - 结果：3 files / 86 tests passed。
7. `moodly-chat-svr` 初始 targeted tests 通过：
   - `npx vitest run src/config/env.test.ts src/core/experiments/chat-inner-os-prompt-experiment.test.ts src/core/experiments/chat-reply-shape-experiment.test.ts src/core/experiments/chat-dynamic-decide-context-experiment.test.ts src/core/experiments/chat-message-candy-cost-experiment.test.ts src/core/experiments/chat-generate-reply-dynamic-prompt-experiment.test.ts src/modules/chat/inner-os-generate.test.ts src/modules/chat/chat-message-candy-billing.test.ts`
   - 结果：8 files / 42 tests passed。
8. 2026-07-03 18:22 删除 `chat_message_candy_cost_new_users_20260701` 后补充验证：
   - 数据库复查：该 key 已不存在；当前 9 个 `running` + 1 个 `paused`。
   - 源码复查：`moodly_server/src` 与 `moodly-chat-svr/src` 不再出现真实 key `chat_message_candy_cost_new_users_20260701`。
   - `moodly_server`: `npx vitest run src/modules/experiments/experiments.service.test.ts`，13 tests passed。
   - `moodly-chat-svr`: `npx vitest run src/config/env.test.ts src/core/experiments/chat-message-candy-cost-experiment.test.ts src/modules/chat/chat-message-candy-billing.test.ts`，24 tests passed。
9. 2026-07-03 18:25 删除内心 OS prompt 两个实验后补充验证：
   - `chat_inner_os_prompt_v2_20260627`：先从 running 更新为 paused，再删除定义；删除前 assignment 855、exposure 0、override 0。
   - `chat_inner_os_prompt_v2_examples_20260628`：删除 paused 定义；删除前 assignment 861、exposure 0、override 0。
   - 数据库复查：两个 key 均已不存在；当前 8 个 `running`，无 paused 实验定义。
   - 源码复查：`moodly_server/src` 与 `moodly-chat-svr/src` 不再出现这两个真实 key。
   - `moodly-chat-svr`: `npx vitest run src/config/env.test.ts src/core/experiments/chat-inner-os-prompt-experiment.test.ts src/modules/chat/inner-os-generate.test.ts`，28 tests passed。
10. 2026-07-03 18:48 追加业务代码清理后验证：
   - 源码复查：`moodly-chat-svr/src`、`prompts`、`scripts` 中不再出现已删除 env key、实验模块名、旧 prompt 名、主动 metered 扣费入口。
   - `moodly-chat-svr`: `npx vitest run src/config/env.test.ts src/core/experiments/chat-reply-shape-experiment.test.ts src/core/interaction/personality-reply-shape.test.ts src/core/interaction/dynamic-ability.test.ts src/modules/chat/inner-os-generate.test.ts src/modules/chat/chat-message-candy-billing.test.ts src/modules/chat/reactive-input.test.ts src/modules/chat/regenerate.test.ts`，8 files / 62 tests passed。
   - `moodly-chat-svr`: `npx vitest run src/core/experiments/chat-model-experiment.test.ts`，1 file / 5 tests passed。
   - `moodly-chat-svr`: `npm run build` 通过，Prisma Client 生成与 TypeScript 编译均成功。

额外说明：

1. 曾额外尝试运行 `moodly-chat-svr/src/core/interaction/engine.generate-reply-repair.test.ts`；当前 26 个用例中 24 个通过，剩余 2 个失败在敏感词 trace 断言：当前 trace 的 `matched_patterns` 中仍包含 `moodly_mock_sensitive_word`。该失败与本次实验删除无关，未作为本次清理阻塞项。
2. 如需要上线前回归，补一轮会员页、糖果钱包、普通聊天、内心 OS smoke test。

## 回滚说明

本次物理删除的是 `experiments` 定义行。复查确认历史 assignment / exposure / override 明细仍保留在历史表中，可通过重建同名 `experiment_key` 的实验定义重新关联。`chat_inner_os_prompt_v2_examples_20260628` 曾按此方式恢复为 `paused`，随后已于 2026-07-03 18:25 再次删除定义。

如果需要恢复某个实验能力，应重新创建实验定义并重新接入代码，不建议复活本次已删除 key。
