# 改动说明与上游兼容性

## 一句话

上游的架构限制来自**分发准入**，不是实现。本项目补上缺失的 `linux-arm64` 目标，
改动面是 4 处常量 + 对应断言，其余代码与上游逐字节相同。

---

## 一、为什么上游说"不支持 Linux ARM64"

对上游 `native/` workspace 全文检索：

```
$ grep -rn "target_arch" native --include="*.rs" | wc -l
0
```

唯一的平台条件是 `cfg(target_os = ...)`，用于三件事：

| 位置 | 用途 |
|---|---|
| `ops-files/src/file.rs:213` | Linux 下清理继承的 POSIX ACL |
| `ops-files/src/lib.rs:28` | Linux 下经 `/proc/self/fd` 重开目录描述符做 fsync |
| `ops-files/src/file.rs:298` | macOS 下 APFS clone 相关 |

依赖树全部是纯 Rust：

```
cap-std, cap-fs-ext, cap-primitives, rustix, rustix-linux-procfs,
serde/serde_json, quick-xml, zip, zlib-rs, sha2, regex, uuid, fs2, nix, libc
```

**没有任何需要交叉编译 C 代码的 crate。** 也没有 `#[cfg(target_arch)]`、没有手写
汇编、没有 SIMD intrinsic、没有指针宽度假设。

所以：**源码层面 aarch64 完全可行，挡住的是三层准入校验。**

## 二、三层准入（改动就在这里）

| 文件 | 常量 | 作用 |
|---|---|---|
| `src/ptc/runtime.ts:10` | `PLATFORMS` | `resolveWorker()` 的入口闸门。注意它在读 `DSH_OPS_WORKER_BIN` / `config.binaryPath` **之前**就检查，所以环境变量绕不过去 |
| `src/profile-install.ts:18` | `SUPPORTED_TARGETS` | 安装器层面的闸门 |
| `dsh-plugin.json` × 5 | `x-components[].targets` | 发布一致性校验（`bin/check-release.mjs`、`scripts/validate-manifest.mjs`） |

## 三、具体改动

```diff
# src/ptc/runtime.ts
-export const PLATFORMS = Object.freeze(['win32-x64', 'linux-x64', 'darwin-arm64'])
+export const PLATFORMS = Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64'])

-  if (!PLATFORMS.includes(...)) throw new Error(`dsh-ops supports Windows x64, Linux x64 and macOS Apple Silicon (darwin-arm64) only; ...`)
+  if (!PLATFORMS.includes(...)) throw new Error(`dsh-ops supports Windows x64, Linux x64, Linux arm64 and macOS Apple Silicon (darwin-arm64) only; ...`)

# src/profile-install.ts
-Object.freeze({ win32: ['x64'], linux: ['x64'], darwin: ['arm64'] })
+Object.freeze({ win32: ['x64'], linux: ['x64', 'arm64'], darwin: ['arm64'] })

# dsh-plugin.json（5 处）
-"targets": ["win32-x64", "linux-x64", "darwin-arm64"]
+"targets": ["win32-x64", "linux-x64", "linux-arm64", "darwin-arm64"]

# scripts/validate-manifest.mjs、test/linux-scope.test.mjs
  对应断言同步（否则上游自己的测试会红）
```

**没有改动的**：`native/` 下的任何 Rust 源码、`lib/` 下的运行时逻辑、
`cordis.patch.yml`、profile 依赖、DSH 本体。

## 四、能否同时编译出原项目的所有版本？

**能。** 这就是 `.github/workflows/build-all-targets.yml` 与改造后的 `release.yml` 做的事：

| 目标 | runner | 工具链 |
|---|---|---|
| `win32-x64` | `windows-latest` | MSVC（上游原样） |
| `linux-x64` | `ubuntu-24.04` | 宿主 gcc（上游原样） |
| `darwin-arm64` | `macos-latest` | Apple 原生（上游原样） |
| `linux-arm64` | `ubuntu-24.04` | zig 交叉（**本项目新增**） |

三个上游目标用的是**上游原来的构建命令与 runner**，一个字节都没改；
第四个目标用 `cargo zigbuild`，因为公共 runner 上 apt 装交叉 gcc 会卡死（见下）。

`cargo zigbuild` 与 `cargo build` 产出的 ELF 在功能上等价，但**字节不同**：
zig 用自己打包的 glibc sysroot，链接结果与发行版 gcc 不同。这解释了为什么
本项目预编译产物的 sha256 与"用 gcc 交叉编译"的版本不一致 —— 两者都能跑。

## 五、本项目是"通用能力"还是"私自分发"？

**私自分发。** 理由：

1. `bin/check-release.mjs` 与 `scripts/validate-manifest.mjs` 把三目标集合当作发布契约。
   加第四目标改变了上游 `verify:release` 的语义。
2. `package.json` 的 `os`/`cpu` 字段是配对矩阵的粗糙投影，无法表达
   "linux 支持 x64+arm64，darwin 只支持 arm64"。
3. 上游 `docs/roadmap.md` 把 Linux ARM64 列为**未计划**。

所以本项目不假装能被上游直接合并。它的定位是：**把上游源码拉下来、打一个薄补丁、
产出可用的 arm64 二进制**。

## 六、升级到 0.5.x 会发生什么

### 如果你用 npm 升级

`npm install dsh-ops@0.5.x` 会**整体覆盖**插件目录：

- `lib/`、`bin/`、`dsh-plugin.json`、`runtime/` 全部换成上游版本
- 三个准入补丁丢失
- `runtime/linux-arm64/` 丢失
- 结果：15 个原生工具重新静默消失，`ops_bash` 继续可用

**升级后必须重新执行 `./scripts/install.sh`。**

### 补丁会不会失效

补丁是逐字匹配的。上游若改了以下任何一处，`install.sh` 会**明确报错并停止**
（它校验替换次数，不是盲目替换）：

- `PLATFORMS` 那一行的字面量
- `SUPPORTED_TARGETS` 那一行的字面量
- `dsh-plugin.json` 里 `targets` 的行格式（空格、引号、顺序）

届时需要手动更新 `scripts/install.sh` 里的三个 `patch()` 调用。改动面小，但**需要人看一眼**。

### 建议的升级流程

```bash
# 1. 记录当前版本
cd ~/.dsh/profiles/web/node_modules/dsh-ops && node -p "require('./package.json').version"

# 2. 升级
dsh plugin --profile web add dsh-ops@<new-version>

# 3. 重新打补丁（会失败并告诉你哪里变了）
cd ~/dsh-ops-linux-arm64
gh workflow run build-all-targets.yml -f upstream_ref=v<new-version>
gh run download <run-id> -n native-linux-arm64 -D ./out
./scripts/install.sh --artifact-dir ./out
```

## 七、上游源码与本仓库的关系

本仓库**完整包含**上游 0.4.1 源码（544 个文件，6.7 MB），并直接在其上应用了补丁。
所以：

- `git log` 能看到补丁提交
- `git diff v0.4.1..HEAD` 就是全部改动
- 可以直接 `npm run build` / `cargo build` / `npm test`
- 不需要额外 clone 上游

上游许可要求保留版权声明，`LICENSE` 与 `NOTICE` 原样保留（见 `docs/LICENSE-SCOPE.md`）。
