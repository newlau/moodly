状态：historical instruction（2026-06-05 已同步会员充值额外 20% 加赠移除口径）

请基于现有工程，直接完成 Moodly 糖果模块的服务端与 iOS 接入方案审查和落地设计，不要只做泛泛分析，要结合代码库给出具体文件、类、接口、字段、可复用能力、缺失能力，以及最小可上线实现方案。

项目：
- 服务端：moodly-server
- iOS：moodly-ios

背景：
- 会员相关接口已经接入，但 App Store Connect 商品还没有完整配置
- moodly-ios 里已经有一个文档：`App Store Connect Setup.md`，内容是昨天写的“会员接口接入后如何配置商品”
- 现在要新增“糖果模块”接入到 iOS 中
- 服务端代码在 `moodly-server`

目标：
1. 审查 moodly-server 和 moodly-ios 当前已有能力
2. 设计并补齐糖果模块接口
3. 设计 iOS 糖果钱包 / 充值 / 流水接入方案
4. 结合现有会员支付逻辑，给出 App Store Connect 的糖果商品配置方案
5. 输出工程化、可执行的改造清单

---

# 一、糖果模块 PRD（严格按此理解，不要擅自改业务含义）

## 1. 获取糖果余额
GET /candy/balance

响应示例：
{
  "code": 0,
  "msg": "success",
  "data": {
    "balance": 223
  }
}

## 2. 获取糖果充值套餐列表
GET /candy/packages

说明：
- 6 个套餐及首充赠送逻辑均由接口控制
- 前端不硬编码价格

响应示例：
{
  "code": 0,
  "msg": "success",
  "data": {
    "balance": 223,
    "is_first_recharge": true,
    "packages": [
      {
        "package_id": "candy_100",
        "candy_amount": 100,
        "price": 1.00,
        "bonus_candy": 100,
        "total_candy": 200,
        "tag": "首充多赠100糖果",
        "tag_visible": true,
        "is_popular": false,
        "sort": 1
      },
      {
        "package_id": "candy_600",
        "candy_amount": 600,
        "price": 8.00,
        "bonus_candy": 600,
        "total_candy": 1200,
        "tag": "首充多赠600糖果",
        "tag_visible": true,
        "is_popular": false,
        "sort": 2
      },
      {
        "package_id": "candy_1200",
        "candy_amount": 1200,
        "price": 18.00,
        "bonus_candy": 1200,
        "total_candy": 2400,
        "tag": "首充多赠1200糖果",
        "tag_visible": true,
        "is_popular": false,
        "sort": 3
      },
      {
        "package_id": "candy_3000",
        "candy_amount": 3000,
        "price": 38.00,
        "bonus_candy": 3000,
        "total_candy": 6000,
        "tag": "首充多赠3000糖果",
        "tag_visible": true,
        "is_popular": true,
        "sort": 4
      },
      {
        "package_id": "candy_6800",
        "candy_amount": 6800,
        "price": 88.00,
        "bonus_candy": 6800,
        "total_candy": 13600,
        "tag": "首充多赠6800糖果",
        "tag_visible": true,
        "is_popular": false,
        "sort": 5
      },
      {
        "package_id": "candy_12800",
        "candy_amount": 12800,
        "price": 168.00,
        "bonus_candy": 12800,
        "total_candy": 25600,
        "tag": "首充多赠12800糖果",
        "tag_visible": true,
        "is_popular": false,
        "sort": 6
      }
    ]
  }
}

字段说明：
- candy_amount：基础购买糖果数
- bonus_candy：首充额外赠送数量（非首充时为 0）
- total_candy：实际到账数（首充 = candy_amount + bonus_candy，非首充 = candy_amount）
- tag_visible：是否展示标签（非首充用户不显示首充标签）

## 3. 创建糖果充值订单
POST /candy/orders

请求体：
{
  "package_id": "candy_3000",
  "pay_channel": "alipay"
}

说明：
- pay_channel: "alipay" | "wechat" | "apple_iap"

响应示例：
{
  "code": 0,
  "msg": "success",
  "data": {
    "order_id": "CO_20260326_001",
    "package_id": "candy_3000",
    "candy_amount": 3000,
    "bonus_candy": 3000,
    "total_candy": 6000,
    "price": 38.00,
    "pay_channel": "alipay",
    "pay_params": {
      "orderString": "alipay_sdk=alipay..."
    },
    "expire_at": "2026-03-26T12:30:00Z"
  }
}

## 4. 查询充值订单状态
GET /candy/orders/{order_id}

响应示例：
{
  "code": 0,
  "msg": "success",
  "data": {
    "order_id": "CO_20260326_001",
    "status": "paid",
    "candy_credited": 4500,
    "new_balance": 4723,
    "paid_at": "2026-03-26T10:20:00Z"
  }
}

状态：
- pending
- paid
- failed
- cancelled

## 5. 获取糖果账单（交易流水）
GET /candy/transactions

Query 参数：
- type: all | expense | income，默认 all
- page: 默认 1
- page_size: 默认 20，最大 50

响应示例：
{
  "code": 0,
  "msg": "success",
  "data": {
    "total": 42,
    "page": 1,
    "page_size": 20,
    "balance": 223,
    "list": [
      {
        "tx_id": "TX_001",
        "type": "expense",
        "label": "角色主动聊天-发送消息",
        "amount": -10,
        "balance_after": 223,
        "created_at": "2026-03-26T10:00:00Z"
      },
      {
        "tx_id": "TX_002",
        "type": "income",
        "label": "每日签到奖励",
        "amount": 60,
        "balance_after": 233,
        "created_at": "2026-03-25T09:00:00Z"
      },
      {
        "tx_id": "TX_003",
        "type": "income",
        "label": "糖果充值",
        "amount": 4500,
        "balance_after": 173,
        "created_at": "2026-03-24T15:30:00Z"
      }
    ]
  }
}

---

# 二、通用错误码

0     success               成功
401   unauthorized          Token 无效或过期
403   forbidden             无权限
404   not_found             资源不存在
1001  already_checked_in    今日已签到
1002  vip_already_active    会员已生效，无需重复购买
1003  order_expired         订单已过期
1004  payment_failed        支付失败
1005  insufficient_candy    糖果余额不足
1006  plan_not_found        套餐不存在
1007  package_not_found     充值包不存在
5000  server_error          服务端错误

---

# 三、糖果体系补充规则

## 获取渠道
- 每日签到：66~130 糖果 / 天
- 连续 7 天可得 700（现有逻辑保留）
- VIP 会员每月赠送：1000 糖果 / 月（请检查是否已实现，不要臆造）
- 充值购买：见充值档位
- 首充额外赠送
- 邀请好友注册：100 糖果 / 人
- 分享到社交平台：300 糖果 / 次（运营主动发放，有审核）

## 充值档位
- 体验包：100 糖果，¥1，首充 +100
- 基础包：600 糖果，¥8，首充 +600
- 进阶包：1200 糖果，¥18，首充 +1200
- 超值包：3000 糖果，¥38，首充 +3000
- 豪华包：6800 糖果，¥88，首充 +6800
- 尊享包：12800 糖果，¥168，首充 +12800

额外规则：
- 会员充值额外 20% 糖果加赠已移除，不要重新实现或写入客户端文案
- 充值到账只按基础糖果数 + 首充赠送计算

---

# 四、增值服务体系（本次只做钱包和充值基础能力，消费扣糖先做结构预留）

## 订阅类
- 无限聊天
- 更细腻模型
- 更长记忆存储
- 查看角色记忆
- 免广告
- 重启角色
- 引用回复
- 额外充值送币
- 签到领更多币
- 更多表情包额度
- 送定制声卡次数卡

## 增值类
- 主动分享图片：30 糖果/次
- 查看 TA 的日记：100 糖果/次
- 查 TA 手机：100 糖果/次
- 他在干嘛：200 糖果/次
- 语音回复：3 糖果/条
- 聊天气泡：300 糖果/套
- 主动推消息角色 +1：300 糖果/月
- 定制声卡：500 糖果/次
- 语音电话：20 糖果/分钟

注意：
- 本次重点先做糖果钱包 / 充值 / 流水能力
- 若扣糖消费接口尚未实现，只做结构预留与设计建议，不要擅自发明新接口

---

# 五、请按以下顺序执行

## 任务 1：审查项目现状

### 在 moodly-server 中检查
1. 是否已有：
   - 用户资产 / 钱包 / 余额表
   - 订单表 / 支付单表
   - 虚拟币流水表 / 积分表 / 收支明细表
   - 会员首充赠送相关字段或逻辑
2. 当前会员支付怎么实现：
   - 创建订单接口在哪
   - Apple IAP 回调 / 验证逻辑在哪
   - 支付状态轮询怎么做
3. 当前错误码体系、接口返回结构、认证中间件、数据库命名风格是什么

### 在 moodly-ios 中检查
1. 当前会员相关：
   - 网络层封装位置
   - 会员接口 model / service / viewModel 组织方式
   - StoreKit / IAP 封装位置
   - 支付结果轮询逻辑位置
2. 是否已有钱包页 / 虚拟币页 / 流水页 / 订单页 UI 或占位
3. `App Store Connect Setup.md` 中会员商品配置方式、命名规范、product id 规则是什么

要求：
- 先输出“现状结论”
- 明确列出：已有能力、可复用能力、缺失能力
- 具体到文件、模块、类名、接口名
- 不要只写泛泛结论

---

## 任务 2：设计糖果模块最小可上线方案

### 服务端
请给出：
1. 数据模型设计
   - candy balance 来源
   - candy package 配置来源
   - candy order 表结构建议
   - candy transaction 流水结构建议
2. 接口实现建议
   - /candy/balance
   - /candy/packages
   - /candy/orders
   - /candy/orders/{order_id}
   - /candy/transactions
3. 充值成功后的发糖逻辑
   - 首充赠送
   - 确认会员充值额外 20% 赠送已移除
   - 幂等处理
   - 重复回调保护
   - 余额与流水事务一致性
4. Apple IAP 接入建议
   - 是否复用会员 IAP 验证链路
   - 创建订单与 product_id 的映射策略
   - 验证成功后如何把苹果商品映射到 candy package

### iOS 客户端
请给出：
1. Model / API / Repository / ViewModel 新增建议
2. 钱包页至少需要的数据结构
3. 糖果充值页展示建议：
   - 当前余额
   - 首充标签
   - popular 标签
   - 实付价
   - 到账糖果数
4. 下单与支付流程：
   - 请求套餐列表
   - 选中 package
   - 创建订单
   - 根据 pay_channel 发起支付
   - 查询订单状态
   - 刷新余额
5. 流水页展示建议：
   - 收入 / 支出切换
   - 分页
   - 文案映射
6. 如何与会员模块共存，避免耦合混乱

---

## 任务 3：给出 App Store Connect 商品配置方案

请结合 `moodly-ios/App Store Connect Setup.md` 现有会员商品配置方式，新增糖果商品配置方案，并明确：

1. 糖果充值商品应该使用什么类型：
   - Consumable（消耗型内购）
   - 还是其他类型
2. product id 命名规则建议
3. 与服务端 package_id 的映射关系
4. 6 个糖果档位分别对应哪些 product id
5. 首充赠送放服务端算；会员充值额外 20% 赠送已移除，不能在 App Store Connect 或客户端表达
6. 如果会员和糖果都走 Apple IAP：
   - 客户端如何区分商品类型
   - 服务端如何区分校验后的发货逻辑
7. 是否需要新增文档：
   - `Candy IAP Setup.md`
   - 或直接补充现有 `App Store Connect Setup.md`

要求：
- 给出一份可直接执行的配置清单
- 包括每个商品的 product id / 显示名 / 价格档位 / 对应 package_id
- 明确指出：App Store Connect 无法表达“首充赠送”；会员充值额外 20% 赠送已移除，不要配置或实现

---

## 任务 4：直接产出代码改造建议

不要停留在架构口号，要输出接近可开发的改造清单。

### 服务端
请列出：
- 新增哪些 controller / route / service / model / migration
- 每个文件负责什么
- 哪些逻辑可复用会员代码
- 哪些逻辑必须拆分，避免污染会员购买逻辑

### iOS
请列出：
- 新增哪些 Swift 文件 / 目录
- 哪些现有支付封装需要抽象成通用层
- 哪些会员页面/逻辑可提炼复用
- 如果必要，给出伪代码或代码骨架

文件名可以参考但不限于：
- CandyAPI.swift
- CandyPackage.swift
- CandyOrder.swift
- CandyTransaction.swift
- CandyWalletViewModel.swift
- CandyRechargeViewModel.swift
- CandyService.swift
- CandyIAPManager.swift

---

## 任务 5：按下面结构输出最终结果

# A. 项目现状审查结果
- 服务端现状
- iOS 现状
- 可复用模块
- 缺失模块

# B. 糖果模块落地方案
- 数据结构
- 接口方案
- 支付链路
- 幂等与事务
- 会员充值加赠移除策略

# C. App Store Connect 配置方案
- 商品类型
- product id 设计
- package_id 映射
- 配置步骤
- 风险点

# D. 代码改造清单
- 服务端文件级改动建议
- iOS 文件级改动建议
- 公共层抽象建议

# E. 待确认问题
例如：
- 当前会员 IAP 验证是 App Store Server API 还是 receipt 校验
- 当前服务端是否已有通用资产流水表
- VIP 月赠 1000 糖果是否已实现
- iOS App Store 版本是否允许支付宝/微信入口展示

# F. 建议的下一步执行顺序
请按优先级给出务实的开发顺序

---

# 六、重要约束

1. 不要凭空编造项目已有能力，找不到就写“未发现”
2. 不要把首充赠送写死在 iOS，必须以后端接口结果为准；不要重新加入会员充值 20% 加赠
3. 不要让 iOS 硬编码价格
4. 如果 iOS 走 App Store 上架版本，数字内容充值优先按 Apple IAP 设计，并标注支付宝/微信在审核上的风险
5. 优先复用会员支付链路，但不要把糖果和会员写成一锅粥
6. 输出务必具体到文件、类、接口、字段，不要给 PPT 式空话

---

# 七、补充提醒

你可以直接在仓库中搜索：
- membership
- vip
- iap
- purchase
- order
- receipt
- StoreKit
- App Store Connect Setup.md
- wallet
- coin
- point
- gem
- balance

如果发现现有代码里已有 coin / point / gem / wallet / balance 之类模块，请优先评估可复用性，不要重复造轮子。

请基于代码审查结果回答，而不是只复述这份 PRD。
