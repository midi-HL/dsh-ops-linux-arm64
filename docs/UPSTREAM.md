# 改动说明与上游兼容性

## 一句话

上游从 **v0.4.1 到 v0.5.2** 从未把 Linux ARM64 纳入支持矩阵；限制来自**分发准入**，
不是实现。本项目补上缺失的 `linux-arm64` 目标，改动面是一小组常量与对应断言，
其余代码与上游一致。

当前仓库源码对齐 **v0.5.2**（上游最新 tag），目标机也已升到
DSH 0.2.2-rc.1 + dsh-ops 0.5.2，三者版本一致。升级过程见下面"宿主 DSH 升级"。

---

## 一、为什么上游说"不支持 Linux ARM64"

对 `native/` workspace 全文检索（v0.4.1 与 v0.5.2 都一样）：

```
$ grep -rn "target_arch" native --include="*.rs" | wc -l
0
```

唯一的平台条件是 `cfg(target_os = ...)`，用于三件事：

| 位置 | 用途 |
|---|---|
| `ops-files/src/file.rs` | Linux 下清理继承的 POSIX ACL |
| `ops-files/src/lib.rs` | Linux 下经 `/proc/self/fd` 重开目录描述符做 fsync |
| `ops-files/src/file.rs` | macOS 下 APFS clone 相关 |

依赖树全部是纯 Rust：`cap-std`、`cap-primitives`、`rustix`、`serde/serde_json`、
`quick-xml`、`zip`、`zlib-rs`、`sha2`、`regex`、`uuid`、`fs2`、`nix`、`libc`。
**没有需要交叉编译 C 代码的 crate，也没有 `#[cfg(target_arch)]`、手写汇编或 SIMD intrinsic。**

所以：**源码层面 aarch64 完全可行，挡住的是三层准入校验。**

## 二、三层准入（v0.5.2 的位置）

| 文件 | 常量 | 作用 |
|---|---|---|
| `src/execution/runtime.ts:10` | `PLATFORMS` | `resolveWorker()` 的入口闸门。注意它在读 `DSH_OPS_WORKER_BIN` / `config.binaryPath` **之前**就检查，所以环境变量绕不过去 |
| `src/profile-install.ts:18` | `SUPPORTED_TARGETS` | 安装器层面的闸门 |
| `dsh-plugin.json` | `x-components[0].targets` | 发布一致性校验（`bin/check-release.mjs`、`scripts/validate-manifest.mjs`） |

v0.5.2 与 v0.4.1 的结构差异：

| 项 | v0.4.1 | v0.5.2 |
|---|---|---|
| 权威 runtime 文件 | `src/ptc/runtime.ts` | `src/execution/runtime.ts`（`src/ptc/runtime.ts` 变成 deprecated 转发） |
| `x-components` 数量 | 7 | 1（`dsh-ops` 单 row） |
| manifest 里 `targets` 出现次数 | 5 | 1（多行） |
| 支持矩阵 | 3 目标 | 4 目标（新增 `darwin-x64`） |
| Linux triple | `x86_64-unknown-linux-gnu` | `x86_64-unknown-linux-musl`（静态） |
| `check-release.mjs` 目标集合 | 硬编码 | 从 `PLATFORMS` 动态读取 |

**v0.5.2 的重构让补丁面更小**，但替换字面量全变了 —— 这正是为什么不能把旧 patch
直接 `git apply` 上去，必须重新定位。

## 三、具体改动（相对 v0.5.2）

```diff
# src/execution/runtime.ts
-export const PLATFORMS = Object.freeze(['win32-x64', 'linux-x64', 'darwin-arm64', 'darwin-x64'])
+export const PLATFORMS = Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64', 'darwin-x64'])

-  ... `dsh-ops supports Windows x64, Linux x64 and macOS (arm64/x64) only; ...`
+  ... `dsh-ops supports Windows x64, Linux x64/arm64 and macOS (arm64/x64) only; ...`

# src/profile-install.ts
-Object.freeze({ win32: ['x64'], linux: ['x64'], darwin: ['arm64', 'x64'] })
+Object.freeze({ win32: ['x64'], linux: ['x64', 'arm64'], darwin: ['arm64', 'x64'] })

# dsh-plugin.json（唯一一处，多行）
   "targets": [
     "win32-x64",
     "linux-x64",
+    "linux-arm64",
     "darwin-arm64",
     "darwin-x64"
   ]

# scripts/validate-manifest.mjs — 断言同步
# scripts/lib/build/tar-modes.js — UNIX_WORKERS 增加 linux-arm64
# test/linux-scope.test.mjs、test/release-scope.test.mjs
#   — 把 linux-arm64 移出"应拒绝"清单；给假 ELF 头加 e_machine=183 分支
```

**没有改动的**：`native/` 下任何 Rust 源码、`lib/` 运行时逻辑、
`cordis.patch.yml`、profile 依赖、DSH 本体。

`tar-modes.js` 那处容易漏：它决定 npm 打包时给哪些二进制设执行位，
漏了会导致 arm64 worker 装上后 `EACCES`。

## 四、能否同时编译出原项目的所有版本？

**能。** `.github/workflows/build-all-targets.yml` 一次编 5 个目标：

| 目标 | runner | 工具链 |
|---|---|---|
| `win32-x64` | `windows-latest` | MSVC（上游原样） |
| `linux-x64` | `ubuntu-24.04` | musl，宿主 cargo（上游原样） |
| `darwin-arm64` | `macos-latest` | Apple 原生（上游原样） |
| `darwin-x64` | `macos-15-intel` | Apple 原生（上游原样） |
| `linux-arm64` | `ubuntu-24.04` | zig 交叉（**本项目新增**） |

四个上游目标用的是**上游原来的构建命令与 runner**，一个字节都没改；
第五个目标用 `cargo zigbuild`（公共 runner 上 apt 装交叉 gcc 会卡死）。

`release.yml` 的 `native` 矩阵与 `gate` 的 artifact 下载也同步加了第 5 项，
否则 `check-release.mjs` 会因缺 `linux-arm64` 而失败。

## 五、宿主 DSH 升级

v0.5.2 的 README 明确写：

> 宿主支持从 DSH **0.2.2-rc.1** 起；0.5 系列不再支持 0.2.0/0.2.1 或更早的
> 0.2.2 预览版。保留 DSH adapter 结构，按 0.2.2 原生工具准入和执行器接口接入。

目标机原本是 **DSH 0.2.1-rc.5** + **dsh-ops 0.4.4**，因此要部署 v0.5.2 必须先升级宿主。
实际执行：

1. DSH 本体从 `0.2.1-rc.5` 升到 `0.2.2-rc.1`
   （在独立目录完成整树安装后再原子替换 `node_modules`，避免在低内存 PRoot 上
   边跑边装导致设备崩溃）
2. `dsh plugin --profile web add dsh-ops@0.5.2` 把插件从 0.4.4 升到 0.5.2
3. 重新构建并部署 `linux-arm64` worker（v0.5.2 / musl）

升级后 DSH、插件、worker 三者版本一致。

> DSH 0.2.2-rc.1 会主动禁用仍停留在 `0.2.1-rc.5` 的
> `@deepseek-ai/dsh-api-terminal-controller`（日志有明确警告）。这是宿主的
> 版本保护，不是本补丁造成的故障；该插件可用 `dsh plugin allow-version` 显式豁免。

`scripts/install.sh` 做了**版本自适应**：按实际文件内容探测
`lib/execution/runtime.js` 是否存在、`targets` 是单行还是多行、
`PLATFORMS` 是 3 目标还是 4 目标，对 0.4.1 / 0.4.2–0.4.4 / 0.5.x 都能正确放开准入。
每处替换都先校验出现次数，不匹配就明确报错停止 —— 因此即使将来上游再升级，
旧版部署也能被安全处理。

## 六、本项目是"通用能力"还是"私自分发"？

**私自分发。** 理由：

1. `bin/check-release.mjs` 与 `scripts/validate-manifest.mjs` 把目标集合当作发布契约。
   加第五目标改变了上游 `verify:release` 的语义。
2. `package.json` 的 `os`/`cpu` 字段是配对矩阵的粗糙投影，无法表达
   "linux 支持 x64+arm64，darwin 支持 arm64+x64，win32 只支持 x64"。
3. 上游 `docs/roadmap.md` 把 Linux ARM64 列为**未计划**。
4. v0.5.2 加入了 `darwin-x64`（Intel Mac）却仍跳过 Linux ARM64 —— 说明是分发决策，
   不是技术障碍。

所以本项目不假装能被上游直接合并。它的定位是：**把上游源码拉下来、打一个薄补丁、
产出可用的 arm64 二进制**。

## 七、升级到 0.5.x 会发生什么

### 如果你用 npm 升级

`npm install dsh-ops@0.5.x` 会**整体覆盖**插件目录：

- `lib/`、`bin/`、`dsh-plugin.json`、`runtime/` 全部换成上游版本
- 三个准入补丁丢失
- `runtime/linux-arm64/` 丢失
- 结果：原生工具重新静默消失，`ops_bash` 继续可用

**升级后必须重新执行 `./scripts/install.sh`。** 目标机实测已发生过一次这种自动升级
（0.4.1 → 0.4.4），当时 `probe-tools` 报的正是 0.4.4 的
「macOS (arm64/x64) only; unsupported runtime target linux-arm64」。

### 宿主 DSH 版本

若要真正部署 v0.5.2，宿主 DSH 需 ≥ 0.2.2-rc.1。这是一次涉及约 90 个
`@deepseek-ai/*` 子包的整树升级，在低内存 PRoot 设备上风险很高，需先释放内存与磁盘。
本报告记录的实际升级过程见 `docs/VERIFICATION.md`。

### 补丁会不会失效

补丁是逐字匹配的。上游若改了以下任何一处，`install.sh` 会**明确报错并停止**：

- `PLATFORMS` 那一行的字面量
- `SUPPORTED_TARGETS` 那一行的字面量
- `dsh-plugin.json` 里 `targets` 的行格式（空格、引号、顺序）
- `lib/execution/runtime.js` 是否取代 `lib/ptc/runtime.js`

届时需要更新 `scripts/install.sh` 里的替换规则。改动面小，但需要人看一眼。

### 建议的升级流程

```bash
# 1. 记录当前版本
cd ~/.dsh/profiles/web/node_modules/dsh-ops && node -p "require('./package.json').version"

# 2. 升级（会覆盖插件目录）
dsh plugin --profile web add dsh-ops@<new-version>

# 3. 重新构建对应版本的 worker 并打补丁
cd ~/dsh-ops-linux-arm64
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
./scripts/install.sh --artifact-dir ./out
```

## 八、上游源码与本仓库的关系

本仓库**完整包含**上游 v0.5.2 源码（1060 个文件），并直接在其上应用了补丁。所以：

- `git log` 能看到补丁提交
- `git diff upstream-v0.5.2..main` 就是全部改动
- 可以直接 `npm run build` / `cargo build` / `npm test`
- 不需要额外 clone 上游

上游许可要求保留版权声明，`LICENSE` 与 `NOTICE` 原样保留
（见 `docs/LICENSE-SCOPE.md`）。上游 `README.md` / `README.en.md` / `README.zh.md`
也原样保留；本项目自己的说明放在 `README.arm64.md` 与 `docs/` 下，避免覆盖上游文档。
