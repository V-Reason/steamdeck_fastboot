# 国区SteamDeck开机速度优化

## 简介

针对国区（或受限网络环境）Steam Deck 用户的开机启动优化工具。

通过跳过 SteamOS 开机时的系统更新检测，

将因网络超时导致的 2-3 分钟开机等待时间缩短至 30 秒左右，

并正常实现登陆、云存档同步等

## 使用教程

**注意：需要执行用户有`sudo`权限，执行过程可能需要输入一次密码**

0. 下载

    进入桌面模式，打开终端（Konsole）执行

    ```Bash
    git clone https://github.com/V-Reason/steamdeck_fastboot.git
    ```

    **后续操作都要在脚本文件夹下执行**，

    当然，在图形化界面下 双击执行 也可以：

    ```Bash
    # 切换到脚本文件夹下
    cd steamdeck_fastboot
    ```

1. 安装

   ```Bash
   ./install.sh
   ```

2. 检查状态（需要在终端才能查看输出）

   ```Bash
   ./check_status.sh
   ```

   如果安装成功，可以看到 `active (running)` 的字眼

3. 卸载

   ```Bash
   ./uninstall.sh
   ```

## 文件结构

```Plaintext
.
├── Source/                    # 逻辑目录
│   ├── steamdeck_fastboot.service # 所安装的系统服务文件
│   ├── steamdeck_fastboot.sh      # 核心脚本 on/off/wait/status 逻辑
│   └── steamdeck_fastboot_service_manager.sh # 安装逻辑，内部调用steamdeck_fastboot.sh
├── install.sh                 # 安装脚本
├── uninstall.sh               # 卸载脚本
├── check_status.sh            # 状态检查脚本
├── .gitignore
├── LICENSE
└── README.md
```

## 技术原理

### 开机缓慢原因

> *就像是有时候无法直连Steam商城一样*

SteamOS 每次冷启动时都会尝试连接服务器检查系统更新。

在国区等特定网络环境下，由于无法直连 Steam 更新服务器，

系统会不断重连直至 **超时** 后放弃连接。

这个过程通常长达 **1-2 分钟**，系统才会放弃更新并进入登录界面。

### 优化原理

本工具的核心逻辑如下：

1. **屏蔽**：在开机网络初始化阶段，通过修改 `/etc/hosts` 将 Steam 更新服务器域名指向 `0.0.0.0`
2. **跳过**：SteamOS 尝试联网时会立即收到“连接拒绝”信号（而不是漫长的等待超时），从而瞬间放弃更新检查，直接进入 UI 加载阶段
3. **恢复**：脚本实时监控 Steam 底层日志 `connection_log.txt`。一旦捕捉到 **`Connect() starting connection`** 信号（意味着已跳过更新，正在初始化用户登录），脚本会移除屏蔽规则，正常进行后续的登陆、云存档同步等网络功能

### 可替代方案

关机之前开启 **飞行模式** 即可。

SteamOS在开机时，检测到没有网络，

会直接跳过任何的网络连接过程（也包括登陆、云存档等等）

### 开机时间构成

> *第4部分是该代码的优化部分*

1. 0s~5s —— Linux系统自检
2. 6s~25s —— SteamOS系统自检
3. 26s~30s —— 开机动画
4. 31s之后 —— Steam更新、登陆等

## 技术细节

> *更多实现详细请见代码注释，我写得很详细了*

通过安装 Linux 系统服务，在开关机的同时自动执行 hosts 屏蔽脚本。

服务在 Linux 网络功能启动后启动，之后实时监控 Steam 的底层日志`connection_log.txt`，

在捕捉到 `Connect() starting connection`日志之后，说明 Steam 已跳过OS更新并开始进行账号登陆和UI初始化，

此时脚本立刻移除 hosts 屏蔽规则，恢复 Steam 连接

## 调试建议

> *如果你需要调试或验证脚本逻辑，可以使用以下命令*

1. 手动测试脚本逻辑

   ```Bash
   # 关于steamdeck_fastboot.sh
   # 手动开启屏蔽
   sudo ./Source/steamdeck_fastboot.sh on
   # 监控模式（手动调用wait无意义，不建议这么做，因为需要配合 Steam 重启才有用）
   sudo ./Source/steamdeck_fastboot.sh wait
   # 手动解除屏蔽
   sudo ./Source/steamdeck_fastboot.sh off
   
   # 关于steamdeck_fastboot_service_manager.sh
   # 手动安装服务
   sudo ./Source/steamdeck_fastboot_service_manager.sh install
   # 手动检查服务状态
   sudo ./Source/steamdeck_fastboot_service_manager.sh status
   # 手动卸载服务
   sudo ./Source/steamdeck_fastboot_service_manager.sh uninstall
   ```

2. 查看 `Hosts` 文件当前状态

   ```Bash
   cat /etc/hosts
   ```

   在屏蔽规则开启的状态下，你应该能看到被 `Steam_Fastboot_Block` 标记包裹的规则：

   ```txt
   # --- Steam_Fastboot_Block_Start --- 
   0.0.0.0 api.steampowered.com 
   0.0.0.0 store.steampowered.com  
   0.0.0.0 steamcommunity.com       
   0.0.0.0 client-download.steampowered.com    
   0.0.0.0 client-update.steamstatic.com
   :: api.steampowered.com
   :: store.steampowered.com   
   :: steamcommunity.com 
   :: client-download.steampowered.com                       
   :: client-update.steamstatic.com                                                                    # --- Steam_Fastboot_Block_End ---
   ```

3. 查看服务运行日志

   查看脚本的实时运行情况，确认是否成功捕捉到启动信号，你可以看到代码中写的日志信息：

   ```Bash
   journalctl -u steamdeck_fastboot.service -b
   ```

4. 查看 Steam 日志文件

   确认 Steam 的网络活动状态：

   ```Bash
   tail -n 100 /home/deck/.local/share/Steam/logs/connection_log.txt
   ```


## 声明

> 还是一个学生，请多包涵

脚本由 个人 + Gemini 协同开发，

工作流：人工设计逻辑 -> 人工编写脚本 -> AI优化脚本 -> 人工审查脚本 -> 实机测试 -> 重复迭代

注：所有代码都已经人工审查多遍，并且在本人的 SteamDeck 上进行过多次测试，确保安全有效

