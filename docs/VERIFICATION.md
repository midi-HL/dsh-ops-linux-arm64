# 验证记录

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

## 7. 复现方法

```bash
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
sha256sum ./out/dsh-ops-worker
# 期望 bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef

./scripts/install.sh --artifact-dir ./out
cd ~/.dsh/profiles/web/node_modules/dsh-ops && node bin/dsh-ops.mjs ladder
```
