# 验证记录

> **本文第 1–8 节是 2026-10-27 基于上游 v0.4.1 的历史验收，保留作为证据链。**
> **当前版本（上游 v0.5.2 / DSH 0.2.2-rc.1）的实测结果见第 9 节。**
> 两版的二进制不同：v0.4.1 用 gnu 动态链接（sha256 `bf30ef79…cbb9ef`），
> v0.5.2 用 musl 静态链接（sha256 `88a1417c…e3`）。

全部数据来自 2026-10-27 的实机测试。

- 目标机：未 root 的 Android 手机 + Termux + PRoot Debian trixie
- CPU：`aarch64` / Cortex-A53（`0xd03`），8 核
- 内核：`4.9.227-perf+`（宿主 Android 内核）
- glibc：`2.41-12+deb13u4`
- DSH：`0.2.1-rc.2`，profile `web`

---

## 1. PRoot 环境快照

worker 与被测进程在**同一环境**下运行：

```
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 0000000000000000
Seccomp: 2

Linux localhost 4.9.227-perf+ #1 SMP PREEMPT Fri Jul 11 12:18:43 CST 2025 aarch64 GNU/Linux

uid=0(root) gid=0(root) 组=0(root),1079,3003,9997,20440,50440,99909997

/proc/self/ns    -> cgroup mnt net uts        （无 pid / user / ipc namespace）
/proc/1          -> 权限不够
/proc/self/root  -> /data/data/com.termux/files/home/Debian
```

`id` 报 root 是 PRoot 的假象：零 capability 意味着不能 mount / mknod / setns / chroot，
也没有 `CAP_SYS_PTRACE`。

## 2. 二进制

```
target:  aarch64-unknown-linux-gnu
size:    3,569,560 bytes
sha256:  bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef
rustc:   1.97.1 (8bab26f4f 2026-07-14)
zig:     0.13.0
```

ELF 校验：

```
$ readelf -h runtime/linux-arm64/dsh-ops-worker | grep -E 'Class|Machine'
  Class:                             ELF64
  Machine:                           AArch64
```

设备上动态依赖全部解析成功：

```
$ ldd runtime/linux-arm64/dsh-ops-worker
	linux-vdso.so.1
	libpthread.so.0 => /lib/aarch64-linux-gnu/libpthread.so.0
	libc.so.6 => /lib/aarch64-linux-gnu/libc.so.6
	libdl.so.2 => /lib/aarch64-linux-gnu/libdl.so.2
	/lib/ld-linux-aarch64.so.1
```

## 3. 逐项验收

测试链路是**真实的 DSH 组件**：

```
@deepseek-ai/cordis Context
  → @deepseek-ai/dsh-tools（真实注册表）
  → @deepseek-ai/dsh-sandbox-policy
  → dsh-ops host 桥
  → 版本化 envelope
  → aarch64 原生 worker（真实进程）
```

唯一替换的是 LLM：用脚本化 provider 替代网络模型请求，这样测试不依赖任何 API key，
每次运行可重复。

DSH 重启前后各跑一次，结果一致：

| 用例 | 结果 |
|---|---|
| `ops_grep`（content / count） | completed |
| `ops_glob` | completed |
| `ops_read_files` | completed |
| `ops_stat` | completed |
| `ops_read_table`（CSV） | completed，`columns=["name","age"]`，2 行 |
| `ops_read_pdf` | completed，读出 `ARM64-PROOT-PDF-MARKER` |
| `ops_read_docx` | completed，读出 `ARM64-PROOT-DOCX-MARKER` |
| `ops_edit_file` | completed |
| `ops_diff` | completed |
| `ops_copy` | completed |
| `ops_move` | completed |
| `ops_remove` | completed |
| `ops_write_file` | completed |
| `ops_replace` | completed |
| `ops_inspect_local_file` | completed |
| `ops_copy` 到已存在路径 | `REVISION_CONFLICT`（预期拒绝） |
| `ops_remove` 用过期 revision | `REVISION_CONFLICT`（预期拒绝） |
| `ops_stat` 读凭证文件 | `CREDENTIAL_DENIED`（预期拒绝） |

汇总：**19 / 19 通过。**

### PTC

worker 层直接调用 `component: "ptc"`：

```
batch plan:  {"status":"planned","total":1,"detailsRef":"j-572b6af3-…"}
batch run:   {"status":"completed","done":2,"failed":0,"total":2}
             → batch-copy.txt  sha256 13f4ea3f… == a.txt
             → batch-copy2.txt sha256 87ff44af… == b.txt
batch run（copy+move 同一路径）: PATH_RESTRICTED（重叠路径保护，预期拒绝）
```

PTC 呈现层（`tools mode: "ptc"`）正确发布
`run_code` + `ops_load_sdk` + `ops_inspect_local_file` + `ops_result`，
`run_code` 真实执行（独立 Node 进程、TypeScript 剥离、`tools.*` 绑定可用）。

### ops_bash 无回归

```
shell-inventory -> ["ops_bash"]
bash-run        -> exitCode 0, stdout "aarch64\n2\n"
```

## 4. 构建可复现性

两次独立的 `workflow_dispatch`，同一提交：

| run | sha256 |
|---|---|
| `40482982709` | `bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef` |
| `40483708838` | `bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef` |

字节完全一致。

## 5. PRoot 专项：能力边界

| 能力 | PRoot 下 | 说明 |
|---|---|---|
| worker 启动 | ✅ | 零 capability + Seccomp 2 下正常 |
| 文件读 / 搜索 / glob / stat | ✅ | 无特权需求 |
| 原子写 + 目录 fsync | ✅ | worker 经 `/proc/self/fd/N` 重开目录描述符；实测 `fsync` 成功 |
| 元数据保留（mode / owner / xattr） | ✅ | 实测 copy 后 `0640` 与 `user.tag` 均保留 |
| POSIX ACL 继承清理 | ✅ | `fremovexattr` 可用 |
| 无 pid / user namespace | 无影响 | worker 不依赖 `/proc/1` 或 namespace |
| `chown` 到其他用户 | 受限 | 仅同 uid 可保留；跨用户降级为 warning，不失败 |

**没有任何工具因 PRoot 限制而不可用。** worker 本来就不使用需要特权的路径
（mount / mknod / setns / chroot）。

## 6. 未达成的项

| 项 | 状态 | 原因 |
|---|---|---|
| 16 个工具全部同时可见 | 设计如此 | 上游设计为 1 常驻 + 15 按需（`ops_discover_tools` 激活） |
| `ops_batch` 在普通会话内直接调用 | 需 ptc-only 呈现 | 只在 `tools mode: "ptc"` 且 DSH 处于 ptc-only 时发布。worker 层与 PTC 呈现层均已单独验证 |
| 真实 LLM 端到端 | 未做 | 测试机 `127.0.0.1:8765` 转发端当时 down，`dsh headless` 报 `MISSING_CREDENTIAL`。属既有环境状态，与本改动无关 |

## 7. 四个目标同时编译（run `40491361545`）

一次 `workflow_dispatch`，4 个 job 全部 success：

| 目标 | triple | 大小 | sha256 | 格式 |
|---|---|---|---|---|
| `win32-x64` | `x86_64-pc-windows-msvc` | 3,855,872 | `5d0805c3c4885c7ae82accfc4725cf09c4e78b96507a5e68f189721fee40ea48` | PE |
| `linux-x64` | `x86_64-unknown-linux-gnu` | 5,264,688 | `3b781969c9f5a8e814a736702a223178999969821c0cd449613185ff698c5ec0` | ELF x86-64 (e_machine=62) |
| `linux-arm64` | `aarch64-unknown-linux-gnu` | 3,569,560 | `bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef` | ELF aarch64 (e_machine=183) |
| `darwin-arm64` | `aarch64-apple-darwin` | 4,236,288 | `241dfe16a3f38c4d2c4fc9cb17b73469b9d445714bf3c966fb42f0560450cce4` | Mach-O arm64 |

两个结论：

1. **`linux-arm64` 的 sha256 与本仓库 `prebuilt/` 里的产物完全一致** —— 说明从源码到
   二进制的链路可复现，预编译产物不是黑盒。
2. **`linux-x64` 的 sha256 与上游 npm 包 `runtime/linux-x64/provenance.json` 记录的值
   完全一致**（`3b781969c9f5a8e814a736702a223178999969821c0cd449613185ff698c5ec0`）——
   说明这个补丁**没有改变原项目在已有平台上的产出**，一个字节都没动。

## 8. 复现方法（历史 v0.4.1，当前版本请用第 9 节）

> 下面这组哈希属于已不再随仓库分发的 v0.4.1 产物。当前版本请跳到
> [第 9 节的可复现命令](#可复现命令)。

```bash
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
sha256sum ./out/dsh-ops-worker
# 期望 bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef

./scripts/install.sh --artifact-dir ./out
cd ~/.dsh/profiles/web/node_modules/dsh-ops && node bin/dsh-ops.mjs ladder
```

## 9. 当前版本验收（2026-11-09，v0.5.2 + DSH 0.2.2-rc.1）

### 环境

同一台未 root 的 Android 手机 + Termux + PRoot Debian：

```
CapEff:  0000000000000000        Seccomp: 2
Linux localhost 4.9.227-perf+ aarch64 GNU/Linux
uid=0(root)（PRoot 伪造）      /proc/1 不可访问
无 pid / user / ipc namespace
```

### 版本一致性

| 组件 | 版本 |
|---|---|
| DSH | `0.2.2-rc.1`（v0.5.2 要求 ≥ 此版本） |
| dsh-ops | `0.5.2` |
| worker | `0.5.2`，`aarch64-unknown-linux-musl`，静态链接 |
| worker sha256 | `88a1417cd97e49b144b0bdecae564380d96b29e80c25900265887dc22932aae3` |
| worker 大小 | 3,584,376 bytes |

`dsh-ops ladder` 输出：

```
Native worker (file tools)
  executable: /root/.dsh/profiles/web/node_modules/dsh-ops/runtime/linux-arm64/dsh-ops-worker
  source:     packaged runtime
...
  bash  available: yes  executable: /usr/bin/bash
$ runtime/linux-arm64/dsh-ops-worker --version
dsh-ops-worker 0.5.2
```

`dsh-web.sh` 启动成功并打印带 token 的链接；`curl 127.0.0.1:3080` 返回 401（需 token，正常）。
`http://127.0.0.1:8788/` 返回 200，全程未被关闭。

### 五个目标同时编译（run `42617401138`）

5 个 job 全部 success：

| 目标 | triple | 大小 | sha256（前 16 位） |
|---|---|---|---|
| `win32-x64` | `x86_64-pc-windows-msvc` | 4,059,136 | `45bdfd63ee0f82b6` |
| `linux-x64` | `x86_64-unknown-linux-musl` | 5,690,896 | `47e42c028de2499b` |
| `linux-arm64` | `aarch64-unknown-linux-musl` | 3,584,376 | `88a1417cd97e49b1` |
| `darwin-arm64` | `aarch64-apple-darwin` | 4,618,720 | `0acd73b55043de6a` |
| `darwin-x64` | `x86_64-apple-darwin` | 4,839,264 | `0ccefbd9fb8fbb81` |

arm64 产物 ELF 校验：`ELF64 / little-endian / e_machine=183 (AArch64)`，无 `GLIBC_` 符号。

### 真实 worker 逐项调用（13/13）

请求由插件自己的 `workerEnvelope()` 构造，经 stdin 送入 aarch64 原生 worker 进程，
解析其 stdout 的版本化 envelope。脚本 `/root/final-verify.mjs`。

| 用例 | 结果 |
|---|---|
| `stat` | completed，返回 revision |
| `read_files` | completed |
| `grep` | completed，命中 `hello aarch64` |
| `glob` | completed，匹配 `*.txt` |
| `read_table` | completed，CSV `columns=["name","age"]` 2 行 |
| `inspect_local_file` | completed |
| `diff` | completed |
| `write_file` | completed，创建 `out.txt` |
| `edit_file` | completed，`arm64` → `AARCH64` |
| `copy` | completed，保留元数据 |
| `move` | completed |
| `remove` | completed |
| 覆盖已存在目标 | `REVISION_CONFLICT`（正确拒绝，no clobber） |

```
SUMMARY {"pass":13,"total":13,"failed":[]}
```

### 文档解析

| 用例 | 结果 |
|---|---|
| `read_docx` | completed，读出 `ARM64-DOCX-MARKER` |
| `read_pdf` | completed，读出 `ARM64-PDF-MARKER` |

### PTC batch

| 用例 | 结果 |
|---|---|
| `batch action=plan` | `status: planned`，`done:0`，返回 `detailsRef` |
| `batch action=run`（两个不同源） | `status: completed`，`done:2 failed:0` |
| 落盘校验 | `b2.txt` / `b3.txt` sha256 与源文件完全一致 |
| 两个 copy 共用同一源 | `PATH_RESTRICTED`（重叠路径保护，预期拒绝） |

### 已知限制

| 项 | 说明 |
|---|---|
| `dsh-api-terminal-controller@0.2.1-rc.5` | DSH 0.2.2-rc.1 主动禁用了这个未升级的插件，日志有明确警告。属宿主版本保护，与本补丁无关；可用 `dsh plugin allow-version` 显式豁免 |
| 真实 LLM 端到端 | 未测（需要 API key 与转发端）。所有工具调用均在真实 worker 进程上完成，未经过 LLM 编排 |
| 旧 `acceptance-run.mjs` | 依赖 DSH 0.2.1 的 `Tools.mode: 'native'` schema，在 0.2.2 上失效。已改用直接 envelope 调用验证，不影响插件本身 |

### 可复现命令

```bash
gh workflow run build-all-targets.yml --repo midi-HL/dsh-ops-linux-arm64 --ref main
gh run download <run-id> -n native-linux-arm64 -D ./out
sha256sum ./out/dsh-ops-worker
# 88a1417cd97e49b144b0bdecae564380d96b29e80c25900265887dc22932aae3
./scripts/install.sh --artifact-dir ./out
cd ~/.dsh/profiles/web/node_modules/dsh-ops && node bin/dsh-ops.mjs ladder
```
