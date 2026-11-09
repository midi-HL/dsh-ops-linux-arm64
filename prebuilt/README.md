# 预编译产物

```
linux-arm64/
  dsh-ops-worker      3,569,560 bytes
  provenance.json     sha256 bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef
```

## 来源

| 项 | 值 |
|---|---|
| 源码 | 本仓库 `HEAD`（= 上游 `v0.4.1` + `patches/` 的改动） |
| 目标三元组 | `aarch64-unknown-linux-gnu` |
| 编译器 | `rustc 1.97.1 (8bab26f4f 2026-07-14)` |
| 交叉工具链 | `zig 0.13.0`（pip wheel）+ `cargo-zigbuild 0.19.7` |
| 构建环境 | GitHub Actions `ubuntu-24.04` |
| 可复现 run | 两次独立 dispatch，sha256 完全一致 |

## 校验

```bash
sha256sum prebuilt/linux-arm64/dsh-ops-worker
# bf30ef79b5b921a659c0f04d7b54a0344ed2268dd1a1a9a5faea284042cbb9ef
```

`install.sh` 会在安装前做同样的校验，不匹配就停止。

## 为什么不放进 npm 包

上游 `dsh-ops` 的 npm 包名由 `T-Auto` 维护，本项目无权发布。发布到自己的包名
会引入"两个包都要装、版本还要对齐"的复杂度，而实际交付物只有一个二进制 + 4 处常量改动。

所以这里直接给产物 + 安装脚本。安装方式见 [../docs/INSTALL.md](../docs/INSTALL.md)。

## 自己重建

```bash
gh workflow run build-all-targets.yml
gh run download <run-id> -n native-linux-arm64 -D ./out
```

产物应与本目录逐字节一致。
