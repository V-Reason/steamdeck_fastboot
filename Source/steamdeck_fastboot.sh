#!/bin/bash

# 配置区域
HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/etc/hosts.bak"

# steamIP缓存文件路径
STEAM_IP_CACHE_FILE="/home/deck/.local/share/Steam/update_hosts_cached.vdf"

# 标记定义
START_MARKER="# --- Steam_Fastboot_Block_Start ---"
END_MARKER="# --- Steam_Fastboot_Block_End ---"

# 目标 IP (同时屏蔽 IPv4 和 IPv6)
TARGET_IP_V4="0.0.0.0"
TARGET_IP_V6="::"

# 定义要屏蔽的域名列表
DOMAINS=(
    # --- Steam 核心服务与 API ---
    "api.steampowered.com"
    "store.steampowered.com"
    "steamcommunity.com"

    # --- 客户端更新与下载 ---
    "client-download.steampowered.com"
    "client-update.steamstatic.com"
    "media.steampowered.com"

    # --- SteamOS & Steam Deck 系统更新 ---
    "images.steamos.cloud"
    "steamdeck-atomupd.steamos.cloud"
    "steamdeck-images.steamos.cloud.akamaized.net"

    # --- CDN 加速节点 ---
    "cdn.akamai.steamstatic.com.edgesuite.net"
    "client-update.akamai.steamstatic.com"
    "client-update.fastly.steamstatic.com"
    "client-update.queniuqe.com"
    "media.st.dl.eccdnx.com"
    "steamcdn-a.akamaihd.net"

    # 注意，这里不要屏蔽连接管理器服务器IP (CM Servers / Connection Managers)
    # 这些服务器负责 账号登陆、云存档同步 等, 很重要
)

# 核心功能函数

# 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "❌ 请使用 sudo 运行此脚本: sudo $0 [on|off]"
        exit 1
    fi
}

# 清理 Hosts 规则
clean_hosts_rules() {
    # 将hosts文件中自定义标记之间的文字删除
    if grep -q "$START_MARKER" "$HOSTS_FILE"; then
        sed -i "/$START_MARKER/,/$END_MARKER/d" "$HOSTS_FILE"
    fi
}

# 备份并隐藏 SteamIP 缓存
backup_steam_cache() {
    if [ -f "$STEAM_IP_CACHE_FILE" ]; then
        # 情况1: 原文件存在 -> 执行备份
        echo "📦 正在备份并隐藏 Steam IP 缓存..."
        mv "$STEAM_IP_CACHE_FILE" "${STEAM_IP_CACHE_FILE}.bak"
        echo "   (已备份至 ${STEAM_IP_CACHE_FILE}.bak)"
    elif [ -f "${STEAM_IP_CACHE_FILE}.bak" ]; then
        # 情况2: 原文件不在，但备份在 -> 之前已经处理过了
        echo "✅ Steam IP 缓存已被隐藏，无需重复操作。"
    else
        # 情况3: 啥都没找到
        echo "⚠️ 未发现缓存文件，跳过备份。"
    fi
}

# 恢复 SteamIP 缓存
restore_steam_cache() {
    if [ -f "${STEAM_IP_CACHE_FILE}.bak" ]; then
        mv "${STEAM_IP_CACHE_FILE}.bak" "$STEAM_IP_CACHE_FILE"
    fi
}

# 业务逻辑函数

# 开启屏蔽规则
enable_block() {
    # 清理旧 hosts 规则，防止重复写入
    clean_hosts_rules

    # 备份SteamIP缓存
    backup_steam_cache

    echo "🔒 正在写入屏蔽规则..."

    # 备份 hosts 文件
    cp "$HOSTS_FILE" "$BACKUP_FILE"

    # 写入屏蔽列表 (IPv4 + IPv6)
    echo "$START_MARKER" >> "$HOSTS_FILE"
    for domain in "${DOMAINS[@]}"; do
        echo "$TARGET_IP_V4 $domain" >> "$HOSTS_FILE"
    done
    for domain in "${DOMAINS[@]}"; do
        echo "$TARGET_IP_V6 $domain" >> "$HOSTS_FILE"
    done
    echo "$END_MARKER" >> "$HOSTS_FILE"
    
    echo "✅ 屏蔽已开启！Steam 开机更新检查将被跳过。"
    echo "   (当前 hosts 已备份至 $BACKUP_FILE)"
}

# 关闭屏蔽规则 (静默模式 - 无log，用于系统服务调用)
disable_block_silent() {
    # 清理 hosts 规则
    clean_hosts_rules
    # 使用备份恢复SteamIP缓存
    restore_steam_cache
}

# 关闭屏蔽规则 (公开模式 - 有log，用于用户手动调用)
disable_block() {
    # 检查权限
    check_root
    
    # 预检查是否有备份存在，给用户反馈 (log提示)
    local cache_restored="no"
    if [ -f "${STEAM_IP_CACHE_FILE}.bak" ]; then
        cache_restored="yes"
    fi

    # 关闭屏蔽规则（静默函数）
    disable_block_silent
    
    # log提示
    echo "🔓 屏蔽已移除！Steam 现在可以尝试更新了。"
    if [ "$cache_restored" == "yes" ]; then
        echo "📦 Steam IP 缓存已恢复。"
    fi
}

# 事件驱动等待（通过检查SteamLog文件）
wait_for_launch() {
    echo "👀 正在监控 Steam 启动信号..."
    
    # 目标日志文件
    LOG_FILE="/home/deck/.local/share/Steam/logs/connection_log.txt"
    # 目标关键词：开始尝试建立 WebSocket 连接，即SteamOS开始登陆账号
    TARGET_KEYWORD="Connect() starting connection"
    
    # 获取当前日志的行数，作为起始检查点，防止扫描到旧日志
    start_line=$(wc -l < "$LOG_FILE")
    
    # 设置超时时间 (秒)，防止卡死
    TIMEOUT=30
    elapsed=0
    
    while [ $elapsed -lt $TIMEOUT ]; do
        # 开始扫描
        # tail -n +$((start_line + 1)) 表示从 start_line 的下一行开始看直到末尾
        if tail -n +$((start_line + 1)) "$LOG_FILE" 2>/dev/null | grep -q "$TARGET_KEYWORD"; then
            echo "🚀 检测到 SteamOS 正在登陆账号！(检测耗时: ${elapsed}s)"
            echo "🔓 任务完成，正在解封..."
            disable_block
            return 0
        fi
        
        # 每 1 秒检查一次
        sleep 1
        ((elapsed++))
    done
    
    echo "⏰ 等待超时！ Steam 可能启动失败或日志未刷新，强制解封以防万一。"
    disable_block
}




# 主程序入口Main
check_root
case "$1" in
    on)
        enable_block
        ;;
    off)
        disable_block
        ;;
    wait)
	wait_for_launch
	;;
    status)
        if grep -q "$START_MARKER" "$HOSTS_FILE"; then
            echo "🔒 当前状态：[已开启屏蔽] (极速开机模式)"
        else
            echo "🔓 当前状态：[未屏蔽] (正常更新模式)"
        fi
        ;;
    *)
        echo "用法: sudo $0 [on | off | status]"
	echo "  on     : 开启hosts屏蔽，并备份于隐藏Steam IP缓存"
	echo "  off    : 关闭hosts屏蔽，并恢复Steam IP缓存"
	echo "  status : 查看当前是否启用hosts屏蔽规则"
        exit 1
        ;;
esac
