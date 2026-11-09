# 安装

本项目提供**完整源码 + 预编译好的 linux-arm64 二进制**。两条路任选：

- **A. 直接用预编译产物**（最快，不需要 Rust，不需要联网构建）
- **B. 自己从源码构建**（可复现，需要交叉工具链）

两种方式最终都做同一件事：把 `dsh-ops-worker` 放进插件的 `runtime/linux-arm64/`，
并让插件承认这个目标。

---

## 前置：先装上 dsh-ops 本体

本项目**不发布到 npm**。它是 dsh-ops 的一个平台补丁，需要先有上游包：

```bash
dsh plugin --profile web add dsh-ops@0.4.1
```

或者如果你的 profile 里已经有了（检查一下）：

```bash
ls ~/.dsh/profiles/web/node_modules/dsh-ops/package.json
```

> 为什么不上 npm：npm 上的 `dsh-ops` 由上游 `T-Auto` 维护，本项目无权发布到那个包名。
> 发布到自己的包名（如 `dsh-ops-linux-arm64`）会引入"两个包都要装、版本还要对齐"的
> 复杂度，而实际交付物只有 **一个 3.5 MB 的二进制 + 4 处常量改动**。
> 直接给产物 + 安装脚本，比多一个 npm 包更可靠。

---

## 方式 A：用预编译产物（推荐）

仓库里已经放了构建好的产物：

```
prebuilt/linux-arm64/
  dsh-ops-worker      3,569,560 bytes
  provenance.json     sha256 bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef
```

把整个仓库拷到目标机，然后：

```bash
cd dsh-ops-linux-arm64
./scripts/install.sh
```

脚本会依次做：

1. 用 `provenance.json` 里的 sha256 校验二进制（不匹配就停）
2. 备份插件目录 / profile manifest / `cordis.patch.yml` 到 `~/.dsh/dsh-ops-arm64-backup-<时间戳>/`
3. 安装 `runtime/linux-arm64/dsh-ops-worker`
4. 打开三处平台准入
5. 用插件自己的 `resolveWorker()` 验证能解析到 worker

指定别的 profile：

```bash
./scripts/install.sh --profile tui
```

先看它要做什么而不实际改动：

```bash
./scripts/install.sh --dry-run
```

### 手动安装（不想跑脚本）

```bash
P=~/.dsh/profiles/web/node_modules/dsh-ops

# 1. 放二进制
mkdir -p $P/runtime/linux-arm64
install -m 0755 prebuilt/linux-arm64/dsh-ops-worker $P/runtime/linux-arm64/dsh-ops-worker
cp prebuilt/linux-arm64/provenance.json $P/runtime/linux-arm64/provenance.json

# 2. 打开准入（三处）
sed -i "s/Object.freeze(\['win32-x64', 'linux-x64', 'darwin-arm64'\])/Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64'])/" \
  $P/lib/ptc/runtime.js
sed -i "s/win32: \['x64'\], linux: \['x64'\]/win32: ['x64'], linux: ['x64', 'arm64']/" \
  $P/lib/profile-install.js
sed -i 's/"targets": \["win32-x64", "linux-x64", "darwin-arm64"\]/"targets": ["win32-x64", "linux-x64", "linux-arm64", "darwin-arm64"]/g' \
  $P/dsh-plugin.json

# 3. 验证
cd $P && node bin/dsh-ops.mjs ladder
```

`sed -i` 在部分环境需要备份后缀（macOS 用 `sed -i ''`）。用脚本更稳。

---

## 方式 B：从源码构建

### B1. 用 GitHub Actions（不用本机工具链）

```bash
gh workflow run build-all-targets.yml    # 一次编译全部 4 个目标
gh run download <run-id> -n native-linux-arm64 -D ./out
./scripts/install.sh --artifact-dir ./out
```

`build-all-targets.yml` 会同时编译 `win32-x64`、`linux-x64`、`linux-arm64`、`darwin-arm64`。
每个目标的 sha256 写在 run summary 里。

### B2. 本机交叉编译（Linux x64 上）

```bash
python3 -m pip install ziglang==0.13.0 cargo-zigbuild==0.19.7
rustup toolchain install 1.97.1 && rustup default 1.97.1
rustup target add aarch64-unknown-linux-gnu

npm ci --ignore-scripts
npm run build
cargo zigbuild --release --locked --manifest-path native/Cargo.toml --target aarch64-unknown-linux-gnu
node bin/native-runtime.mjs stage --platform linux-arm64 --input native/target/aarch64-unknown-linux-gnu/release
node bin/native-runtime.mjs check --platform linux-arm64
```

`runtime/linux-arm64/` 下会得到二进制与 provenance。

### B3. 在 aarch64 机器上原生编译

```bash
rustup target add aarch64-unknown-linux-gnu    # 就是宿主架构
cargo build --release --locked --manifest-path native/Cargo.toml
node bin/native-runtime.mjs stage --platform linux-arm64 --input native/target/release
```

> 内存不足 1 GB 的机器（如 PRoot 容器）不建议本机编译：`cap-std` + PDF/DOCX 解析的
> 依赖树首次编译很容易 OOM 或 ENOSPC。用 B1。

---

## 装完必须重启 DSH

插件在 profile 加载时解析 worker，改完文件不重启不会生效。

```bash
# 如果你用 dsh-web.sh 包装脚本
dsh-web.sh --stop && dsh-web.sh

# 或者直接
pkill -f 'dsh.*web' && dsh web --port 3080 --no-open
```

重启后验证：

```bash
cd ~/.dsh/profiles/web/node_modules/dsh-ops
node bin/dsh-ops.mjs ladder
```

期望输出前两行是：

```
Native worker (file tools)
  executable: /root/.dsh/profiles/web/node_modules/dsh-ops/runtime/linux-arm64/dsh-ops-worker
  source:     packaged runtime
```

如果 `executable:` 指向别的路径，或者报 support matrix 错误，说明第 2 步没生效。

---

## 在 DSH 会话里确认工具真的能调

装好之后，会话里不会一次看到 16 个工具。这是上游设计：

- `ops_read_files` 常驻
- 其余 14 个文件工具 + `ops_batch` 通过 `ops_discover_tools` 按需激活

所以会话里先看到 `ops_read_files` 和 `ops_discover_tools` 是**正常**的。
让 agent 调 `ops_discover_tools` 说"我要搜代码"，`ops_grep` / `ops_glob` 就会出现在下一步。

---

## 卸载 / 回滚

```bash
backup=$(cat ~/.dsh/dsh-ops-arm64-backup-path)
rm -rf ~/.dsh/profiles/web/node_modules/dsh-ops
cp -a "$backup/dsh-ops-pkg" ~/.dsh/profiles/web/node_modules/dsh-ops
```

然后重启 DSH。回滚后 `ops_bash` 仍然可用，15 个原生工具重新消失（回到上游默认行为）。

---

## 常见问题

**`Native worker unavailable for linux-arm64`**
第 2 步的准入没改成功。检查：

```bash
grep -n "linux-arm64" ~/.dsh/profiles/web/node_modules/dsh-ops/lib/ptc/runtime.js
```

应该看到 `PLATFORMS` 那行含 `linux-arm64`。

**`Native worker ... is not executable`**
`chmod +x` 丢了。`install -m 0755` 会设好；`cp` 不会。

**`Native worker provenance mismatch`**
`provenance.json` 里的 sha256 和实际文件不一致。重新拷一份，别只拷其中一个文件。

**工具还是没出现**
先重启 DSH；再看 `dsh-ops ladder` 是否解析到 worker；最后确认 profile 的
`package.json` 里 `dsh.profile.bundles` 含 `dsh-ops`。
