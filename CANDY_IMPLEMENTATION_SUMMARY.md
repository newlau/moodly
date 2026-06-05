# 糖果模块实现总结

状态：historical implementation record（2026-06-05 已同步会员充值额外 20% 加赠移除口径）

## 已完成的工作

### 服务端（moodly_server）

✅ **数据库模型定义**
- 更新 `prisma/schema.prisma`：
  - User 表新增：`candyBalance`, `isFirstCandyRecharge`
  - Transaction 表新增：`label`, `balanceAfter`
  - 新增 CandyPackage 模型
  - 新增 CandyOrder 模型

✅ **糖果模块实现**
- `src/modules/candy/candy.schema.ts` - 请求验证 schema
- `src/modules/candy/candy.routes.ts` - 6 个接口路由
- `src/modules/candy/candy.service.ts` - 核心业务逻辑
  - getBalance() - 查询余额
  - getPackages() - 获取套餐（含首充赠送计算）
  - createOrder() - 创建订单
  - getOrderStatus() - 查询订单状态
  - getTransactions() - 查询流水（支持类型筛选）
  - verifyAndFulfill() - IAP验证和发糖

✅ **路由注册**
- 更新 `src/app.ts`，注册 `/v1/candy` 路由

✅ **初始数据**
- `prisma/seed_candy_packages.sql` - 6个糖果套餐配置

---

### iOS 端（moodly-ios）

✅ **IAPManager 更新**
- 已添加 `candyProductIDs`（5个商品）
- 已更新 `allProductIDs` 包含糖果商品

✅ **数据模型**
- `Bubbly/Models/Candy.swift`：
  - CandyPackage
  - CandyPackagesResponse
  - CandyOrder
  - CandyOrderStatus
  - CandyTransaction
  - CandyTransactionsResponse

✅ **服务层**
- `Bubbly/Services/CandyService.swift`：
  - fetchBalance()
  - fetchPackages()
  - createOrder()
  - verifyPurchase()
  - fetchOrderStatus()
  - fetchTransactions()

---

## 下一步操作

### 1. 数据库迁移（需要数据库运行）
```bash
cd ~/Desktop/moodly_server
npx prisma migrate dev --name add_candy_module
```

### 2. 导入初始数据
```bash
mysql -u root -p bubbly < prisma/seed_candy_packages.sql
```

### 3. 测试服务端接口
启动服务后测试：
- GET /v1/candy/balance
- GET /v1/candy/packages
- POST /v1/candy/orders
- GET /v1/candy/orders/:order_id
- GET /v1/candy/transactions

### 4. iOS UI 实现（后续）
- CandyRechargeView - 充值页面
- CandyRechargeViewModel - 充值逻辑
- CandyTransactionsView - 流水页面
- 更新 WalletView - 添加糖果入口

---

## 核心特性

✅ 首充赠送：服务端动态计算（1:1赠送）
✅ 会员充值额外 20% 加赠已移除，仅保留首充赠送
✅ 订单过期：30分钟自动过期
✅ 幂等处理：防止重复发货
✅ 事务保护：余额和流水一致性
✅ 流水筛选：支持 all/income/expense

---

## 注意事项

⚠️ 数据库迁移需要在数据库启动后执行
⚠️ App Store Connect 配置暂未进行（按计划先完成接口）
⚠️ iOS UI 页面需要后续实现
⚠️ 需要测试完整的购买流程
