# dsh-ops-linux-arm64

把 [dsh-ops](https://github.com/T-Auto/dsh-ops) 的原生文件工具带到 **Linux ARM64**（aarch64）。

上游 0.4.1 的支持矩阵是 `win32-x64` / `linux-x64` / `darwin-arm64`，不含 Linux ARM64。
本项目**完整包含上游 0.4.1 源码**并打上一个薄补丁：补上缺失的目标，产出真正能跑的
aarch64 二进制。不模拟架构、不伪装平台、不跳过 provenance 校验。

> 这是**本地维护的私自分发**，不是上游的一部分。
> 上游是否接受这个改动是上游的决定 —— 见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

---

## 它解决什么

在 aarch64 Linux（例如 Android + Termux + PRoot Debian）上，dsh-ops 装得上、
`ops_bash` 能用，但 15 个原生文件工具一个都不存在：

```
dsh-ops: this host is linux-arm64, outside the win32-x64 / linux-x64 / darwin-arm64 support matrix
```

因为 `file` / `ptc` / `discovery` 三个组件声明了 `required: false`，
`resolveWorker()` 抛错后只写一条 warn、不发布任何工具 —— 静默降级。

本项目让这条链路真正走通：

```
DSH 会话 → dsh-tools 注册表 → dsh-sandbox-policy → dsh-ops 桥
        → 版本化 envelope → aarch64 原生 worker（真实进程）
```

## 状态（2026-10-27 实测）

| 项 | 结果 |
|---|---|
| 原生文件工具 | 15 个（1 常驻 + 14 按需）在 PRoot aarch64 上实测可用 |
| 逐项验收 | 19 / 19 通过，DSH 重启前后各一次 |
| PTC `ops_batch` | worker 层 plan / run 实测通过 |
| `ops_bash` | 无回归 |
| 构建 | 两次独立 run，sha256 完全一致 |
| 可编译目标 | 4 个：`win32-x64`、`linux-x64`、`linux-arm64`、`darwin-arm64` |

完整证据见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

## 安装（两种方式）

仓库里已经带了**构建好的产物**，开箱即用：

```
prebuilt/linux-arm64/
  dsh-ops-worker      3,569,560 bytes
  provenance.json     sha256 bf30ef79…cbb9ef
```

```bash
# 前置：先有 dsh-ops 本体（本项目不发布到 npm）
dsh plugin --profile web add dsh-ops@0.4.1

# 方式 A：用预编译产物（不需要 Rust）
git clone https://github.com/midi-HL/dsh-ops-linux-arm64.git
cd dsh-ops-linux-arm64
./scripts/install.sh

# 方式 B：自己构建（GitHub Actions，一次编全部 4 个目标）
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
./scripts/install.sh --artifact-dir ./out

# 装完必须重启 DSH
dsh-web.sh --stop && dsh-web.sh
```

详细步骤、手动安装、回滚、排错：**[docs/INSTALL.md](docs/INSTALL.md)**

## 为什么能编译

对上游 `native/` 全文检索，`target_arch` 出现 **0 次**。唯一的平台条件是
`cfg(target_os = ...)`（POSIX ACL、`/proc/self/fd` 目录 fsync、Windows DACL）。
依赖树全部纯 Rust（`cap-std`、`rustix`、`quick-xml`、`zip`、`sha2`、`regex`），
没有需要交叉编译 C 代码的 crate。

**限制来自分发准入，不是实现。** 所以改动只需要 4 处常量与对应断言。

## 改动面

| 文件 | 改动 |
|---|---|
| `src/ptc/runtime.ts` | `PLATFORMS` 增加 `linux-arm64`；错误文案同步 |
| `src/profile-install.ts` | `SUPPORTED_TARGETS.linux` 增加 `'arm64'` |
| `dsh-plugin.json` × 5 | `x-components[].targets` 增加 `linux-arm64` |
| `scripts/validate-manifest.mjs`、`test/linux-scope.test.mjs` | 断言同步 |
| `.github/workflows/` | `build-all-targets.yml`（新增）、`release.yml`（矩阵加一项） |

`native/` 下的 Rust 源码、`lib/` 运行时逻辑、`cordis.patch.yml`、profile 依赖、
DSH 本体 —— **全部未改**。

查看完整差异：

```bash
git diff v0.4.1..HEAD
```

## 上游兼容性

| 问题 | 答案 |
|---|---|
| 能否同时编译原项目的所有版本？ | **能**。`build-all-targets.yml` 一次编译 4 个目标；3 个上游目标仍用上游原来的 runner 与命令 |
| 是通用能力还是私自分发？ | **私自分发**。上游 release 校验把三目标集合当契约，且 roadmap 明确未计划 Linux ARM64 |
| 升级到 0.5.x 会怎样？ | npm 会整体覆盖插件目录，补丁与 arm64 二进制全部丢失，工具重新静默消失。**升级后必须重跑 `install.sh`** |
| 补丁失效怎么办？ | `install.sh` 校验替换次数，上游一改就**明确报错停止**，不会盲目替换 |

详见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 许可

上游 dsh-ops 是复合许可 `MIT AND Apache-2.0`：

- 插件本体 —— **MIT**，版权 `T-Auto and the dsh-ops contributors`
- FastCtx（`licenses/fastctx/`）—— Apache-2.0，本仓库不含其内容，仅保留许可文本

本仓库**原样保留** `LICENSE` 与 `NOTICE`，未作任何修改。本项目新增的部分
（workflow、脚本、文档、补丁差异）同样以 MIT 发布。

MIT 的唯一实质要求是保留版权声明与许可文本 —— 任何再分发（含二进制）都必须做到。
细节见 [docs/LICENSE-SCOPE.md](docs/LICENSE-SCOPE.md)。

## 仓库结构

```
src/ native/ bin/ scripts/ test/ docs/ …   上游 0.4.1 源码（含补丁）
prebuilt/linux-arm64/                      预编译产物，开箱即用
scripts/install.sh                         安装 + 放开准入 + 自动备份
.github/workflows/build-all-targets.yml    一次编译全部 4 个目标
.github/workflows/release.yml              上游发布流程（矩阵已含 arm64）
docs/                                      INSTALL / VERIFICATION / UPSTREAM / LICENSE-SCOPE
```
