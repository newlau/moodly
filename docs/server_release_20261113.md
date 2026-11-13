# 服务端发布单 2026-11-13：Lovee 源账号退休热修 + iOS 1.2.8+ QQ 入口

状态：implementation record（2026-11-13 14:36–14:44 已执行）
Owner topic：`moodly-chat-svr` / `bubbly-server` 生产发布（本文只记录这一次发布，不替代两仓库 `.docs/` 与 `docs/deployment-branch-guard.md`）
涉及：`moodly-chat-svr`（三节点）、`bubbly-server`（一台）
不涉及：客户端发版

## 1. 发布内容

| 仓库 | 发布点 | 线上效果 |
|---|---|---|
| moodly-chat-svr | `master` @ `6145e770` | 在 HTTP/JWT、WS 每帧、推送、主动/被动及延迟生成、QQ 外发、语音清理等边界拒绝 `LOVEE_SOURCE_RETIRED_UIDS`；名单为空时保持原行为 |
| bubbly-server | `.env.prod`（未提交） | 全局 `ios_feature_flags.qq_chat_enabled=true`；iOS 1.2.8 及以上读取该开关展示 QQ 入口 |

## 2. 代码检查

- 提交范围 44 个文件：35 个修改 + 9 个新增（`src/lovee-source-retirement.ts`、`src/infra/source-account-retirement.ts`、`src/modules/qq/source-recipient-scope.ts` 及对应测试/说明）。
- 修复 `src/jobs/handlers/session-memory.test.ts`：新增用例后缺少 describe 的收尾 `});`，整文件无法被 Vitest 收集；补上后 43 项通过。该文件的原现场版本同样不完整，发布后以提交版本为准。
- 明确排除三处现场本地热修，未进入本次提交，部署后按原值恢复：
  - `.env.prod`（含生产密钥，不提交）
  - `prisma/schema.prisma` 的 `CharacterRedemption.code @db.VarChar(16)`（仅 `10.64.128.5`）
  - `src/config/env.ts` 的 `OFFICIAL_ACCOUNT_AVATAR_URL` 品牌迁移（三节点）
- 验证：
  - `yarn build` 通过（Prisma generate + TypeScript）。
  - 19 个相关测试文件 446 项通过。
  - 全量测试仍有既有失败，不是本次引入：`src/modules/qq/personal/compat.test.ts` 14 项在干净 `756b18e6` 上同样失败；`src/app.test.ts` 因缺少 `assets/character_stickers` fixture 报 ENOENT。
- 发布前配置核对：chat 三节点 `DATABASE_URL`/`DATABASE_URL_SINGLE` 均为 `/moodly`，未设置 `LOVEE_DATABASE_ISOLATION`、`LOVEE_GRAY_*` 等 source-only 冲突项；`LOVEE_SOURCE_RETIRED_UIDS` 为空，功能默认关闭。

## 3. chat-svr 发布

发布方式参考 [2026-11-12 发布单](server_release_20261112.md)：三节点 `serial=1`、逐台健康检查。因三节点在 `756b18e6` 上带有未提交的源账号退休热修（新增文件与 38 个修改文件），`deploy.sh start` 的 `git pull --rebase --autostash` 会与新增文件冲突，本次改为：

1. 每节点备份到 `/root/lovee-pre-20261113/`：`tracked.diff`、`untracked.tar.gz`、`env.prod`、`env.ts`、`schema.prisma`。
2. 移出 9 个即将入库的新增文件，`git fetch` 后 `git reset --hard origin/master`（`6145e770`）。
3. 恢复 `.env.prod`、`env.ts` 头像行，`10.64.128.5` 另恢复 schema 的 `@db.VarChar(16)`。
4. 逐台执行 `./run.sh dev`（不拉取、不 stash；安装依赖 → 构建 → PM2 滚动 reload），每一步 `curl http://127.0.0.1:3333/health`。

结果：

| 节点 | PM2 实例 | 发布时间 | 结果 |
|---|---|---|---|
| 10.64.128.5 | 2 / 3 | 14:36–14:38 | `6145e770`，两实例 online，health ok |
| 10.64.0.13 | 0 / 1 | 14:39–14:41 | `6145e770`，两实例 online，health ok |
| 10.64.192.6 | 2 / 3 | 14:41–14:43 | `6145e770`，两实例 online，health ok |

`err.log` 仍有既有的 Milvus `EHOSTUNREACH 101.126.140.131:19530` digest-recall 错误和 Redis `allkeys-lru` 提示；发布前后一致，不是本次代码引入。

## 4. bubbly-server：QQ 1.2.8+

- 备份：`/www/wwwroot/bubbly-server/.env.prod.bak-qq-ios128plus-20261113144257`（保留原 0600 权限）。
- 在最后一条生效的 `STARTUP_STRATEGY_EXT` 中增加全局 `ios_feature_flags.qq_chat_enabled=true`；保留原有 `ios_feature_flags_by_version.1.2.8.qq_chat_enabled=true`。
- 逐个 `pm2 reload 0`、`pm2 reload 1`，中间执行 `http://127.0.0.1:8733/health`，均 200。
- 公网核验 `GET /v1/app/startup-strategy`：iOS `1.2.7`/`1.2.8`/`1.2.9`/`1.3.0`/`1.3.1` 均返回 `qq_chat_enabled=true`；`companion_guard_enabled=false`、`wechat_mp_chat_enabled=false`、`phone_login_entry_enabled=true` 未变。`1.2.7` 及更早没有 QQ 入口代码，返回 true 不会展示入口。

## 5. 回滚

- bubbly-server：`cp -a .env.prod.bak-qq-ios128plus-20261113144257 .env.prod`，逐个 `pm2 reload 0`、`pm2 reload 1`，再回读公网策略。
- chat-svr 单节点：
  - 代码：`./run.sh rollback 756b18e6`（会先 stash 当前工作区再 reset），随后把 `/root/lovee-pre-20261113/tracked.diff` 与 `untracked.tar.gz` 复原，再 `./run.sh dev` 重建；或直接 `git reset --hard 756b18e6` 后复原同一备份。
  - 只回滚本次提交且保留现场热修时，不要直接依赖 `rollback` 的 stash，先核对 `/root/lovee-pre-20261113/`。
- 三节点均失败时先暂停继续发布，保留当前健康节点，按备份恢复后再逐台重建。

## 6. 验证边界

- 已做：提交、构建、目标测试、三节点健康检查、主服务公网策略回读。
- 未做：真实已迁 UID 的端到端拦截（`LOVEE_SOURCE_RETIRED_UIDS` 仍为空）、QQ 真机入口截图/扫码聊天、全量测试清绿。`LOVEE_SOURCE_RETIRED_UIDS` 需要业务方提供名单后再单独配置和验证。
