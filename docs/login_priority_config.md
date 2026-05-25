# 登录页优先级配置

Status: current

Owner topic: login / App Store review / startup strategy config

## 1. 功能背景

Apple 审核反馈指出，未安装微信时用户可能无法继续登录。Moodly iOS 已支持手机号、Apple、微信三种登录方式，本功能通过服务端配置控制登录页主推荐入口，避免审核环境下微信成为主要或唯一登录路径；正式期可将微信作为首屏主按钮，手机号降级到底部“更多登录方式”折叠入口。

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
| `phone` | 审核/兜底样式：不把微信作为首屏主按钮，Apple 作为主按钮，手机号收在底部更多登录方式折叠入口。 |
| `wechat` | 正式样式：微信登录为首屏主按钮，Apple 与手机号收在底部更多登录方式折叠入口。 |

## 4. iOS 渲染规则

- `phone`: Apple 登录为首屏主按钮；手机号登录收在底部“更多登录方式”折叠入口，点击展开后显示图标；如 `wechat_login_entry_enabled=true` 且检测到微信已安装，微信也可在展开区显示。
- `wechat`: 微信登录为首屏主按钮；Apple 登录与手机号登录收在底部更多登录方式折叠入口，点击展开后显示图标。
- Apple 登录始终可见；微信为主按钮时，Apple 降级到底部图标；微信不可用或审核态隐藏微信时，Apple 回到主按钮。
- 手机号登录不再作为首屏大按钮，默认收在底部更多登录方式展开区里。
- iOS 额外读取 `data.ext.ios_feature_flags.phone_login_entry_enabled`；为 `false` 时隐藏手机号登录入口，并在点击路径上阻断打开手机号验证码流程。

## 4.1 Android 渲染规则

- Android 当前没有接入 `login_config.primary_login_method` 远程优先级。
- 微信登录保持首屏主按钮。
- 启动策略接口成功返回 `data.ext.android_feature_flags.phone_login_entry_enabled` 时，以远程值为准；为 `true` 时手机号登录收在底部“更多登录方式”折叠入口，点击展开后显示图标，为 `false` 时隐藏该入口。
- 启动策略接口失败或字段缺省时，回落到包内 `BuildConfig.DEFAULT_PHONE_LOGIN_ENTRY_ENABLED`。华为渠道包本地默认关闭手机号入口。
- 服务端当前对华为 `1.0.6`、`1.0.7`、`1.0.8` 内置提审态：`android_feature_flags.phone_login_entry_enabled=false`。iOS `1.0.7` 提审态关闭 `ios_feature_flags.phone_login_entry_enabled`，iOS `1.0.8` 提审态关闭 `ios_feature_flags.wechat_login_entry_enabled` 和 `ios_feature_flags.phone_login_entry_enabled`。

## 5. Fallback 策略

- 配置接口拉取失败：iOS 当前客户端使用本地 `LoginConfig.safeDefault`，现代码默认值为 `wechat`；审核期不要依赖失败 fallback，应由服务端明确下发审核态配置。
- 服务端返回非法值：服务端应按 `phone` 处理；iOS 客户端直接解析非法值时会回落到本地枚举兜底。
- 旧服务端未返回 `login_config`：iOS 客户端使用本地 `LoginConfig.safeDefault`。

## 6. 未安装微信时的降级策略

- 无论服务端配置是 `phone` 还是 `wechat`，iOS 都强制把 Apple 登录作为主入口；当 `phone_login_entry_enabled=true` 时，手机号保留在底部更多登录方式展开区。
- 登录页不展示微信主按钮或微信底部入口，避免审核设备点击后进入微信 SDK 拉起或安装引导链路。
- 如果运行过程中仍触发微信登录动作，客户端只展示提示：“当前设备未安装微信，你可以使用手机号或 Apple 登录继续。” 不调用微信授权启动。
- 微信可用性同时检查 SDK 安装状态和 `weixin://` 是否可打开，任一失败都按未安装处理。

## 7. 测试步骤

1. iOS 审核态：服务端配置 `LOGIN_PRIMARY_METHOD=phone` 且 `wechat_login_entry_enabled=false`，打开登录页，确认 Apple 为主按钮，点击底部“更多登录方式”后出现手机号图标，不出现微信入口。
2. iOS 正式态：服务端配置 `LOGIN_PRIMARY_METHOD=wechat` 且 `wechat_login_entry_enabled=true`，打开登录页，确认微信为主按钮，点击底部“更多登录方式”后出现 Apple 与手机号图标。
3. iOS 手机号关闭态：服务端配置 `STARTUP_STRATEGY_EXT={"ios_feature_flags":{"phone_login_entry_enabled":false}}`，打开登录页，确认底部更多登录方式不展示手机号图标。
4. 真机卸载微信后打开登录页，确认页面只保留 Apple 主按钮与手机号底部入口，不出现可点击微信入口。
5. Android 普通包打开登录页，确认微信为主按钮；远程 `phone_login_entry_enabled=true` 时点击底部“更多登录方式”后出现手机号图标。华为 `1.0.8` 提审包确认不展示手机号图标。
6. iPad Pro 11-inch / iPad Air 11-inch 审核环境检查登录按钮完整可见，不被协议区域、SafeArea 或弹窗高度遮挡。
7. 分别执行 Android 与 iOS 编译，确认项目正常构建。

## 8. App Store 审核注意事项

- 审核期建议保持 `LOGIN_PRIMARY_METHOD=phone`，并下发 `wechat_login_entry_enabled=false`。
- 不要隐藏 Apple 登录。
- 微信登录不能成为唯一入口。
- 未安装微信时登录页不展示微信登录入口，避免审核设备触发安装引导。
- 不要使用“必须安装微信才能登录”的表达。
- 如需过审后恢复微信优先，调整服务端环境变量为 `LOGIN_PRIMARY_METHOD=wechat` 且打开 `wechat_login_entry_enabled`，iOS 无需发版。
