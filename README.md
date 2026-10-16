# zcron

**Batch-manage [ZCode](https://zcode.ai) local automations from your terminal.**
批量创建/管理 ZCode 定时自动化,绕过 CronCreate 单会话限制与 20 条总数上限。单文件、零依赖(Python 3 标准库)。

> English TL;DR: ZCode's `CronCreate` refuses to create multiple automations in one session,
> and also rejects creation once you hit 20 automations total.
> Automations actually live in a local SQLite DB (`~/.zcode/v2/tasks-index.sqlite`, table
> `automations`, WAL mode) that the host re-reads on every scheduler tick — no in-memory cache.
> `zcron` writes there directly. Verified end-to-end: insert → shows up in CronList →
> fires on schedule → `outcome=succeeded`.

## 为什么

在 ZCode 会话里想让 agent 挂多个定时任务(雷达、监控、周报管线……),`CronCreate` 会被
"单个会话拒建多个"挡住,只能开 N 个会话逐个建;总数到 20 条后更是直接拒建。
`zcron` 两道闸门都绕过,把这件事变成一条命令:

```bash
zcron add --from-dir ./my-automations --yes
```

## 原理

- 自动化持久化在 `~/.zcode/v2/tasks-index.sqlite` 的 `automations` 表(WAL 模式)。
- 宿主调度器每个 tick 直接查库(`idx_automations_due` 索引),**没有内存缓存**,
  外部写入即刻可见、即刻可调度。
- 写入前 `zcron` 会自己解析 cron、算好 `next_run_at`(epoch 毫秒)——这正是宿主判到期的依据。

## 安装

**方式一:skills.sh 一键安装(推荐)**

```bash
npx skills add lian-yang/zcron
```

经 [skills.sh](https://skills.sh)(vercel-labs/skills)安装,自动落到当前使用的
agent 技能目录(Claude Code / Codex / ZCode / Cursor 等都支持)。指定 agent 端:

```bash
npx skills add lian-yang/zcron -g -y -a zcode   # 例:装到 ~/.zcode/skills
```

装完技能即含 CLI 工具(技能目录内的 `zcron` 可执行文件),agent 会自动按
SKILL.md 调用;想在 shell 里直接敲 `zcron`,再补一步:

```bash
ln -s ~/.zcode/skills/zcron/zcron ~/.local/bin/zcron
```

**方式二:手动安装 CLI**

```bash
git clone https://github.com/lian-yang/zcron.git
cd zcron
./install.sh            # 装到 ~/.local/bin/zcron(确认该目录在 PATH)
```

或者不装,直接跑仓库里的文件:`python3 zcron doctor`。

## 快速开始

```bash
# 0. 体检:库存在?WAL?表结构未被 ZCode 改版?
zcron doctor

# 1. 预览 cron(不写库)
zcron next "0 9 * * 1" --count 3

# 2. 单条创建(prompt 放文件里)
zcron add --title "每周一 9 点数据管线" --cron "0 9 * * 1" --prompt-file prompt.md

# 3. 批量创建:一个 .md 一条自动化,一次导入
zcron add --from-dir ./automations --yes

# 4. 日常管理
zcron list                  # 全部(含下次触发时间)
zcron disable 55e3e527      # 前 8 位 id 前缀即可
zcron enable  55e3e527
zcron rm 55e3e527 --yes
```

### 批量文件格式(`--from-dir`)

每个 `.md` = 一条自动化,frontmatter + prompt 正文:

```markdown
---
title: 每天 8:40 新词雷达扫描
cron: 40 8 * * *
max-runs: 1                    # 可选;省略 = 无限循环
enabled: false                 # 可选;默认 true
model: providerId/modelId:max  # 可选;省略 = 取库内现有自动化的众数模型
---
自动化触发后发给 agent 的完整指令(prompt)。
```

### 模型

`--model providerId/modelId[:level]`(level ∈ max/high/medium/low/minimal)。
省略时 zcron 自动统计库里现有自动化的 `model_selection` 众数并沿用——即
"跟这台机器上已在跑的自动化保持一致",空库则留空跟随宿主默认。

## 安全设计

| 机制 | 说明 |
|---|---|
| 写前整库备份 | 每次写操作先经 sqlite backup API 快照到 `~/.zcron/backups/`(保留 10 份),可回滚 |
| 结构闸门 | 表结构不符预期(如 ZCode 改版)时拒绝写入,不写坏库 |
| 并发保护 | `busy_timeout=10s`,与宿主进程并发写安全 |
| 显式确认 | `rm` 必须 `--yes`;批量导入不带 `--yes` 先逐条预览 |
| 只读预览 | `next` 命令纯计算,不碰库 |

## 命令一览

```
zcron list [--disabled]         列出(含 cron / 已跑次数 / 下次触发)
zcron show <id前缀>             看单条完整字段
zcron add                       单条(--title --cron --prompt-file|--prompt)
zcron add --from-dir DIR        批量导入(.md × N)
zcron rm <id前缀> --yes         删除(连运行历史)
zcron enable|disable <id前缀>   启停(enable 可复活已跑完的任务,有限次任务计数清零)
zcron next "cron" [--count N]   预览触发时间
zcron doctor                    库体检 + 最近将触发的任务
```

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ZCODE_DB` | `~/.zcode/v2/tasks-index.sqlite` | 自动化库路径 |
| `ZCODE_WORKSPACE` | `~/.zcode/workspace/default` | 新建自动化绑定的 workspace |

## 兼容性与免责

- 在 macOS + ZCode CLI(2026-10 版)上开发并端到端验证;纯标准库,理论通吃有
  Python 3.8+ 的平台。
- **非官方工具**,表结构以实测为准;ZCode 大版本更新后先跑 `zcron doctor`,
  结构闸门会在不兼容时拒绝写入而不是写坏数据。
- cron 为标准 5 字段(分 时 日 月 周)、本地时区;`日`与`周`同时受限时按
  vixie-cron OR 语义。

## License

MIT
