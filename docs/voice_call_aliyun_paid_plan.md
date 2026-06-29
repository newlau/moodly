# Moodly 阿里云复刻音色与语音通话付费闭环方案

状态：plan
Owner topic：voice / voice call / paid plan
调研日期：2026-06-11
适用范围：`/Users/liuyingying/Desktop/moodly`、`/Users/liuyingying/Desktop/moodly-chat-svr`、`/Users/liuyingying/Desktop/moodly_server`、`/Users/liuyingying/Desktop/moodly-dev-docs`

说明：本文是当前代码真相 + 阿里云官方价格/能力核对后的执行方案。真实代码、配置、日志和线上账单优先于旧文档。2026-06-17 已确认语音通话卡按秒计费、套餐按分钟展示、商品与音色卡独立。

## 1. 结论

我们自己复刻的音色应按阿里云音色资产处理，角色语音输出优先走阿里云 Qwen-TTS / CosyVoice provider，而不是把用户复刻音色映射成火山音色。

当前最稳的付费口径：

| 付费项 | 建议产品口径 | 当前/建议价格 | 说明 |
|---|---|---:|---|
| 保存一个复刻音色 | 音色卡 | 1 张音色卡 | 沿用当前 `VOICE_CARD_SAVE_COST=1` |
| 单张音色卡 | 消耗型商品 | ¥6 | 沿用当前 `voice_card_1 -> bubbly.voice_card.price_6` |
| VIP 月赠 | 会员权益 | 2 张/月 | 沿用当前常量 |
| SVIP 月赠 | 会员权益 | 4 张/月 | 沿用当前常量 |
| 普通语音消息/播放 | 糖果 | 3 糖果/次 | 沿用当前 voice billing launch cost |
| 语音电话 | 通话时长卡 + 糖果兜底 | 时长卡按秒扣；糖果兜底 100 糖果/分钟按秒折算 | 新增 `voice_call_seconds` / `voice_call_tick`，不复用音色卡 |

最小闭环不建议一上来做真全双工电话。先做“通话壳 + 分段说话 + 阿里云复刻音色回复”的 P0：

```text
用户点电话
-> 全屏通话 UI
-> 用户按住说话或自动录一小段
-> 上传音频 + ASR 得到文本
-> 走现有 chat-svr reactive ingress / generate_reply
-> 角色回复文本
-> 使用该角色绑定的阿里云复刻 voice_id 做 TTS
-> 播放角色语音
-> 按 tick 扣糖果
-> 挂断后写回通话摘要
```

这样能复用当前聊天链路和音色资产，先验证付费、体验、延迟和内容安全。后续再升级到 WebSocket 实时 ASR + Qwen-TTS-VC-Realtime 流式播放。

## 2. 扫描范围

### 2.1 本地代码与文档

- `AGENTS.md`
- `/Users/liuyingying/Desktop/moodly-dev-docs/README.md`
- `/Users/liuyingying/Desktop/moodly-dev-docs/chat-execution-standard.md`
- `/Users/liuyingying/Desktop/moodly-dev-docs/voice/voice-feature-research.md`
- `/Users/liuyingying/Desktop/moodly-chat-svr/.docs/chat-pipeline.md`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/config/env.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/infra/qwen-voice-clone.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/infra/volc-tts.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/modules/voice/service.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/modules/voice/billing.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/prisma/schema.prisma`
- `moodly-ios/Bubbly/Services/ChatVoiceTranscriber.swift`
- `moodly-ios/Bubbly/ViewModels/ChatDetailViewModel.swift`
- `moodly_android/app/src/main/java/com/yuewei/moodly/ui/chat/ChatDetailViewModel.kt`
- `docs/ios_server_payment_linkage.md`

### 2.2 官方资料

- 阿里云百炼模型价格：https://help.aliyun.com/zh/model-studio/model-pricing
- 阿里云声音复刻：https://help.aliyun.com/zh/model-studio/voice-cloning-user-guide
- 阿里云实时语音合成：https://help.aliyun.com/zh/model-studio/realtime-tts-user-guide
- 阿里云语音合成模型说明：https://help.aliyun.com/zh/model-studio/tts-model/

## 3. 当前真相

### 3.1 现有音色与复刻链路

chat-svr 现在已经有账号级音色资产和复刻任务：

- `Voice` 表有 `provider`、`provider_voice_id`、`provider_speaker_id`、`owner_user_id`、`status`。
- `VoiceCloneJob` 表有素材、provider task、provider speaker、试听音频、保存后的 voice id。
- `VoiceCardLedger` 记录音色卡流水。
- `VOICE_CLONE_PROVIDER` 当前只支持 `cosyvoice` / `qwen`，默认 `cosyvoice`。
- `DASHSCOPE_VOICE_API_KEY` 会回退使用 `DASHSCOPE_API_KEY`。
- Qwen 复刻默认模型是 `qwen-voice-enrollment`。
- Qwen 克隆 TTS 默认目标模型是 `qwen3-tts-vc-2026-01-22`。
- CosyVoice 默认 TTS 模型是 `cosyvoice-v3.5-plus`。

关键代码：

- `/Users/liuyingying/Desktop/moodly-chat-svr/src/config/env.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/infra/qwen-voice-clone.ts`
- `/Users/liuyingying/Desktop/moodly-chat-svr/src/modules/voice/service.ts`

### 3.2 角色语音输出已经能按 provider 分流

`/Users/liuyingying/Desktop/moodly-chat-svr/src/infra/volc-tts.ts` 虽然文件名是 `volc-tts`，但实际已经做了 TTS target resolve：

- 原始火山 speaker id：走 `volc_tts`。
- `qwen-*` 或 `Voice.provider = qwen_voice_clone`：走 `qwen_tts`。
- `cosyvoice-*` 或 `Voice.provider = cosyvoice_clone`：走 `cosyvoice_tts`。

所以如果角色绑定的是用户自己复刻的阿里云音色，服务端不需要把它改成火山音色；只要 `Voice.provider` 和 `providerSpeakerId` 正确，助手语音消息可走阿里云 TTS。

### 3.3 当前语音消息链路不是电话

当前 App 语音消息是：

```text
录音
-> /chat/v1/upload/audio
-> /chat/v1/chats/:id/messages content_type=voice
-> reactive ingress
-> generate_reply
-> 可选 assistant voice message
```

它是“录完整段再发”的消息链路，不是实时电话。

双端当前差异：

- iOS 已在 `sendVoiceRecording` 中并发上传和本地 Apple Speech 转写，会把 `asr_text` / `local_asr_text` / `recognized_text` 发给 chat-svr。
- Android 当前只上传音频并发 `[语音]`，`extra.asr_status=server_processing`，没有实际本地 ASR 文本。
- chat-svr 服务端 ASR 默认关闭，`VOICE_SERVER_ASR_ENABLED=false`；打开后可通过 `VOICE_ASR_PROVIDER=volc|aliyun` 切火山或阿里云。
- Android 若不补本地 ASR，可以直接走服务端阿里云 ASR：`VOICE_ASR_PROVIDER=aliyun` + `DASHSCOPE_ASR_API_KEY`。

### 3.4 当前付费与权益

代码常量在 `/Users/liuyingying/Desktop/moodly-chat-svr/src/modules/voice/billing.ts`：

| 常量 | 当前值 | 含义 |
|---|---:|---|
| `VOICE_MESSAGE_CANDY_COST` | 3 | 语音消息 launch cost |
| `VOICE_PLAYBACK_CANDY_COST` | 3 | 角色语音播放扣费 |
| `VOICE_CARD_SAVE_COST` | 1 | 保存复刻音色消耗 1 张音色卡 |
| `VIP_MONTHLY_VOICE_CARDS` | 2 | VIP 月赠音色卡 |
| `SVIP_MONTHLY_VOICE_CARDS` | 4 | SVIP 月赠音色卡 |
| `VOICE_CARD_UNIT_PRICE_CNY` | 6 | 单张音色卡展示价 |

支付文档 `docs/ios_server_payment_linkage.md` 当前口径：

- `voice_card_1`
- `voice_card_amount = 1`
- `price_cny = 6`
- `apple_product_id = bubbly.voice_card.price_6`
- 其他 `price_3 / 9 / 12 / 15 / 18` 只是候选，不是线上展示。

## 4. 阿里云官方费用核对

以下价格为 2026-06-11 从阿里云百炼模型价格页核对，最终仍以阿里云控制台账单为准。

### 4.1 复刻音色

| 模型 | 计费方式 | 中国内地价格 | 免费额度 |
|---|---|---:|---|
| `qwen-voice-enrollment` | 按新建音色个数 | ¥0.01 / 个音色 | 开通后 90 天内 1000 个音色/账号 |

说明：

- 这是 Qwen-TTS 声音复刻的明确官方价格。
- 当前代码中的 Qwen provider 正好使用 `qwen-voice-enrollment`。
- 若线上实际走 CosyVoice 复刻，官方页面没有在同一价格表里给出独立“每个复刻音色”单价；需以 DashScope 控制台账单复核，不应凭猜测写入产品价。

### 4.2 阿里云复刻音色 TTS

| 模型 | 场景 | 计费方式 | 中国内地价格 |
|---|---|---|---:|
| `qwen3-tts-vc-2026-01-22` | 非实时复刻音色 TTS | 按输入文本字符数 | ¥0.8 / 万字符 |
| `qwen3-tts-vc-realtime-2026-01-15` | 实时复刻音色 TTS | 按输入文本字符数 | ¥1 / 万字符 |
| `cosyvoice-v3.5-plus` | CosyVoice 高质量 TTS | 按输入文本字符数 | ¥1.5 / 万字符 |
| `cosyvoice-v3.5-flash` | CosyVoice 快速 TTS | 按输入文本字符数 | ¥0.8 / 万字符 |

### 4.3 阿里云 ASR

| 模型 | 场景 | 计费方式 | 中国内地价格 |
|---|---|---|---:|
| `qwen3-asr-flash` | 文件/非实时 ASR | 按输入音频秒数 | ¥0.00022 / 秒 |
| `qwen3-asr-flash-realtime` | 实时 ASR | 按输入音频秒数 | ¥0.00033 / 秒 |
| `paraformer-realtime-v2` | 实时 ASR 低价选项 | 按输入音频秒数 | ¥0.00024 / 秒 |

### 4.4 估算单分钟服务商成本

粗算仅用于产品定价参考，不等于真实毛利。假设 1 分钟电话内用户说话 30 秒、角色回复 80 个中文字符：

```text
ASR：30 秒 * 0.00033 = ¥0.0099
TTS：80 / 10000 * 1 = ¥0.008
阿里云语音直接成本约 ¥0.018 / 分钟
```

还未计入：

- LLM generate_reply 成本。
- 服务端带宽、对象存储、CDN。
- App Store / 支付通道手续费。
- 失败重试、审核、风控、客服和坏账。
- 用户实际说话时长和角色回复长度波动。

结论：服务商语音成本很低，产品定价不应按“成本加一点点”设计，而应按付费心智、滥用防护、体验价值和现有糖果体系设计。

## 5. 付费方案

### 5.1 音色卡：只管“保存音色”

继续沿用当前方案：

```text
1 张音色卡 = 保存 1 个复刻音色
单张音色卡 = ¥6
VIP 每月赠 2 张
SVIP 每月赠 4 张
```

推荐流程：

1. 用户上传或录制样本。
2. 服务端创建 `VoiceCloneJob`。
3. 生成试听音频，试听不扣音色卡。
4. 用户点“保存音色”时检查音色卡余额。
5. 保存成功后扣 1 张音色卡，写 `VoiceCardLedger`。
6. 失败不扣卡；provider 已产生的小额成本由平台承担，并受每日尝试次数限制。

不建议：

- 不要把“打电话分钟数”消耗音色卡。
- 不要把 provider 的 ¥0.01 复刻成本直接展示给用户。
- 不要在 App 里展示多档音色卡，除非服务端商品列表正式灰度。

### 5.2 语音消息：沿用 3 糖果

当前已有语音消息和角色语音播放 3 糖果口径，可以继续：

- 用户发语音：3 糖果。
- 播放角色语音：3 糖果。
- 失败或加载失败按现有 refund 逻辑退还。

这部分不要和电话计费混在一起。

### 5.3 语音电话：新增通话时长卡与通话 tick

已确认口径：

```text
voice_call_seconds_purchase
voice_call_tick
```

通话卡是独立于音色卡的付费资产，余额单位统一按秒存储和扣减，客户端展示为分钟。现有 `voice_card_1`、`voice_card_ledger` 仍只代表“保存复刻音色”，不能被通话分钟复用。

首批通话时长卡：

| package_id | 展示时长 | 入账秒数 | 价格 | Apple Product ID |
|---|---:|---:|---:|---|
| `voice_call_minutes_20` | 20 分钟 | 1200 秒 | ¥6 | `bubbly.voice_call.minutes_20` |
| `voice_call_minutes_90` | 90 分钟 | 5400 秒 | ¥18 | `bubbly.voice_call.minutes_90` |
| `voice_call_minutes_300` | 300 分钟 | 18000 秒 | ¥38 | `bubbly.voice_call.minutes_300` |
| `voice_call_minutes_1000` | 1000 分钟 | 60000 秒 | ¥98 | `bubbly.voice_call.minutes_1000` |

计费规则：

- 开始通话时优先消耗通话秒数余额。
- 通话秒数不足时允许糖果兜底，按 `100 糖果 / 分钟` 换算为 `5/3 糖果 / 秒`；服务端按实际消耗秒数向上取整扣糖。
- VIP 每月赠送 30 分钟通话时长，SVIP 每月赠送 90 分钟通话时长；不打折。会员月赠写入独立 `voice_call_credit_ledger`，reason 为 `membership_monthly_grant`，不复用音色卡月赠。
- 断线、首包失败、provider 失败或没有产生有效通话消耗时不扣。
- 钱包明细必须记录“和谁通话”：至少包含 `session_id`、`chat_id`、`character_id`、`character_name`、`duration_seconds`、`payment_source`。

## 6. 最小闭环方案

### 6.1 P0：通话壳 + 分段语音，最快上线验证

P0 的核心是“看起来像通话，但技术上仍是分段语音消息”。它不是最终电话形态，但最小、可控、能收费。

客户端：

1. 聊天页新增电话入口，受 `voice_call_enabled` 控制。
2. 进入全屏通话页。
3. 显示角色头像、昵称、状态、时长、糖果消耗、挂断按钮。
4. 用户按住说话，或自动录 3 到 8 秒一段。
5. 上传音频。
6. 拿到角色语音回复后立即播放。
7. 挂断后回到聊天页，插入通话摘要。

服务端：

1. `POST /chat/v1/chats/:id/voice-call/sessions` 创建 session。
2. 复用 `/chat/v1/upload/audio` 上传音频。
3. 复用 `/chat/v1/chats/:id/messages` 或新增内部 call-turn 入口。
4. 每段用户语音必须得到文本后再进 `generate_reply`。
5. 回复规划强制 call mode：单句、口语、短回复、禁图片/贴纸/复杂动作。
6. 用角色 `voice_id` 解析到阿里云 provider speaker。
7. 非实时阶段可先用 `qwen3-tts-vc-2026-01-22` 生成完整音频。
8. 每 30 秒扣一次 `voice_call_tick`。
9. session 结束写通话摘要。

P0 必须补的缺口：

- Android 需要 ASR。当前 chat-svr 已支持阿里云 DashScope/Qwen ASR provider，配置 `VOICE_ASR_PROVIDER=aliyun` 后聊天语音和 voice-call turn 都可走服务端阿里 ASR。
- iOS 已有 Apple Speech 转写，但电话场景为了双端一致，最好最终也走服务端 ASR 或至少把 provider 差异写入 trace。
- chat-svr 需要新增 call session 和计费 tick，不能只靠普通 message id。

2026-06-17 当前执行记录：

- chat-svr 已补 P0 call-turn 入口：`POST /chat/v1/voice-call/sessions/:session_id/turns`。
- turn body 先接外部 ASR 文本：`asr_text` / `transcript` / `text`，可附带 `asr_confidence`、`media_url` / `audio_url`、`audio_b64`、`mime_type`、`duration`、`client_message_id`。
- turn 内部复用现有聊天链路：`storeReactiveUserMessage -> executeReactiveInteractionFlow -> core interaction -> generate_reply -> writeback/realtime`。
- turn 使用独立 prompt：`chat/generate_reply_voice_call`，规则是实时通话短句、可朗读、禁图片、禁贴纸、禁复杂动作。
- turn 强制角色回复走 TTS：服务端把 prompt 产出的 `$[text]` 气泡转为 assistant `voice`，不受普通聊天 `voice_frequency` 随机频次影响。
- session 创建响应已返回当前角色音色配置摘要：`tts.voice_id`、`provider`、`speaker_id`、`resource_id`、`status`。
- TTS 当前支持两种路径：
  - 配置 `VOICE_CALL_STREAM_TTS_BASE_URL` 后，通话 turn 使用自建 stream TTS：`POST /v1/audio/speech/stream`，把角色 `voice_id` 作为上游 `voice_id`，返回 WAV 后上传为 `tts.media_url`。
  - 未配置 stream TTS 时，仍复用 `moodly-chat-svr/src/infra/volc-tts.ts` 的统一 target resolve：角色 `voice_id` 可解析到 `qwen_tts` / `cosyvoice_tts` / `volc_tts`。
- 新增服务端健康检查包装：`GET /chat/v1/voice-call/tts/health`，内部检查上游 `GET /health` 返回的 `{status:"ok"}`。
- 通话 turn 作为 trusted server route 跳过普通聊天“语音消息按条扣糖”，只保留通话 session 秒级计费。
- 当前仍不是最终全双工实时流式电话：P0 先把 stream TTS 的 WAV 响应缓存并上传；Pipecat 后续需要把 STT final transcript 调这个 turn 接口，再升级为 WS + ASR/TTS chunk 直传客户端播放。

2026-06-25 静默追话/自动告别客户端兼容记录：

- iOS / Android 客户端已在“助手 TTS 播放结束”后启动通话内静默阶段计时，不从接口返回时开始计时。
- 阶段值按 `followup_5s`、`followup_30s`、`goodbye_60s` 兼容；客户端按约定调用 `POST /chat/v1/voice-call/sessions/:session_id/idle-turn`，body 为 `{ "stage": "..." }`，期望返回 `audio/wav` stream，并继续读取 `X-Voice-Call-Tts-Text-B64` 作为展示文本。
- 用户开始说话、打断角色播放、提交新一轮语音、挂断、重载或续时阻塞时，客户端取消当前静默计时；每个阶段在同一段静默链路内只触发一次。
- `goodbye_60s` 音频播放完成后，客户端主动结束通话，并用 `end_reason=idle_goodbye_60s` 调 session end。
- `moodly-chat-svr` 已实现 `POST /chat/v1/voice-call/sessions/:session_id/idle-turn` 与 `/idle-turn/audio-stream`；联调时需要继续用真实接口响应和日志复核响应头、realtime 写回和 session 静默结束标记是否一致。

2026-06-25 自动打断降敏客户端记录：

- 当前 iOS / Android P0 仍是本地电平门控，不是真正 VAD / 声纹识别。
- 已把“角色 TTS 播放中第一帧达到音量阈值就打断”改为“连续达到打断阈值并满足最短持续时间后才停 TTS”。
- 2026-06-26 根据真机反馈“太难打断”回调到中间档：iOS / Android barge-in 监听延后从 900ms 调到 600ms；确认门限从约 480ms、4 帧调到约 320-340ms、3 帧；同时适当放低播放中起始/持续音量阈值。目标是保留连续确认，避免回到“一响就断”，但让短句插话更容易触发。
- iOS 继续使用系统 voice processing；Android TTS 播放期间继续优先使用 `VOICE_COMMUNICATION` 音源。Android 已在 `VoiceCallLoop` 日志输出本次捕获窗口阈值；iOS DEBUG 构建会输出 `VoiceCallBargeIn` 窗口、确认和丢弃信息，便于真机调试。
- 后续如仍有误触发，应优先接入真正 VAD（仅判断人声）作为 `音量门限 + VAD speech + 持续时间` 的组合条件；“熟悉的人声/声纹”属于更高风险能力，需要单独隐私授权、声纹注册/删除流程和产品开关，不纳入当前 P0 打断可用性修复。

2026-06-26 自动打断声纹保护客户端/服务端记录：

- 因实时语音成本较高，iOS / Android 已把“自动开口打断”改成声纹保护状态机：播放中本地音量门限只产出 barge-in candidate，不再立即停止角色 TTS；候选录音结束后先调用声纹验证接口，只有返回允许后才停止 TTS 并提交通话 turn。
- 客户端约定接口：`POST /chat/v1/voice-call/sessions/:session_id/voiceprint/verify`，body 包含 `audio_b64`、`mime_type` / `audio_mime_type`、`duration` / `audio_duration_seconds`、`stage: "barge_in"`、`client_version`。期望响应包含 `allowed`，可选 `matched`、`confidence`、`threshold`、`mode`、`reason`。客户端要求 `allowed=true`，且当 `matched=false` 时强制拒绝。
- `moodly-chat-svr` 已新增服务端控制层：`VOICE_CALL_VOICEPRINT_MODE=deny_all|allow_all|audio_gate|remote`。非生产未配置时默认 `audio_gate` 方便联调；生产未配置时默认 `deny_all` 保护成本；`allow_all` 只用于看打断体验；`remote` 会把候选音频转发到 `VOICE_CALL_VOICEPRINT_VERIFY_URL`。
- 当前 `audio_gate` 只是服务端轻量音频门控（按候选音频字节数和时长），不是真正声纹识别；真实声纹仍需要外部服务、注册/更新/删除、隐私授权、数据留存和阈值策略单独补齐。接口未上线、失败或返回 false 时，客户端会丢弃自动打断候选；用户点击“插话”仍保留即时打断。

2026-06-27 Android 客户端 WebRTC VAD 门控记录：

- Android 实时语音通话已把通话录音从 `MediaRecorder` 电平采样切到 `AudioRecord` PCM 采样，并以 `audio/wav` 通过原有 `audio_b64 + mime_type` 字段提交，不改变 voice-call API path / 字段语义。
- Android 播放中自动打断前新增客户端 WebRTC VAD 门控：依赖 `com.github.gkonovalov.android-vad:webrtc:2.0.9`，参数为 `16kHz / frameSize=320 / VERY_AGGRESSIVE`。`2.0.10` 会拉入 Kotlin 2.2 stdlib，与当前 Android Kotlin 2.0.21 不兼容，故先固定 2.0.9。
- 自动打断必须同时满足音量阈值、WebRTC VAD speech frame、连续帧数和最短持续时间，才进入 barge-in 候选；普通聆听阶段也复用 WebRTC VAD 门控，拍手/敲击等非人声高能量输入不会直接进入“用户开始说话”。若 WebRTC VAD 初始化或单帧执行失败，则回退到本地 RMS / 过零率 / crest factor 兜底门控。
- Android 录音会优先使用 `VOICE_COMMUNICATION` 音源，并启用系统可用的 AEC / NS / AGC 音频处理；高能量但 WebRTC VAD 判非 speech 的帧会输出 `VoiceCallLoop: listen non-voice frame ignored` 或 `VoiceCallLoop: barge-in non-voice frame ignored` 日志，便于真机调阈值。
- 这是客户端人声活动检测，不是熟人声纹识别。WebRTC VAD 只判断“是否有人声”，不会判断“是不是当前用户本人”；声纹/本人识别仍需服务端 speaker verification、隐私授权、注册/删除和阈值策略。
- 打断候选录音在确认用户人声开始时会丢弃此前捕获的音频，避免把角色外放 TTS、前置静音和误触片段一起提交给后端，减少打断后 `让我想想` 等待过长和 ASR 误识别。

2026-06-29 Android 发版阻断修复记录：

Status: current。

- 麦克风按钮改为纯“打开麦克风 / 关闭麦克风”语义；关闭麦克风只停止用户采集和提交，不影响角色语音播放，也不再承担“插话”按钮职责。
- 扬声器路由改为通话路由：播放使用 `USAGE_VOICE_COMMUNICATION`，页面进入后保持 `MODE_IN_COMMUNICATION`；检测到有线耳机、蓝牙或 USB/助听输出时不强制外放，拔掉后默认回到扬声器。
- Android P0 自动打断临时取消声纹强依赖：本地 WebRTC VAD + 音量/持续时间确认人声后立即停止角色播放并继续录完本轮用户语音；候选录音仍通过现有 voice-call turn 提交给服务端 ASR，服务端 no-speech 只作为兜底，不生成新回复。`voiceprint/verify` 接口保留给后续风控，但当前不作为发版放行条件。
- 声纹后续方案单独做：需要用户授权、注册/删除、服务端 speaker verification、阈值策略和失败降级；在这些流程补齐前，不能让未上线/返回 false 的声纹接口阻断付费通话体验。
- 发版前真机验收顺序：无耳机默认扬声器播放；插入有线耳机/蓝牙后走耳机；麦克风关闭时不采集、不提交 turn；角色说话时用户正常开口可自动打断；拍手/敲击等非人声不应频繁打断；通话结束仍调用 session end 并返回摘要。

2026-06-29 iOS 同步记录：

Status: current。

- iOS `VoiceCallMockView` 已同步同一产品口径：麦克风按钮只负责“打开麦克风 / 关闭麦克风”，不再在角色说话时变成“插话”。
- iOS 输出路由复用一份当前输出判断：有线耳机、蓝牙、USB、车载或 AirPlay 输出存在时显示“耳机”并取消强制外放；无外接输出时默认扬声器，用户可手动关闭扬声器。
- iOS 自动打断不再调用 `voiceprint/verify` 作为 P0 放行条件；本地峰值、平均能量、持续时间和连续帧确认人声后立即停止角色播放，候选录音提交给服务端 ASR，服务端 no-speech 只作为兜底，不生成新回复。`MessageService.verifyVoiceCallBargeInVoiceprint` 保留给后续真实声纹方案。
- iOS 录音和流式播放的 `AVAudioSession` 选项补齐 `allowBluetoothA2DP` / `allowBluetoothHFP`，避免耳机/蓝牙场景被录音或播放会话抢回外放。

2026-06-29 拍手误打断修复记录：

Status: historical。最新热麦阈值、pre-roll 与 `interrupted_*` 上下文契约见下方“豆包式自动打断与上下文修复记录”。

- 根因：上一版客户端在本地 barge-in candidate 确认后就停止角色播放；拍手/敲击等高能量噪声可能先造成“听感已被打断”，即使服务端随后返回 no-speech，也已经破坏通话体验。
- 修正口径：不能等服务端返回才打断，否则用户开口体感像“没有自动打断”。客户端必须在本地确认连续人声后立即停止旧播放；服务端 `ASR_NO_SPEECH`、静音、无有效语音或候选请求失败只负责丢弃本轮候选，不生成新回复。
- Android 依赖 WebRTC VAD + 音量/持续时间确认人声；stream 与 legacy 兜底都带 `wasBargeIn` 语义。非 stream fallback 的 422 no-speech 也统一映射成 `VoiceCallNoSpeechException`。
- iOS 同步立即打断，并把播放中插话候选调整为约 480ms / 5 帧 / 560ms post-silence，同时增加平均能量门控，减少单次拍手峰值被当成人声候选的概率。
- 服务端现状已能把 ASR 客户端静音/无效音频映射为 `ASR_NO_SPEECH`，且过滤部分 ASR 幻觉文本；P0 暂不新增接口。若后续追求更低延迟，可增加 ASR-only `barge-in/validate` 接口，返回 `{accepted, transcript, confidence}` 后客户端再停播并复用 transcript 生成回复。

2026-06-29 远距离开口与静默追问修复记录：

Status: historical。静默追问结论仍适用；最新热麦阈值与打断上下文见下方“豆包式自动打断与上下文修复记录”。

- 真实通话口径：用户不应必须贴着麦克风说话。Android 普通聆听与播放中插话都降低音量门限，继续用 WebRTC VAD / 声学特征判断人声；iOS 普通聆听降低 peak 门限，播放中插话降低 peak + average 门限。
- Android 插话当前约 `520ms / 5 帧` 即可确认人声并立即停播；iOS 插话当前约 `440ms / 5 帧`，同时要求平均能量满足门槛。
- 静默追问修复：用户轻声/远距离说话触发过“用户开始说话”后，如果录音最终被丢弃、编码为空、服务端返回 `ASR_NO_SPEECH` 或提交失败，客户端会重新启动静默追问计时。避免计时被一次无效候选取消后永远不追问。
- 验收重点：离手机更远自然说一句应能进入用户回合；角色说话时远一点插话应打断；完全不说话 5 秒左右应触发第一句追问，后续约 30 秒追问，再到 60 秒自动告别。

2026-06-29 豆包式自动打断与上下文修复记录：

Status: current。

- 当前发版口径是“本地确认人声后立即停旧播放，录完这句话后作为打断 turn 提交”，不是点击插话，也不是等待服务端 ASR 后才停播。
- 服务端现有 `/turns` 与 `/turns/audio-stream` 已支持打断上下文：`interrupted_assistant_message_id`、`interrupted_played_text`、`interrupted_played_char_count`、`interrupted_played_segment_count`。客户端读取 `X-Voice-Call-Assistant-Message-Id` 和 `X-Voice-Call-Tts-Text-B64`，在打断瞬间按播放耗时估算已播字符数并随下一轮用户音频提交；服务端据此排除未播完的旧 assistant 回复，并把已播片段作为上下文注入。
- Android 播放中热麦延迟保持约 `180ms`，但停播确认收紧到约 `440ms / 4 帧`，继续要求 WebRTC VAD + 音量 + RMS / 过零率 / crest factor 兜底声学特征共同成立；确认用户人声开始时回退到最近 `420ms` pre-roll，保住第一句话开头。若 TTS 正好自然结束但用户已经开口，`onAssistantPlaybackFinished` 不再递增 `userCaptureNonce` 取消当前捕获；同一个捕获窗口会从“打断阈值”自动降回“普通聆听阈值”，轻声接话也能作为下一轮提交。
- iOS 播放中热麦延迟保持约 `180ms`，停播确认收紧到约 `460ms / 5 帧`；除 peak / average 能量外增加 peak-average spread 与短间隙 reset，降低拍手、敲击等瞬态高能量输入误打断概率。播放中的被动热麦不再重新配置 `AVAudioSession`，避免角色 TTS 被录音会话打断或产生停顿；若角色语音自然结束时用户已经在说话，当前候选继续收尾并作为普通下一轮提交。
- 服务端补齐 no-speech 兜底：当 voice-call turn 携带音频但 ASR provider 成功返回空文本时，也统一抛 `ASR_NO_SPEECH`，与供应商静音错误、客户端静音和 ASR 幻觉过滤同一恢复路径，避免客户端卡在普通失败分支。
- 仍保留 `voiceprint/verify` 接口给后续本人声纹风控，但当前 P0 不以声纹作为可用性前置条件；否则未完成注册/授权/删除/阈值策略前会阻断付费通话。
- 真机验收优先级：角色长句播放中自然说“等一下我想问...”应在约半秒内停旧播放，并且 ASR 能拿到句首；连续拍手、敲桌、咳嗽不应稳定打断；耳机/Bluetooth 下不强制外放；麦克风关闭后不再采集打断候选。

### 6.2 P1：半双工实时电话

P1 开始做真正实时链路：

```text
client audio stream
-> chat-svr voice-call WS
-> Aliyun ASR-Realtime
-> final transcript
-> existing core interaction / generate_reply
-> Qwen-TTS-VC-Realtime
-> audio chunks back to client
```

新增接口建议：

```text
POST /chat/v1/chats/:id/voice-call/sessions
GET  /chat/v1/chats/:id/voice-call/sessions/:sessionId
POST /chat/v1/chats/:id/voice-call/sessions/:sessionId/end
WS   /chat/v1/ws/voice-call?session_id=...
```

WS 事件建议：

| 方向 | event | 说明 |
|---|---|---|
| client -> server | `audio.chunk` | PCM/Opus 音频片段 |
| client -> server | `audio.commit` | 用户本句结束 |
| client -> server | `interrupt` | 打断角色播放 |
| client -> server | `hangup` | 挂断 |
| server -> client | `session.ready` | 通话就绪 |
| server -> client | `asr.partial` | 临时转写 |
| server -> client | `asr.final` | 最终转写 |
| server -> client | `assistant.thinking` | 角色思考中 |
| server -> client | `tts.audio.delta` | 角色音频流 |
| server -> client | `assistant.final_text` | 角色最终文本 |
| server -> client | `billing.tick` | 扣费状态 |
| server -> client | `session.ended` | 通话结束 |

### 6.3 P2：打断和拟真电话

P2 再做体验增强：

- VAD 自动判断用户是否说完。
- 用户说话时打断当前 TTS。
- 角色“正在听/正在想/正在说”状态更细。
- 断线恢复 session。
- 长通话摘要与记忆写回。
- 服务端按 trace 记录 ASR、LLM、TTS 首包延迟。

## 7. 数据与服务边界

### 7.1 新增表建议

```text
voice_call_sessions
- id
- chat_id
- user_id
- character_id
- status
- provider
- voice_id
- provider_speaker_id
- started_at
- ended_at
- duration_ms
- charged_candy
- first_audio_at
- error_code
- summary_message_id
- created_at
- updated_at
```

```text
voice_call_turns
- id
- session_id
- interaction_id
- user_asr_text
- assistant_text
- tts_media_url
- asr_provider
- tts_provider
- provider_log_id
- latency_json
- created_at
```

### 7.2 服务边界

chat-svr 负责：

- 通话 session。
- ASR/TTS provider 编排。
- core interaction / generate_reply。
- 通话 tick 扣糖果。
- trace 和摘要写回。

moodly_server 负责：

- 音色卡商品。
- IAP/支付宝订单。
- 会员月赠音色卡。
- 钱包和商品展示口径。

不要让主业务服旧 `/v1/voices` mock 文档成为电话 runtime 的 owner。

## 8. Provider 选择

### 8.1 复刻音色与角色输出：阿里云优先

因为用户自己的复刻音色属于阿里云，角色输出应优先使用：

- `qwen_voice_clone` + `qwen_tts`
- 或 `cosyvoice_clone` + `cosyvoice_tts`

建议把生产复刻 provider 明确配置为：

```text
VOICE_CLONE_PROVIDER=qwen
QWEN_VOICE_CLONE_MODEL=qwen-voice-enrollment
QWEN_TTS_VC_MODEL=qwen3-tts-vc-2026-01-22
```

本轮接入的自建通话 TTS stream 接口：

```text
VOICE_CALL_STREAM_TTS_BASE_URL=https://u1025309-8174-fcd16e47.westc.seetacloud.com:8443
VOICE_CALL_STREAM_TTS_CFG_VALUE=2.0
VOICE_CALL_STREAM_TTS_TIMEOUT_SECONDS=300
VOICE_CALL_STREAM_TTS_HEALTH_TIMEOUT_SECONDS=5
```

上游契约来自本轮 `API.md`：

- `GET /health`：200 JSON，`status=ok` 表示上游可用。
- `POST /v1/audio/speech/stream`：JSON body 使用 `input`、`voice_id`、`cfg_value`，成功返回 `Content-Type: audio/wav` 的 WAV stream。
- 当前服务端 P0 会缓存完整 WAV 后上传，返回普通聊天语音泡可播放的 `media_url`；P1 再改为把音频 chunk 直接推给通话客户端。

实时电话阶段再补：

```text
QWEN_TTS_VC_REALTIME_MODEL=qwen3-tts-vc-realtime-2026-01-15
ALIYUN_ASR_REALTIME_MODEL=qwen3-asr-flash-realtime
```

非实时 P0 ASR 已支持：

```text
VOICE_SERVER_ASR_ENABLED=true
VOICE_ASR_PROVIDER=aliyun
DASHSCOPE_ASR_API_KEY=...
DASHSCOPE_ASR_MODEL=qwen3-asr-flash
```

实时 `qwen3-asr-flash-realtime` 仍是后续 WS/chunk 阶段配置方向。

### 8.2 火山的角色

火山现在仍可保留：

- 官方预设音色。
- 已有 `S_*` speaker id 的旧角色。
- 现有火山 ASR 作为 `VOICE_ASR_PROVIDER=volc` 的兜底选项。

但用户自己复刻音色不应再新建到火山，除非产品明确要双 provider 音色资产。

## 9. 风控与合规

必须做到：

- 用户上传复刻样本前展示授权确认。
- 保存音色前明确“这是私人音色，不随角色码传播”。
- 删除音色时解除角色绑定，并尽量删除服务商侧音色或至少标记不可用。
- 角色码导出不得包含用户克隆音色 provider speaker id。
- 通话原始音频 chunk 不长期保存；只保留最终 transcript、摘要和必要 trace。
- ASR final 文本进入现有敏感词/输入审核。
- assistant final 文本进入现有输出安全策略。
- 日志不得记录原始音频、完整敏感文本、API Key、支付 payload。

## 10. 验证计划

### 10.1 P0 验证

- iOS：发送语音后，服务端收到 `asr_text/local_asr_text/recognized_text`。
- Android：补齐 ASR 后，服务端不再只收到 `[语音]`。
- 使用用户保存的阿里云音色时，assistant voice message 的 `extra.voice_provider` 为 `qwen_tts` 或 `cosyvoice_tts`。
- 保存音色扣 1 张音色卡。
- 通话 tick 每 30 秒扣 3 糖果。
- 首个角色音频未播放前失败不扣费。
- 挂断后写入摘要。

### 10.2 P1 验证

- ASR 首个 partial 延迟。
- ASR final 延迟。
- LLM generate_reply 延迟。
- TTS 首包延迟。
- 客户端播放 buffer 延迟。
- 打断成功率。
- 长连接断开恢复。
- 并发通话下的 Redis/session 清理。

## 11. 待产品确认

1. 语音电话是否按 6 糖果/分钟起步。
2. 是否每天给一次 30 秒免费体验。
3. VIP/SVIP 已确认赠通话分钟：VIP 30 分钟/月，SVIP 90 分钟/月；是否需要额外折扣待确认。
4. 通话摘要是否默认写入聊天记录。
5. 通话中是否展示实时字幕。
6. 用户克隆音色是否允许绑定多个角色。
7. 删除音色后历史已生成语音是否继续可播放。
8. 阿里云 ASR P0 smoke 后，是否把 `VOICE_ASR_PROVIDER=aliyun` 设为生产默认。

## 12. 当前建议排期

### Phase 0：把已有语音消息打磨完整

- Android 补 ASR。
- 确认生产复刻 provider 是 `qwen` 还是 `cosyvoice`。
- 修正旧文档中“客户端未实现语音”的过期结论。
- 验证阿里云复刻音色能稳定生成 assistant voice message。

### Phase 1：P0 通话壳

- 新增 `voice_call_enabled` 开关。
- 新增通话 UI。
- 新增 call session。
- 分段录音、ASR、generate_reply、阿里云 TTS、播放。
- 新增 `voice_call_tick` 扣费。
- 写通话摘要。

### Phase 2：实时语音

- 接入 Aliyun ASR-Realtime。
- 接入 Qwen-TTS-VC-Realtime。
- 建立 chat-svr voice-call WebSocket。
- 客户端 AudioRecord/AudioTrack 或 iOS AVAudioEngine 播放流。

### Phase 3：拟真体验

- VAD。
- barge-in 打断。
- 通话记忆写回。
- 失败自动恢复。
- Provider A/B：Qwen vs CosyVoice vs 火山旧音色。

## 13. 当前验证状态

- 2026-06-29 已修改 Android / iOS 客户端实时语音业务代码，同步麦克风开关、音频路由和自动打断口径。
- 2026-06-29 已跑 Android `./gradlew :app:compileDebugKotlin` 与 `./gradlew :app:testDebugUnitTest`，结果通过；同时把现有 `voice-playback` timeout 改动与单测期望收口到 15s，避免阻断验证。
- 2026-06-29 已跑 iOS `xcodebuild -workspace Bubbly.xcworkspace -scheme Bubbly -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`，结果通过；仅有既有 iOS `requestRecordPermission` deprecated warning 与 AppIntents metadata skip warning。
- 2026-06-29 已跑服务端定向 `npx vitest run src/modules/voice-call/routes.test.ts src/modules/voice-call/service.test.ts -t "ASR no-speech|ASR silence hallucinations"`，结果 2 passed，确认 no-speech 映射和 ASR 幻觉文本过滤仍可用。
- 未查生产阿里云账单。
- 未调用真实阿里云 API。
- 未修改商品、支付、埋点或隐私 SDK 配置。
