# 关停实验清理方案

Status: implementation record

执行备注：2026-07-03 已执行清理，详见 `docs/experiment_shutdown_delete_record_20260703.md`。本文件保留方案与执行顺序背景。

日期：2026-07-03  
目标：最小单位清理已关停实验，避免影响线上业务、历史分析和客户端兼容。

关联清单：`docs/experiment_shutdown_inventory_20260702.md`

## 清理原则

1. 先断代码引用，再动数据库。
2. 有 assignment / exposure / override 的实验默认不物理删除，先归档。
3. 正在被运行时代码或默认环境变量引用的实验，不直接删。
4. 每次只清一个实验或一个强相关实验组，方便回滚和验证。
5. 删除代码时保留当前生产固定口径，不能改变价格、扣费、提示词、模型或入口显示行为。

## 最小清理单元

每个实验按下面 5 步走：

1. 确认业务当前口径
   - 当前线上是否仍会 resolve 该 experiment key。
   - 关停后的固定行为是什么。
   - 是否有旧客户端仍消费 bootstrap 实验。

2. 清代码引用
   - 删除常量、默认 env、resolve 调用、payload 解析、曝光上报。
   - 保留固定业务逻辑，直接走当前默认分支。
   - 删除或更新只服务该实验的测试。

3. 清文档
   - 把实验文档标记为 historical，或在现有 owner 文档记录“已下线，代码已移除”。
   - 不新建平行主题文档。

4. 数据库处理
   - 没有历史数据：可以物理删除实验定义。
   - 有历史数据：先改 `status='archived'`、`client_visible=false`、`server_visible=false`。
   - 如要物理删除，先导出 `experiment_assignments` / `experiment_exposures` / `experiment_overrides`。

5. 验证
   - 查询实验不再从 bootstrap / resolve API 返回。
   - 跑对应模块测试。
   - 对付费、糖果、聊天扣费类实验做接口 smoke test。

## 第一批：可安全最小清理

### 1. 删除误写空实验

实验：`chat_inner_os_price_1_8_1_202606`

当前状态：
- `draft`
- assignment 0
- exposure 0
- override 0
- 无运行时代码引用

操作：

```sql
DELETE FROM experiments
WHERE experiment_key = 'chat_inner_os_price_1_8_1_202606'
  AND status = 'draft'
  AND NOT EXISTS (
    SELECT 1 FROM experiment_assignments
    WHERE experiment_assignments.experiment_key = experiments.experiment_key
  )
  AND NOT EXISTS (
    SELECT 1 FROM experiment_exposures
    WHERE experiment_exposures.experiment_key = experiments.experiment_key
  )
  AND NOT EXISTS (
    SELECT 1 FROM experiment_overrides
    WHERE experiment_overrides.experiment_key = experiments.experiment_key
  );
```

验证：

```sql
SELECT experiment_key, status
FROM experiments
WHERE experiment_key = 'chat_inner_os_price_1_8_1_202606';
```

预期：0 行。

## 第二批：只归档，不删历史数据

### 2. 糖果钱包入口实验归档

实验：`candy_wallet_entry_non_vip_visibility_1_1_2`

当前状态：
- 客户端已移除消费代码。
- 新逻辑走支付开关 + 青少年模式开关。
- 有大量历史 assignment，不能直接物理删。

操作：

1. 执行已有脚本：

```sql
-- moodly_server/prisma/archive_candy_wallet_entry_non_vip_visibility_experiment.sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'system',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key = 'candy_wallet_entry_non_vip_visibility_1_1_2';
```

2. 验证客户端 bootstrap 不返回该实验。
3. 保留历史 assignment / exposure。

### 3. Android 会员价格实验归档

实验：
- `android_vip_catalog_copy_year_anchor_v1`
- `android_vip_price_catalog_20260625`
- `android_vip_price_catalog_20260625_v2`
- `android_vip_plan_catalog_v1`
- `android_vip_price_new_user_v2`
- `android_vip_price_new_user_v3`

当前固定业务口径：
- Android 会员页不再读取实验。
- 固定下发 VIP 月卡/周卡/年卡与 Pro 月卡/周卡/年卡。
- 连续包月入口隐藏。

操作：

1. 确认 `moodly_server/src/modules/vip/vip.service.ts` Android 分支不返回 experiment 字段。
2. 将上述实验统一归档：

```sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'archive_android_vip_retired_experiments_20260703',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key IN (
  'android_vip_catalog_copy_year_anchor_v1',
  'android_vip_price_catalog_20260625',
  'android_vip_price_catalog_20260625_v2',
  'android_vip_plan_catalog_v1',
  'android_vip_price_new_user_v2',
  'android_vip_price_new_user_v3'
);
```

验证：
- `GET /v1/vip/plans?platform=android` 返回固定目录。
- 响应中 `experiment=null` 或无实验字段。
- Android 会员购买金额仍为当前固定价。

## 第三批：先清代码引用，再归档

这些实验当前不是 `running`，但代码仍引用。必须先改代码，确认固定口径后再归档。

### 4. 6 元糖果首充实验

实验：`candy_first_6_recharge_bonus_100pct_20260629`

当前风险：
- `moodly_server/src/modules/candy/candy.service.ts` 仍先 resolve 该 key，再 fallback 到 `candy_recharge_bonus_100pct_20260626`。
- 如果直接删，业务不会崩，但会产生一次 resolve miss；代码仍有历史噪音。

最小代码清理：
- 删除 `CANDY_FIRST_6_RECHARGE_BONUS_EXPERIMENT_KEY`。
- 删除 `CANDY_FIRST_6_RECHARGE_BONUS_NEW_USER_SINCE` 分流保护中只服务旧实验的判断。
- `resolveCandyRechargeBonusExperiment` 只解析当前 `CANDY_RECHARGE_BONUS_EXPERIMENT_KEY`。
- 更新 candy service 测试，删除 first-6 实验专属用例。

固定口径：
- 当前首充赠送以 `candy_recharge_bonus_100pct_20260626` 为准。

数据库：

```sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'archive_candy_first_6_recharge_bonus_20260703',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key = 'candy_first_6_recharge_bonus_100pct_20260629';
```

验证：
- 糖果包列表正常。
- 首充赠送规则仍按当前线上口径返回。
- `yarn test:run src/modules/candy/candy.service.test.ts`。

### 5. iOS VIP 价格实验 v2

实验：`ios_vip_price_catalog_20260625_v2`

当前风险：
- 数据库是 `paused`，但 `moodly_server/src/modules/vip/vip.service.ts` 仍把它作为 iOS catalog experiment key。
- 文档有 running / paused 冲突。

先决策：
- 如果要恢复实验：不要清理，先把数据库与文档恢复一致。
- 如果确认下线：按下面清理。

最小代码清理：
- 删除 `IOS_VIP_PLAN_CATALOG_EXPERIMENT_KEY`。
- `vipCatalogExperimentKeyForPlatform('ios')` 返回 `null`。
- 删除或降级 iOS catalog experiment 相关测试。
- 保留 iOS 当前固定商品目录和价格 override 口径。

数据库：

```sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'archive_ios_vip_price_catalog_v2_20260703',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key IN (
  'ios_vip_price_catalog_20260625',
  'ios_vip_price_catalog_20260625_v2'
);
```

验证：
- `GET /v1/vip/plans?platform=ios` 不再 resolve 实验。
- iOS 会员页商品仍是当前固定目录。
- Apple product id、价格展示、下单金额不变。

### 6. chat-svr 默认 env 仍引用的实验

实验：
- `chat_dynamic_decide_recent_context_registered_user_20260609`
- `chat_dynamic_reply_shape_zero_example_v3_20260622`
- `chat_inner_os_prompt_v2_examples_20260628`

当前风险：
- `moodly-chat-svr/src/config/env.ts` 默认值仍指向这些 key。
- 直接删数据库会导致运行时 resolve miss 或走 fallback，但代码仍不干净。

最小代码清理：

1. `CHAT_DYNAMIC_DECIDE_CONTEXT_EXPERIMENT_KEY` 默认改为空字符串。
2. `CHAT_REPLY_SHAPE_EXPERIMENT_KEY` 默认改为空字符串，或改成当前 running 的替代实验 key，二选一。
3. `CHAT_INNER_OS_PROMPT_EXPERIMENT_KEY` 默认改为空字符串，固定使用当前 prompt。
4. 删除相关实验 payload 分支中不再使用的 helper。
5. 更新对应测试，断言空 key 时不发起 resolve。

数据库：

```sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'archive_chat_svr_retired_experiments_20260703',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key IN (
  'chat_dynamic_decide_recent_context_registered_user_20260609',
  'chat_dynamic_reply_shape_zero_example_v3_20260622',
  'chat_inner_os_prompt_v2_examples_20260628'
);
```

验证：
- chat-svr 启动不再默认请求这 3 个实验。
- 普通聊天回复形态、上下文选择、内心 OS prompt 与当前固定口径一致。
- 跑 chat-svr 对应 experiment / engine 测试。

## 第四批：历史 chat 实验批量归档

实验：
- persona prompt 系列
- cold persona prompt 系列
- generate_reply prompt 系列
- old sticker delivery
- old dynamic reply shape
- old dynamic prompt

操作：

```sql
UPDATE experiments
SET
  status = 'archived',
  client_visible = false,
  server_visible = false,
  updated_by = 'archive_historical_chat_experiments_20260703',
  updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key IN (
  'chat_basic_persona_prompt_5050_20260518',
  'chat_basic_persona_prompt_5050_v2_20260519',
  'chat_basic_persona_prompt_5050_v3_20260519',
  'chat_basic_persona_prompt_5050_v4_20260520',
  'chat_character_tone_prompt_v2_20260518',
  'chat_cold_persona_prompt_5050_20260518',
  'chat_cold_persona_prompt_5050_v2_20260520',
  'chat_dynamic_reply_shape_bubble_cap_minus1_202606',
  'chat_dynamic_reply_shape_bubble_cap_minus1_v2_20260618',
  'chat_generate_model_deepseek_pro_flash_202605',
  'chat_generate_reply_prompt_3arm_20260515',
  'chat_generate_reply_prompt_v2_20260514',
  'chat_generate_reply_sticker_delivery_202605',
  'chat_personality_recipe_inject_20260517',
  'chat_dynamic_reply_shape_zero_example_v4_new_users_20260629',
  'chat_generate_reply_dynamic_prompt_ab_20260624',
  'chat_generate_reply_dynamic_prompt_three_arm_20260627',
  'chat_message_candy_cost_new_users_20260630'
);
```

验证：
- 所有 key 不再被代码引用。
- 历史 assignment / exposure 仍可查询。
- 当前 running 实验不受影响。

## 必须先核实的状态冲突

### Android 糖果档位实验

实验：`android_candy_catalog_18_38_88_128_20260613`

冲突：
- 文档写已关闭。
- 数据库仍是 `running`。

处理：
- 如果业务确认已关闭：先把数据库改为 `archived`，并确认 Android 糖果钱包仍返回固定 `6/18/38/128`。
- 如果仍在跑：修正文档，不做清理。

### iOS VIP 价格实验 v2

实验：`ios_vip_price_catalog_20260625_v2`

冲突：
- 数据库是 `paused`。
- 部分文档写 `running`。
- 服务端代码仍引用。

处理：
- 先业务决策恢复或下线。
- 下线才进入第三批清理。

## 推荐执行顺序

1. 删除空误写实验 `chat_inner_os_price_1_8_1_202606`。
2. 归档 `candy_wallet_entry_non_vip_visibility_1_1_2`。
3. 归档 Android VIP 历史实验组。
4. 清 `candy_first_6_recharge_bonus_100pct_20260629` 代码后归档。
5. 决策并处理 `ios_vip_price_catalog_20260625_v2`。
6. 清 chat-svr 默认 env 引用后归档相关 chat 实验。
7. 批量归档剩余历史 chat 实验。
8. 最后统一更新 `docs/experiments.md`、`docs/vip.md`、`docs/candy.md` 和客户端验收清单。

## 回滚策略

1. 代码清理未发布前，不执行数据库归档。
2. 只归档不删除的实验，可通过恢复 `status='running'` 回滚，但必须确认代码仍支持该 payload。
3. 已物理删除的实验只能通过备份恢复，因此只允许删除无历史数据的空实验。
4. 付费、糖果、聊天扣费类实验每次清理后都要保留一轮 smoke test 记录。
