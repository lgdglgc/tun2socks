# 🚀 tun2socks - ocserv SOCKS5 中转面板

一个专为 `ocserv` (AnyConnect VPN) 打造的流量一转多中继分流管理工具。基于 `tun2socks` 与 Linux 策略路由，实现将连接到 `ocserv` 的客户端流量，经由指定的落地 SOCKS5 代理进行二次中继分流转发。

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-orange.svg)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/Bash-4.0+-brightgreen.svg)](https://www.gnu.org/software/bash/)
[![tun2socks](https://img.shields.io/badge/tun2socks-v2.6.0-blue.svg)](https://github.com/xjasonlyu/tun2socks)
[![GitHub](https://img.shields.io/badge/GitHub-lgdglgc/tun2socks-blue?logo=github)](https://github.com/lgdglgc/tun2socks)

---

## 📖 核心功能与特色

*   🤖 **自动检测 CPU 架构**：移除硬编码限制，自动匹配部署 `amd64`、`arm64`、`386`、`armv7` 等架构的二进制包，完美支持包括甲骨文 ARM 在内的各种主流 VPS 云服务器。
*   ⚙️ **最新的核心依赖**：一键部署最新稳定版 `tun2socks v2.6.0`。
*   🔒 **灵活的落地代理**：支持免密或带有账号密码认证 of SOCKS5 代理。
*   🛡️ **幂等性与零规则残留**：采用 `lookup 200` 动态匹配清除机制，防止在 IP 变更或非正常重启后在系统中残留多余的路由规则；每次启动前执行防冲突环境初始化。
*   🚀 **双模式运行**：
    *   **交互式图形化控制台**：提供日常运维管理菜单（启停、重启、状态诊断、实时日志）。
    *   **无人值守命令行模式**：支持携带参数静默一键安装或卸载，便于融入各类自动化脚本。
*   ⚡ **轻量且冲突少**：使用 `172.23.45.1/30` 极简内部网段建立 TUN 隧道，极大地降低了与 Docker 或常见私网 IP 发生冲突的概率。

---

## 🛠️ 快速开始

### 方式一：一键快速执行 (从 GitHub 运行)

如果您在服务器上想一键直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lgdglgc/tun2socks/main/tun2socks.sh)
```
或使用 wget：
```bash
bash <(wget -qO- https://raw.githubusercontent.com/lgdglgc/tun2socks/main/tun2socks.sh)
```

---

### 方式二：本地克隆与运行

1. 下载脚本到您的 VPS 并赋予可执行权限：
   ```bash
   wget -O tun2socks.sh https://raw.githubusercontent.com/lgdglgc/tun2socks/main/tun2socks.sh
   chmod +x tun2socks.sh
   ```

2. **交互式面板模式**：
   直接运行脚本，进入可视化操作主界面：
   ```bash
   ./tun2socks.sh
   ```
   *注：安装服务后，脚本会自动注册为全局命令。您可以在系统任意路径下直接输入 `tun2socks-menu` 随时唤起此管理面板。*

   **菜单预览：**
   ```
   =================================================
         ocserv -> SOCKS5 流量一键管理面板
   =================================================
    1. 安装与配置 tun2socks 中转服务
    2. 卸载并清理 tun2socks 服务
    3. 查看运行状态与当前配置
    4. 重启中转服务
    5. 停止中转服务
    6. 查看中转服务实时运行日志
    0. 退出脚本
   =================================================
   ```

3. **命令行静默部署模式 (无人值守一键式)**：
   可通过参数直接执行安装或卸载，适合自动化脚本：
   *   **一键静默安装 (有账号密码认证)**：
       ```bash
       ./tun2socks.sh --install --subnet 192.168.1.0/24 --proxy socks5://myuser:mypassword@1.2.3.4:1080
       ```
   *   **一键静默安装 (无认证)**：
       ```bash
       ./tun2socks.sh -i --subnet 192.168.1.0/24 --proxy socks5://1.2.3.4:1080
       ```
   *   **一键静默卸载**：
       ```bash
       ./tun2socks.sh --uninstall
       ```

---

## 📊 命令行参数说明

| 选项 (长 / 短) | 说明 |
| :--- | :--- |
| `-i, --install` | 一键无人值守安装模式 |
| `-u, --uninstall` | 一键无人值守卸载模式 |
| `--subnet <CIDR>` | 指定 `ocserv` 客户端分配的子网段 (例如 `192.168.1.0/24`) |
| `--proxy <SOCKS5>` | 指定落地 SOCKS5 代理连接串 (例如 `socks5://user:pass@ip:port` 或 `socks5://ip:port`) |
| `-h, --help` | 显示脚本参数使用帮助 |

---

## 📂 运维与管理

系统服务在部署后，会创建以下文件：
*   **Systemd 单元文件**: `/etc/systemd/system/tun2socks.service`
*   **网络激活脚本**: `/etc/tun2socks-up.sh`
*   **网络清理脚本**: `/etc/tun2socks-down.sh`
*   **tun2socks 核心路径**: `/usr/local/bin/tun2socks`

### 常用服务命令：
```bash
# 查看中转服务状态
systemctl status tun2socks

# 启动中转服务
systemctl start tun2socks

# 停止中转服务
systemctl stop tun2socks

# 重启中转服务
systemctl restart tun2socks

# 实时查看中转日志
journalctl -u tun2socks -f
```

---

## 🤝 参与贡献与致谢

*   感谢 [@xjasonlyu](https://github.com/xjasonlyu) 带来的优秀开源工具 [tun2socks](https://github.com/xjasonlyu/tun2socks)。

---

## 📄 授权协议

本项目基于 MIT 协议开源，详情请参阅 [LICENSE](LICENSE) 文件。
