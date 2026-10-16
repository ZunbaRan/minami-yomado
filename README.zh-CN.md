# Minami Yomado

**给 Agent 一个虚拟工作桌面，用一个实时 PiP 观察整个任务。**

本项目提供 macOS 本地 MCP：创建和配置虚拟显示器，移动指定任务窗口，打开独立的全桌面实时预览，以及恢复窗口。Minami computer-use / browser 可以继续负责应用操作。

- PiP 默认 **480×300**，记住你调整后的尺寸和位置，重开或重启后也保留。
- 同一个工作区复用一个 PiP，工作过程中无需反复打开或切换镜像目标。
- 关闭 PiP 或断开 MCP 不会关闭虚拟工作区。

## 安装到 Codex CLI

需要 Apple Silicon Mac、Node.js 20+。自动注册还需要 Codex CLI。发行包包含原生 helper 和 MCP 运行依赖，无需 Xcode 或 npm。

```bash
curl -fsSL https://raw.githubusercontent.com/ZunbaRan/minami-yomado/mcp-v0.1.0/scripts/install.sh -o /tmp/minami-yomado-install.sh
bash /tmp/minami-yomado-install.sh --codex
```

完成后启动新的 Codex 会话。首次使用时，由用户在 macOS 系统设置中授予辅助功能/设备控制与屏幕录制权限。无需 API key。

其他 MCP 客户端：去掉 `--codex`，将输出的配置合并到客户端设置。配置同时保存在 `~/.local/share/minami-yomado/mcp-config.json`。

[完整安装与故障排查](docs/quickstart.md) · [下载发行版](https://github.com/ZunbaRan/minami-yomado/releases/tag/mcp-v0.1.0) · [Agent 指南](AGENTS.md) · [英文](README.md)

## 源码安装

```bash
git clone https://github.com/ZunbaRan/minami-yomado.git
cd minami-yomado
npm ci --ignore-scripts
npm run build
npm run setup -- --codex
```

源码编译需要 Xcode Command Line Tools。升级前先恢复任务窗口、停止工作区；安装器不会强制停止正在工作的桌面。

```bash
npm run doctor
npm run doctor -- --connect
```

第一次任务可以告诉 Agent：检查权限，创建“Agent Work”工作区，打开一个小 PiP，只移动本任务的明确窗口，沿用我的尺寸，不要反复重开；结束时保存成果并恢复窗口。

## 边界

PiP 只读。虚拟显示器共享当前 macOS 登录会话、焦点和输入，不是隔离电脑。保持实体屏开启且为主屏。

首个 MCP 发行版 `mcp-v0.1.0` 为 Apple Silicon 构建，使用 ad-hoc 签名，**未经过 Apple 公证**。macOS 14 是编译部署目标；实际验证环境为 macOS 27.0.1，不代表所有旧版系统或 Intel 机器均受支持。安装器不会清除 quarantine 或绕过 Gatekeeper；可按系统安全流程审核或从源码编译。

本项目基于 [chekusu/yomado](https://github.com/chekusu/yomado)，保留 MIT 许可。上游 GUI、自动更新器和版本号与本 MCP 独立。[上游原始文档](README.upstream.zh-CN.md) · [LICENSE](LICENSE)
