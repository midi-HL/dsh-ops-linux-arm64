# 许可范围

本仓库是 [dsh-ops](https://github.com/T-Auto/dsh-ops) 的衍生作品。dsh-ops 使用**复合许可**：

```
MIT AND Apache-2.0
```

## 上游的两块内容

| 内容 | 许可 | 版权 |
|---|---|---|
| dsh-ops 插件本体（除 `licenses/fastctx/` 之外的一切） | MIT | `T-Auto and the dsh-ops contributors` |
| FastCtx（`licenses/fastctx/`） | Apache-2.0 | FastCtx 作者 |

## 本仓库包含什么

| 内容 | 来源 | 许可 |
|---|---|---|
| 上游 0.4.1 源码（`src/`、`native/`、`bin/`、`scripts/`、`test/`、`docs/` 等） | 上游 | MIT（原样保留） |
| 上游 `LICENSE`、`NOTICE`、`licenses/` | 上游 | 原样保留，未修改 |
| 本项目新增的补丁（4 处常量 + 断言） | 本项目 | MIT |
| 本项目新增的 workflow、安装脚本、文档 | 本项目 | MIT |
| `prebuilt/linux-arm64/dsh-ops-worker` | 由上游源码交叉编译 | MIT（编译产物） |

**本仓库不包含 FastCtx 的任何源码或二进制。** 上游 0.4.1 已把 FastCtx 从分发中移除，
只保留许可文本在 `licenses/fastctx/`；本仓库原样保留那个目录以满足 Apache-2.0 的
通知义务，但不使用其内容。

## MIT 要求什么

MIT 只有一条实质要求：

> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.

即：**任何再分发（源码或二进制）都必须保留 `LICENSE` 里的版权声明与许可文本。**

本仓库的做法：

- `LICENSE` 与 `NOTICE` 原样保留，未做任何修改
- 每个编译产物的 `provenance.json` 记录 `"source": "native/Cargo.lock + native/src + ..."`
- `README.md` 与 `docs/UPSTREAM.md` 明确标注衍生关系

## 二进制再分发

如果你把 `prebuilt/linux-arm64/dsh-ops-worker` 单独分发（例如放进自己的镜像），
MIT 要求你同时提供版权声明与许可文本。最低限度：

```
本二进制编译自 dsh-ops 0.4.1（MIT AND Apache-2.0）
Copyright (c) 2026 T-Auto and the dsh-ops contributors
许可全文见 https://github.com/T-Auto/dsh-ops/blob/v0.4.1/LICENSE
```

## 本项目自己的部分

本项目新增的内容（workflow、`scripts/install.sh`、`docs/`、补丁的差异部分）
同样以 MIT 发布，版权归本项目贡献者。没有额外的限制。

## 如果上游将来改变许可

上游若从 MIT 改成更严格的许可，本仓库的**新版本**需要遵守新许可；
已经按 MIT 发布的版本不受追溯影响。补丁本身是独立创作，可以继续以 MIT 分发，
但把它应用到新版本上游时，需要遵守新版本上游的许可。
