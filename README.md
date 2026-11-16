<h1 align="center">KAPlus</h1>

<p align="center">
  <b>Komari Agent 部署与管理工具</b><br>
  装、开、管、删，一个菜单搞定。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.0.21-d6336c?style=flat-square" alt="version">
  <img src="https://img.shields.io/badge/platform-Linux-7048e8?style=flat-square" alt="platform">
  <img src="https://img.shields.io/badge/init-systemd%20%7C%20OpenRC-1c7ed6?style=flat-square" alt="init">
  <img src="https://img.shields.io/badge/shell-bash%204%2B-0ca678?style=flat-square" alt="shell">
  <img src="https://img.shields.io/badge/UI-TUI-f59f00?style=flat-square" alt="ui">
</p>

---

## 它是什么

`ka` 是给 [Komari](https://github.com/komari-monitor/komari) 监控面板用的 **Agent 管理工具**。不用记参数、不用手写 systemd 服务，装节点、多开、改配置、升级、卸载都在一个菜单里完成。

```
  K O M A R I   A G E N T
  ────────────────────────────────────────
  ka v0.0.21  · 多实例部署 · NAT 友好
```

## 功能特性

| | 特性 | 说明 |
|:--:|---|---|
| 🚀 | **一键安装** | 一条命令装好，之后输入 `ka` 即可 |
| 🧩 | **多实例** | 一台机器开多个，目录 / 服务名 / token 自动隔离 |
| 🔍 | **自动纳管** | 已经装过的 Agent 自动发现，不用重装 |
| 🌐 | **按网卡批量** | 一块网卡一个节点，适合多 IP 的 NAT 机器 |
| 🔑 | **两种认证** | 节点 Token，或自动发现密钥批量注册 |
| 🛠 | **全生命周期** | 改参数、升级、接管、备注、卸载都有入口 |
| 🩺 | **自检** | 服务状态、开机自启、面板连通一键检查 |
| ⬆️ | **自更新** | `ka update` 拉取新版本，旧版本保留可回退 |

## 安装

> 需要 Linux + root，支持 systemd 与 OpenRC（Alpine）。

**root 用户（大多数 VPS）**

```bash
wget -qO /tmp/ka.sh https://raw.githubusercontent.com/Eoyz369/KAPlus/main/ka.sh && bash /tmp/ka.sh self-install
```

**普通用户（系统里有 sudo）**

```bash
wget -qO /tmp/ka.sh https://raw.githubusercontent.com/Eoyz369/KAPlus/main/ka.sh && sudo bash /tmp/ka.sh self-install
```

没有 `wget` 可以用 `curl`：

```bash
curl -fsSL https://raw.githubusercontent.com/Eoyz369/KAPlus/main/ka.sh -o /tmp/ka.sh && bash /tmp/ka.sh self-install
```

装完直接输入：

```bash
ka
```

## 使用

打开菜单：

```
  ┃  主菜单
     v0.0.21 · OpenRC · 已发现 1 个实例

   ❯ 安装 / 新增实例
     实例管理
     批量操作
     自检
     卸载 / 清理
     检查更新
     退出

   ↑↓ 移动 · Enter 选择 · q 退出
```

安装向导共 5 步：

1. **面板地址** — 已有实例时自动沿用，回车即可
2. **认证方式** — 节点 Token / 自动发现密钥
3. **节点 Token** — 粘贴 token，一行一个，空行结束
4. **高级参数** — 采集间隔、开关、网卡、挂载点
5. **确认部署** — 回车开始，`b` 返回改参数，`q` 取消

不喜欢菜单也可以直接敲命令：

| 命令 | 作用 |
|---|---|
| `ka status` | 查看全部实例状态 |
| `ka doctor` | 一键自检 |
| `ka logs komari-agent-1` | 查看指定实例日志 |
| `ka logs clean` | 清理日志，可开每日自动清理 |
| `ka batch` | 批量重启 / 停止 / 启动 / 升级 / 卸载 |
| `ka adopt` | 接管外部实例 |
| `ka upgrade` | 原地升级 Agent |
| `ka update` | 更新 ka 自身 |
| `ka uninstall` | 卸载实例 |
| `ka self-uninstall` | 卸载 ka（保留实例） |

## 常见问题

<details>
<summary><b>机器上已经有 Agent，为什么没显示？</b></summary>

脚本会扫描 systemd 和 OpenRC 注册的服务，正常安装的 Agent 都能识别；手工 <code>nohup</code> 起的进程会单独标成「进程」。
</details>

<details>
<summary><b>卸载一个实例，会影响其他实例吗？</b></summary>

不会。检测到目录被其他实例共用时，只删服务，不删目录。
</details>

<details>
<summary><b>自动发现能一台机器开多个吗？</b></summary>

可以。每个实例必须使用独立目录，工具默认就是这样安装的。
</details>

<details>
<summary><b>更新下载失败怎么办？</b></summary>

加一个 GitHub 代理再试：

<pre><code>GH_PROXY=https://ghproxy.net ka update</code></pre>
</details>

## 反馈

有问题或建议，欢迎开 [Issues](https://github.com/Eoyz369/KAPlus/issues)。

<p align="center">
  <sub>如果这个工具帮你省了时间，点个 ⭐ 支持一下</sub>
</p>
