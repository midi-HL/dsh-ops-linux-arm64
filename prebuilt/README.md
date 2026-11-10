# 预编译产物

```
linux-arm64/
  dsh-ops-worker      3,584,376 bytes
  provenance.json     sha256 88a1417cd97e49b144b0bdecae564380d96b29e80c25900265887dc22932aae3
```

## 来源

| 项 | 值 |
|---|---|
| 源码 | 本仓库 `HEAD`（= 上游 `v0.5.2` + `linux-arm64` 补丁） |
| 目标三元组 | `aarch64-unknown-linux-musl`（**静态链接**，无 GLIBC 依赖） |
| 编译器 | `rustc 1.97.1` |
| 交叉工具链 | `zig 0.13.0`（pip wheel）+ `cargo-zigbuild 0.19.7` |
| 构建环境 | GitHub Actions `ubuntu-24.04` |
| 构建 run | `42617401138`（5 目标全部 success） |
| ELF 校验 | ELF64 / little-endian / `e_machine=183` (AArch64) |

> 本产物对应 **dsh-ops 0.5.2**。早期基于 v0.4.1 的产物 sha256 为
> `bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef`，已不再随仓库分发。

## 校验

```bash
sha256sum prebuilt/linux-arm64/dsh-ops-worker
# 88a1417cd97e49b144b0bdecae564380d96b29e80c25900265887dc22932aae3
```

`install.sh` 会在安装前做同样的校验，不匹配就停止。

## 为什么不放进 npm 包

上游 `dsh-ops` 的 npm 包名由 `T-Auto` 维护，本项目无权发布。发布到自己的包名
会引入"两个包都要装、版本还要对齐"的复杂度，而实际交付物只有一个二进制 + 一组准入改动。

所以这里直接给产物 + 安装脚本。安装方式见 [../docs/INSTALL.md](../docs/INSTALL.md)。

## 自己重建

```bash
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
```

产物应与本目录逐字节一致（同一提交、同一工具链、同一 runner 镜像）。
