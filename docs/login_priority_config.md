# 登录页优先级配置

Status: current

Owner topic: login / App Store review / startup strategy config

## 1. 功能背景

Apple 审核反馈指出，未安装微信时用户可能无法继续登录。Moodly iOS 已支持手机号、Apple、微信三种登录方式，本功能通过服务端配置控制登录页主入口，避免审核环境下微信成为主要或唯一登录路径。

## 2. 后端配置字段说明

复用主服务端已有启动策略接口：

- `GET /v1/app/startup-strategy`

响应 `data` 内新增：

```json
{
  "login_config": {
    "primary_login_method": "phone"
  }
}
```

服务端环境变量：

- `LOGIN_PRIMARY_METHOD=phone`
- `LOGIN_PRIMARY_METHOD=wechat`

默认值为 `phone`。缺省或非法值按 `phone` 返回。

## 3. 枚举值说明

| 值 | 含义 |
| --- | --- |
| `phone` | 优先展示手机号登录。 |
| `wechat` | 优先展示微信登录，保持原登录页顺序。 |

## 4. iOS 渲染规则

- `phone`: Apple 登录保留；手机号登录展示在原微信主按钮位置；微信登录移动到底部次级入口。
- `wechat`: 保持当前顺序，Apple 登录保留；微信登录为主入口；手机号登录在底部次级入口。
- Apple 登录始终可见，不受该配置影响。

## 5. Fallback 策略

- 配置接口拉取失败：客户端使用安全默认值 `phone`。
- 服务端返回非法值：服务端和客户端都按 `phone` 处理。
- 旧服务端未返回 `login_config`：客户端按 `phone` 处理。

## 6. 未安装微信时的降级策略

- 无论服务端配置是 `phone` 还是 `wechat`，iOS 都强制把手机号登录作为主入口。
- Apple 登录继续显示并可用。
- 登录页不展示微信主按钮或微信次级入口，避免审核设备点击后进入微信 SDK 拉起或安装引导链路。
- 如果运行过程中仍触发微信登录动作，客户端只展示提示：“当前设备未安装微信，你可以使用手机号或 Apple 登录继续。” 不调用微信授权启动。
- 微信可用性同时检查 SDK 安装状态和 `weixin://` 是否可打开，任一失败都按未安装处理。

## 7. 测试步骤

1. 服务端配置 `LOGIN_PRIMARY_METHOD=phone`，打开登录页，确认手机号为主入口、微信为底部次级入口、Apple 登录仍显示。
2. 服务端配置 `LOGIN_PRIMARY_METHOD=wechat`，打开登录页，确认页面保持微信优先样式，手机号仍在底部，Apple 登录仍显示。
3. 断开或模拟启动策略接口失败，确认登录页默认手机号优先且不崩溃。
4. 真机卸载微信后打开登录页，确认页面只保留手机号和 Apple 登录入口，不出现可点击微信入口。
5. iPad Pro 11-inch / iPad Air 11-inch 审核环境检查登录按钮完整可见，不被协议区域、SafeArea 或弹窗高度遮挡。
6. 分别执行服务端测试和 iOS 编译，确认项目正常构建。

## 8. App Store 审核注意事项

- 审核期建议保持 `LOGIN_PRIMARY_METHOD=phone`。
- 不要隐藏 Apple 登录。
- 微信登录不能成为唯一入口。
- 未安装微信时登录页不展示微信登录入口，避免审核设备触发安装引导。
- 不要使用“必须安装微信才能登录”的表达。
- 如需过审后恢复微信优先，只需调整服务端环境变量并重新发布服务端；iOS 无需发版。
