# Android 支付宝订阅接入执行与排错文档

## 一、当前业务目标

Android 会员页做 4 档商品实验，并保持 iOS 与糖果业务不受影响：

- `month_auto_first`
  - 首次支付：`15`
  - 后续续费：`25`
- `month`
  - 月卡，单独购买：`15`
- `week`
  - 周卡，单独购买：`15`
- `year`
  - 年卡，单独购买：`98`

说明：

- 当前数据库里的 `month_auto_first.priceCny` 仍可能是 `25`
- 为避免影响 iOS StoreKit 月卡，Android `month` 的 `15` 由服务端按 `platform=android` / 支付宝或微信支付运行时兜底
- `year` 需要当前数据库执行 `prisma/upsert_android_vip_experiment_plans.sql` 做幂等补齐

## 二、不会影响的业务

本次改动按渠道和模块做了隔离：

- iOS Apple 订阅链路保持原样
- 糖果支付宝购买保持原样
- Android 会员普通展示接口继续使用 `/v1/vip/plans`
- Android 会员页当前只下发 4 档普通会员实验商品，不再补本地 SVIP fallback

## 三、当前服务端实现

### 1. 连续包月首次支付并签约

Android 调用：

- `POST /v1/vip/subscriptions/alipay/pay-and-sign`

服务端动作：

1. 创建 `vip_subscriptions`
2. 创建 `vip_orders`
3. 调支付宝 `alipay.trade.app.pay`
4. 在支付参数中附带 `agreement_sign_params`
5. 返回 `pay_params` 给 Android

Android 使用：

- `PayTask.payV2(...)`

### 2. 支付回调

支付宝支付成功回调：

- `/v1/vip/pay/notify/alipay`

服务端动作：

1. 校验支付成功
2. 查询订单状态
3. 更新 `vip_orders.pay_status=paid`
4. 开通会员
5. 若该订单绑定订阅，则记为 `subscription_initial`

### 3. 签约回调

同一路由处理签约状态：

- `/v1/vip/pay/notify/alipay`

服务端动作：

1. 更新 `agreement_no`
2. 更新 `vip_subscriptions.status=active`
3. 更新 `auto_renew=true`
4. 计算 `next_deduct_at`

### 4. 单独购买

Android 调用：

- `POST /v1/vip/orders`

适用套餐：

- `month`
- `week`
- `year`

服务端按 Android 实验价生成支付宝订单：

- `month`: `15`
- `week`: `15`
- `year`: `98`

### 5. 后续自动续费

当前已补服务端维护任务：

- 每 10 分钟扫描一次
- 任务名：`vip-subscription-maintenance`

处理逻辑：

1. 同步待签约/活跃协议状态
2. 扫描到期订阅
3. 对 `agreement_no` 发起商家扣款
4. 成功则新增/更新续费订单并延长会员
5. 失败则标记 `past_due`，12 小时后重试

## 四、关键文件

### 服务端

- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.service.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.routes.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.subscription.scheduler.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/vendor/pay/alipay.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/vendor/pay/interface.ts`

### Android

- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/data/network/VipApiService.kt`
- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/ui/membership/MembershipViewModel.kt`
- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/ui/screens/SubscriptionScreen.kt`

## 五、数据库表重点

### 1. `vip_subscriptions`

重点字段：

- `external_agreement_no`
- `agreement_no`
- `status`
- `auto_renew`
- `signed_at`
- `next_deduct_at`
- `last_deduct_at`
- `deduct_fail_count`

### 2. `vip_orders`

重点字段：

- `order_id`
- `pay_status`
- `order_type`
  - `normal`
  - `subscription_initial`
  - `subscription_renewal`
- `subscription_id`

### 3. `vip_status`

重点字段：

- `is_active`
- `expire_date`
- `auto_renew`
- `original_transaction_id`

## 六、联调验证步骤

### Phase 1：首次支付并签约

1. Android 会员页确认只展示 `month_auto_first/month/week/year`
2. 勾选自动续费协议
3. 选择 `month_auto_first` 点击购买
4. 应拉起支付宝支付并签约
5. 支付完成后：
   - `vip_orders` 应新增一条 `subscription_initial`
   - `vip_subscriptions` 应有 `pending_sign/active`

查库 SQL：

```sql
SELECT order_id, plan_code, pay_status, order_type, subscription_id, transaction_id
FROM vip_orders
ORDER BY created_at DESC
LIMIT 20;
```

```sql
SELECT id, user_id, plan_id, external_agreement_no, agreement_no, status, auto_renew, next_deduct_at, last_deduct_at, deduct_fail_count
FROM vip_subscriptions
ORDER BY created_at DESC
LIMIT 20;
```

### Phase 2：签约成功

预期：

- `vip_subscriptions.status = active`
- `vip_subscriptions.auto_renew = 1`
- `agreement_no` 已回填

### Phase 2.5：单独购买

1. Android 会员页选择 `month/week/year`
2. 勾选充值协议
3. 点击购买
4. 应拉起普通支付宝支付，不创建 `vip_subscriptions`
5. `vip_orders.amount` 应分别为 `15/15/98`

### Phase 3：后续续费

可临时把某条订阅的 `next_deduct_at` 改到当前时间前：

```sql
UPDATE vip_subscriptions
SET next_deduct_at = DATE_SUB(NOW(), INTERVAL 5 MINUTE)
WHERE id = '你的订阅ID';
```

等待任务执行后检查：

- `vip_orders` 出现 `subscription_renewal`
- `vip_status.expire_date` 延长
- `vip_subscriptions.last_deduct_at` 更新
- `vip_subscriptions.next_deduct_at` 更新

## 七、常见问题排查

### 1. 支付宝报“交易订单处理失败”

优先排查：

- 是否使用了旧 AppID
- 支付串是否为 `alipay.trade.app.pay`
- 是否仍在走纯签约接口
- 支付宝后台是否已绑定包名与 SHA1

### 2. 首月金额不对

当前首月 `15` 是服务端逻辑兜底，不完全依赖数据库：

- `month_auto_first` 首付金额在订阅逻辑里固定按 `15`
- `month` Android 单独购买金额按服务端 Android 运行时口径固定为 `15`
- `year` 需要当前数据库已执行 `prisma/upsert_android_vip_experiment_plans.sql`

### 3. 支付成功但没开会员

排查顺序：

1. `/v1/vip/pay/notify/alipay` 是否收到回调
2. `vip_orders.pay_status` 是否变成 `paid`
3. `users.vip_expire_at` 是否更新
4. `vip_status.is_active` 是否为 `1`

### 4. 已签约但没有自动续费

排查顺序：

1. `agreement_no` 是否已写入
2. `vip_subscriptions.status` 是否为 `active`
3. `auto_renew` 是否为 `1`
4. `next_deduct_at` 是否有值
5. 服务端定时任务日志是否报错

### 5. 续费失败

当前处理：

- 订阅转为 `past_due`
- `deduct_fail_count + 1`
- 12 小时后自动重试

## 八、上线建议

建议顺序：

1. 先在测试环境验证首次支付并签约
2. 再验证签约回调
3. 再手动压测续费任务
4. 确认 `vip_orders`、`vip_subscriptions`、`vip_status` 状态闭环完整
5. 最后再考虑是否同步修正数据库套餐价格

## 九、后续可继续优化

- 补专门的续费任务管理日志表
- 增加失败重试上限与告警
- 增加手动触发某条订阅续费的后台接口
- 增加订阅详情接口，返回更完整的 `expire_at`
