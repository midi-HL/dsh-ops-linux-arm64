# dsh-ops-linux-arm64

把 [dsh-ops](https://github.com/T-Auto/dsh-ops) 的原生文件工具带到 **Linux ARM64**（aarch64）。

本仓库**完整包含上游源码**，当前对齐 **v0.5.2**（上游最新 tag），并打上一个薄补丁：
补上 `linux-arm64` 目标，产出真正能跑的 aarch64 二进制。不模拟架构、不伪装平台、
不跳过 provenance 校验。

> 这是**本地维护的私自分发**，不是上游的一部分。
> 上游从 v0.4.1 到 v0.5.2 从未把 Linux ARM64 纳入支持矩阵 —— 见
> [docs/UPSTREAM.md](docs/UPSTREAM.md) 的完整兼容性说明。

---

## 它解决什么

在 aarch64 Linux（例如 Android + Termux + PRoot Debian）上，dsh-ops 装得上、
`ops_bash` 能用，但原生文件工具一个都不存在：

```
dsh-ops: this host is linux-arm64, outside the win32-x64 / linux-x64 / darwin-arm64 / darwin-x64 support matrix
```

因为相关组件声明了 `required: false`，`resolveWorker()` 抛错后只写一条 warn、
不发布任何工具 —— 静默降级。

本项目让这条链路真正走通：

```
DSH 会话 → dsh-tools 注册表 → dsh-sandbox-policy → dsh-ops 桥
        → 版本化 envelope → aarch64 原生 worker（真实进程）
```

## 版本与部署策略（双轨）

| 组件 | 版本 |
|---|---|
| 仓库源码 | 上游 **v0.5.2** + arm64 补丁 |
| 目标机 DSH | **0.2.2-rc.1**（v0.5.2 要求的最低版本） |
| 目标机 dsh-ops | **0.5.2** + arm64 补丁 |
| worker | `aarch64-unknown-linux-musl`，由 v0.5.2 源码构建 |

v0.5.2 的 README 明确要求宿主 DSH **≥ 0.2.2-rc.1**（新的 adapter 接口），
因此目标机把 DSH 从 0.2.1-rc.5 升级后再部署插件，三者版本保持一致。

`scripts/install.sh` 仍**按文件内容自动识别**三种结构
（0.4.1 / 0.4.2–0.4.4 / 0.5.x），所以旧版环境也能用同一脚本打补丁。

上游 0.5.x 的重构要点（会影响补丁位置）：

- 7 个 `x-components` 合并成 1 个 `dsh-ops` 单 row（manifest 里 `targets` 从 5–6 处变成 1 处）
- `src/ptc/runtime.ts` 变成 deprecated 转发层，权威入口迁到 `src/execution/runtime.ts`
- 支持矩阵新增 `darwin-x64`（Intel Mac），但仍无 `linux-arm64`
- Linux worker 改用 **musl** 静态链接（`x86_64/aarch64-unknown-linux-musl`）
- `bin/check-release.mjs` 改为从 `PLATFORMS` 动态读取目标集合，不再硬编码

## 状态

| 项 | 结果 |
|---|---|
| 源码对齐 | 上游 v0.5.2（1060 文件），补丁重新定位到 `src/execution/` |
| 可编译目标 | 5 个：`win32-x64`、`linux-x64`、`linux-arm64`、`darwin-arm64`、`darwin-x64` |
| 目标机 | DSH 0.2.2-rc.1 + dsh-ops 0.5.2，PRoot aarch64 实测 |
| 逐项验收 | 19 / 19 通过（v0.4.1 基线，见 [docs/VERIFICATION.md](docs/VERIFICATION.md)） |
| `ops_bash` | 无回归 |

## 安装

仓库带了**构建好的产物**：

```
prebuilt/linux-arm64/
  dsh-ops-worker
  provenance.json     sha256 88a1417c…e3
```

```bash
# 前置：先有 dsh-ops 本体（本项目不发布到 npm）
dsh plugin --profile web add dsh-ops

# 用预编译产物（不需要 Rust）
git clone https://github.com/midi-HL/dsh-ops-linux-arm64.git
cd dsh-ops-linux-arm64
./scripts/install.sh

# 或自己构建（GitHub Actions，一次编全部 5 个目标）
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
./scripts/install.sh --artifact-dir ./out

# 装完必须重启 DSH
```

详细步骤、回滚、排错：**[docs/INSTALL.md](docs/INSTALL.md)**

> `install.sh` 会先校验产物 sha256，再自动备份插件目录、profile manifest、
> `cordis.patch.yml`，最后用插件自己的 `resolveWorker()` 验证准入已放开。
> 若上游改动了任一字面量，它会**明确报错停止**，不会盲目替换。

## 为什么能编译

对 `native/` 全文检索，`target_arch` 出现 **0 次**（v0.4.1 与 v0.5.2 都如此）。
唯一的平台条件是 `cfg(target_os = ...)`（POSIX ACL、`/proc/self/fd` 目录 fsync、
Windows DACL）。依赖树全部纯 Rust，没有需要交叉编译 C 代码的 crate。

**限制来自分发准入，不是实现。**

## 改动面（相对 v0.5.2）

| 文件 | 改动 |
|---|---|
| `src/execution/runtime.ts` | `PLATFORMS` 增加 `linux-arm64`；错误文案同步 |
| `src/profile-install.ts` | `SUPPORTED_TARGETS.linux` 增加 `'arm64'` |
| `dsh-plugin.json` | 唯一 `x-components[].targets` 增加 `linux-arm64` |
| `scripts/validate-manifest.mjs` | 断言同步 |
| `scripts/lib/build/tar-modes.js` | `UNIX_WORKERS` 增加 `linux-arm64`（否则打包装上后无执行位） |
| `test/linux-scope.test.mjs`、`test/release-scope.test.mjs` | 把 `linux-arm64` 移出"应拒绝"清单；给假 ELF 头加 aarch64 分支 |
| `.github/workflows/` | `build-all-targets.yml` + `release.yml` 矩阵加第 5 个目标 |

`native/` 下 Rust 源码、`lib/` 运行时逻辑、`cordis.patch.yml`、profile 依赖、
DSH 本体 —— **全部未改**。

```bash
git diff v0.5.2..HEAD     # 完整差异
```

## 上游兼容性

| 问题 | 答案 |
|---|---|
| 能否同时编译原项目所有版本？ | **能**。`build-all-targets.yml` 一次编 5 个目标；4 个上游目标仍用上游原 runner 与命令 |
| 是通用能力还是私自分发？ | **私自分发**。上游 release 校验把目标集合当契约，roadmap 明确未计划 Linux ARM64 |
| 升级到 0.5.x 会怎样？ | npm 覆盖插件目录后补丁与 arm64 二进制全部丢失，工具重新静默消失。**升级后必须重跑 `install.sh`** |
| 补丁失效怎么办？ | `install.sh` 探测文件内容并校验替换次数，上游一改就**明确报错停止** |

详见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 许可

上游 dsh-ops 是复合许可 `MIT AND Apache-2.0`：

- 插件本体 —— **MIT**，版权 `T-Auto and the dsh-ops contributors`
- FastCtx（`licenses/fastctx/`）—— Apache-2.0；本仓库不含其内容，仅保留许可文本

`LICENSE` 与 `NOTICE` **原样保留**。本项目新增的部分（workflow、脚本、文档、
补丁差异）同样以 MIT 发布。MIT 的唯一实质要求是保留版权声明与许可文本 ——
任何再分发（含二进制）都必须做到。细节见 [docs/LICENSE-SCOPE.md](docs/LICENSE-SCOPE.md)。

## 仓库结构

```
src/ native/ bin/ scripts/ test/ docs/ …   上游 v0.5.2 源码（含补丁）
prebuilt/linux-arm64/                      预编译产物
scripts/install.sh                         版本自适应的安装 + 准入 + 备份
.github/workflows/build-all-targets.yml    一次编译全部 5 个目标
.github/workflows/release.yml              上游发布流程（矩阵已含 arm64）
README.arm64.md / docs/*.md                本项目说明（上游 README 原样保留）
```
