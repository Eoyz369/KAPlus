# KAPlus

给 [Komari](https://github.com/komari-monitor/komari) 面板用的 Agent 管理工具。一条命令装好，之后装节点、多开、改参数、升级、卸载都在菜单里点。

支持 systemd 和 OpenRC（Alpine），Linux only。

## 能做什么

- **一条命令安装** Agent，不用记参数
- **一台机器开多个**，目录、服务名、token 自动隔离
- **已经装过的 Agent 会自动发现**，直接纳入管理，不用重装
- **按网卡批量**：一块网卡一个节点，适合多 IP 的 NAT 机器
- **支持自动发现密钥**，不用先在面板建节点
- 改参数、升级、接管**不用重新输 token**
- 自带**自检**和**更新**

## 安装

```bash
wget -qO /tmp/ka.sh https://raw.githubusercontent.com/Eoyz369/KAPlus/main/ka.sh && sudo bash /tmp/ka.sh self-install
```

用 curl 也行：

```bash
curl -fsSL https://raw.githubusercontent.com/Eoyz369/KAPlus/main/ka.sh -o /tmp/ka.sh && sudo bash /tmp/ka.sh self-install
```

装完直接输入：

```bash
ka
```

需要 root 权限。

## 使用

```
  K O M A R I   A G E N T
  ────────────────────────────────────────
  ┃  主菜单
     v0.0.17 · OpenRC · 已发现 1 个实例

   ❯ 安装 / 新增实例
     实例管理
     批量操作
     自检
     卸载 / 清理
     检查更新
     退出

   ↑↓ 移动 · Enter 选择 · q 退出
```

- **安装 / 新增实例**：5 步向导，粘贴 token 就能装完
- **实例管理**：看日志、启停、改参数、升级、接管、备注、卸载
- **批量操作**：一次重启 / 停止 / 启动全部实例
- **自检**：检查服务状态、开机自启、面板连通

不习惯菜单也可以直接用命令：

| 命令 | 作用 |
|---|---|
| `ka status` | 看所有实例状态 |
| `ka doctor` | 一键自检 |
| `ka logs komari-agent-1` | 看某个实例的日志 |
| `ka update` | 更新 ka 自己 |
| `ka uninstall` | 卸载实例 |
| `ka self-uninstall` | 卸载 ka（保留实例） |

## 常见问题

**机器上已经有 Agent，为什么没显示？**
脚本会扫描 systemd 和 OpenRC 里的服务，只要是正常注册的服务都能识别。极少数手工 `nohup` 起的进程会单独标成「进程」。

**卸载一个实例，会把别的实例弄坏吗？**
不会。检测到目录被其他实例共用时只删服务，不删目录。

**自动发现能一台机器开多个吗？**
可以。每个实例必须有自己的目录，工具默认就是这么装的。

**更新下载失败？**
加个 GitHub 代理再试：

```bash
GH_PROXY=https://ghproxy.net ka update
```

## 反馈

有问题或建议请开 [Issues](https://github.com/Eoyz369/KAPlus/issues)。
