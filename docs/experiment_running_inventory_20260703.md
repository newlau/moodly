# 当前 running 实验清单

Status: current

盘点时间：2026-07-03 18:12:11 CST  
数据来源：`moodly_server` 当前数据库 `experiments` / `experiment_assignments` / `experiment_exposures` / `experiment_overrides`。

## 总览

删除关停实验后，`running` 实验当前为 8 个。2026-07-03 18:22 已删除暂停的 `chat_message_candy_cost_new_users_20260701`；2026-07-03 18:25 已暂停并删除 `chat_inner_os_prompt_v2_20260627`，同时删除此前恢复为 paused 的 `chat_inner_os_prompt_v2_examples_20260628`。这些非 running / 已删除项不计入下方 running 清单。

| 实验 key | domain | client_visible | server_visible | version | assignment | exposure | override |
|---|---|---:|---:|---:|---:|---:|---:|
| `candy_recharge_bonus_100pct_20260626` | billing | false | true | 2 | 2,936 | 13,476 | 0 |
| `chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703` | chat | false | true | 1 | 180 | 4,910 | 0 |
| `chat_gender_replay_default_model_deepseek_pro_flash_20260615` | chat | false | true | 2 | 20,048 | 62,149 | 0 |
| `chat_gender_replay_model_deepseek_pro_flash_202606` | chat | false | true | 1 | 98 | 5 | 1 |
| `chat_generate_reply_sticker_delivery_v2_20260513` | chat | false | true | 1 | 12,806 | 779,140 | 0 |
| `chat_inner_os_on_demand_202606` | chat | true | true | 2 | 10,250 | 384,226 | 2 |
| `chat_inner_os_price_1_0_8_1_20260601` | chat | false | true | 1 | 26,196 | 171,775 | 0 |
| `chat_raw_character_prompt_fields_20260626` | chat | false | true | 1 | 1,168 | 30,175 | 0 |

## Billing

### `candy_recharge_bonus_100pct_20260626`

名称：糖果首充赠送比例全量规则  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=redis_round_robin`，fallback=`treatment_full_bonus_ge_18`  
可见性：client=false，server=true  
版本：2  
开始时间：2026-06-26 13:39:32 UTC  
历史计数：assignment 2,936；exposure 13,476；override 0

用途：

- 新注册用户糖果首充赠送规则。
- 当前全量口径：6 元不赠送，18 元及以上赠送 100%。
- 只影响首充用户的糖果充值包展示和订单落单 `bonus_candy / total_candy`。

受众：

- 平台：iOS / Android
- 非游客
- 非未成年人
- `created_at >= 2026-06-26T13:39:32+08:00`

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control` | 0 | 历史对照，当前不再分配 |
| `treatment_full_bonus_ge_18` | 1 | 6 元不赠送，18 元及以上赠送 100% |

关注点：

- 这是当前唯一 running 的 billing 实验。
- 代码清理后 stopped 的 6 元首充实验已删除；当前首充赠送只应看这个 key。

## Chat

### `chat_dynamic_reply_shape_mode_examples_v2_new_users_20260703`

名称：Dynamic reply shape mode examples v2 new users  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=weighted_random`，fallback=`control_current_shape_v4`  
可见性：client=false，server=true  
版本：1  
开始时间：2026-07-03 05:58:56 UTC  
历史计数：assignment 180；exposure 4,910；override 0

用途：

- 新用户三臂 reply shape 实验。
- 对比当前线上 reply-shape snippets 与两种按 reply mode 生成示例的方案。

受众：

- 新用户：`created_at >= experiment.starts_at`
- 注册用户
- 非游客
- 非未成年人

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control_current_shape_v4` | 100 | 当前线上动态 reply-shape snippets |
| `treatment_asset_bubble_examples_v2` | 100 | 每种 reply mode 生成角色示例；第二段 prompt 只给 bubble requirements |
| `treatment_asset_bubble_length_examples_v2` | 100 | 每种 reply mode 生成角色示例；第二段 prompt 给 bubble + 总长度 requirements |

关注点：

- 这是删除旧 reply-shape 实验后当前唯一 running 的 reply shape 新实验。

### `chat_gender_replay_default_model_deepseek_pro_flash_20260615`

名称：gender_replay default DeepSeek V4 Pro rollout  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=redis_round_robin`，fallback=`treatment_pro`  
可见性：client=false，server=true  
版本：2  
历史计数：assignment 20,048；exposure 62,149；override 0

用途：

- 新注册用户默认进入 `gender_replay` 回复模型。
- 当前已推全到 DeepSeek V4 Pro。
- 与 `generate_reply` 和其他实验正交。

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control_flash` | 0 | 历史 control，不再分配 |
| `treatment_pro` | 1 | gender_replay 使用 DeepSeek V4 Pro |

关注点：

- 当前虽然是 running，但已经是推全态。后续可以单独评估是否改为固定代码/配置后清理。

### `chat_gender_replay_model_deepseek_pro_flash_202606`

名称：gender_replay DeepSeek V4 Pro vs Flash  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=redis_round_robin`，fallback=`control_flash`  
可见性：client=false，server=true  
版本：1  
历史计数：assignment 98；exposure 5；override 1

用途：

- gender_replay 模型 Flash vs Pro 对比实验。
- 与默认模型 rollout 实验并存。

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control_flash` | 1 | gender_replay 使用 DeepSeek V4 Flash |
| `treatment_pro` | 1 | gender_replay 使用 DeepSeek V4 Pro |

关注点：

- 与 `chat_gender_replay_default_model_deepseek_pro_flash_20260615` 功能相近，需要确认两者是否仍都需要保留。

### `chat_generate_reply_sticker_delivery_v2_20260513`

名称：Chat generate_reply sticker delivery v2  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=server_deterministic`，fallback=`treatment_deliver`  
可见性：client=false，server=true  
版本：1  
历史计数：assignment 12,806；exposure 779,140；override 0

用途：

- generate_reply sticker delivery 实验。
- 当前只有一个 treatment 变体，服务端确定性返回。

变体：

| variant | weight | 口径 |
|---|---:|---|
| `treatment_deliver` | 1 | 通过 `select_sticker` 投递 decide-driven stickers |

关注点：

- 单臂 running，基本是功能开关/推全态。后续可评估改固定逻辑后清理。

### `chat_inner_os_on_demand_202606`

名称：聊天内心 OS 按需生成实验  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=redis_round_robin`，fallback=`control`  
可见性：client=true，server=true  
版本：2  
历史计数：assignment 10,250；exposure 384,226；override 2

用途：

- 客户端可见实验。
- A 组保持主回复生成并隐藏内心 OS。
- B 组主回复不生成内心 OS，客户端展示轻量入口，点击后独立生成并缓存。

受众：

- iOS / Android
- 非游客
- 非未成年人
- app version >= 1.0.8

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control` | 1 | 线上旧体验，主回复仍生成内心 OS，入口关闭 |
| `on_demand` | 1 | 主回复移除内心 OS，点击后按需生成 |

关注点：

- 唯一 `client_visible=true` 的 running 实验。
- 删除或改动前必须检查 iOS / Android 客户端消费逻辑。

### `chat_inner_os_price_1_0_8_1_20260601`

名称：内心 OS 糖果价格实验  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=redis_round_robin`，fallback=`price_50`  
可见性：client=false，server=true  
版本：1  
历史计数：assignment 26,196；exposure 171,775；override 0

用途：

- 内心 OS 单次消耗价格。
- 当前已推全为 50 糖果。
- 不影响充值、每日免费糖果、VIP 赠送糖果。

受众：

- iOS / Android
- 非游客
- 非未成年人
- app version >= 1.0.8

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control` | 0 | 历史对照，当前 payload 也为 50 |
| `price_50` | 1 | 当前全量：50 糖果 |
| `price_100` | 0 | 历史实验组，当前 payload 也改为 50 |

关注点：

- 已是推全态。后续可以评估改为固定 50 糖果并删除实验。


### `chat_message_candy_cost_new_users_20260701`

2026-07-03 18:22 已从 running 清单移除并删除实验定义。

删除前状态：

- `status=paused`
- `ends_at=2026-07-03T10:19:40.270Z`
- assignment 2,357
- exposure 0
- override 0
- 删除前快照：`docs/experiment_deleted_chat_message_candy_cost_20260701_snapshot.json`

### `chat_raw_character_prompt_fields_20260626`

名称：Raw custom-character prompt template 50/50  
状态：`running`  
分配：`unit_type=user`，`allocation_strategy=round_robin`，fallback=`control_current_prompt`  
可见性：client=false，server=true  
版本：1  
历史计数：assignment 1,168；exposure 30,175；override 0

用途：

- 新用户 generate_reply prompt template 50/50。
- control 使用当前 prompt template。
- treatment 使用独立 raw-user-settings prompt template，读取原始保存的自定义角色字段。

受众：

- 注册用户
- 非游客
- 允许未成年人
- `created_at >= 2026-06-25T20:38:10+08:00`

变体：

| variant | weight | 口径 |
|---|---:|---|
| `control_current_prompt` | 1 | 当前线上 prompt template |
| `treatment_raw_user_settings_prompt` | 1 | raw-user-settings prompt template |

关注点：

- 仍有大量 exposure，说明正在被消费和记录。

## 建议关注

1. `chat_gender_replay_default_model_deepseek_pro_flash_20260615`、`chat_generate_reply_sticker_delivery_v2_20260513`、`chat_inner_os_price_1_0_8_1_20260601` 都呈现推全或单臂状态，后续可单独评估是否固化代码后清理。
2. `chat_inner_os_on_demand_202606` 是唯一 client-visible running 实验，任何清理都要同步检查 iOS / Android 客户端消费逻辑。
3. 普通聊天计费实验 `chat_message_candy_cost_new_users_20260701` 已暂停并删除定义；当前聊天计费应回到固定策略或显式配置的新实验。
4. 内心 OS prompt 实验 `chat_inner_os_prompt_v2_20260627` 与 `chat_inner_os_prompt_v2_examples_20260628` 已删除定义；当前默认 prompt 行为由代码/环境配置决定。
