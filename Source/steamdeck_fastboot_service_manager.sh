#!/bin/bash

# --- 配置区域 ---
# .service文件名称
SERVICE_NAME="steamdeck_fastboot.service"
# 屏蔽功能脚本路径
CORE_SCRIPT="$CURRENT_DIR/steamdeck_fastboot.sh"
# 获取当前脚本所在的绝对路径
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 整理获得 源文件路径 和 目标文件路径
SOURCE_SERVICE_FILE="$CURRENT_DIR/$SERVICE_NAME"
TARGET_SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# --- 权限检查 ---
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请使用 sudo 运行此脚本"
    echo "   用法：sudo $0 [install | uninstall | status]"
    exit 1
fi

# --- 功能函数 ---
# 查询服务安装与否
check_status() {
    echo "🔍 --- Systemd 服务状态 ---"
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        systemctl status "$SERVICE_NAME" --no-pager
    else
        echo "⚪ 服务未安装"
    fi
    
    echo "🔍 --- /etc/hosts 屏蔽状态 ---"
    # 如果屏蔽脚本存在
    if [ -f "$CORE_SCRIPT" ] && [ -x "$CORE_SCRIPT" ]; then
        # 查询屏蔽规则状态
        "$CORE_SCRIPT" status
    else
        echo "⚠️ 无法找到或执行核心脚本: $CORE_SCRIPT"
    fi
}
# 安装服务
install_service() {
    echo "🔧 正在安装/更新服务..."

    # 1. 预清理：尝试停止旧服务，忽略报错
    systemctl stop "$SERVICE_NAME" 2>/dev/null

    # 2. 检查屏蔽脚本
    if [ ! -f "$CORE_SCRIPT" ]; then
        echo "❌ 错误：找不到核心脚本 $CORE_SCRIPT"
        exit 1
    fi
    # 防止脚本没有执行权限
    chmod +x "$CORE_SCRIPT"

    # 3. 动态修正 .service 文件内容
    # 使用 sed 直接修改源文件，确保路径正确且逻辑符合要求
    echo "📝 修正.service文件中"
    echo "📝 修正路径指向：$CURRENT_DIR"

    # 设置Type=oneshot
    if grep -q "^Type=" "$SOURCE_SERVICE_FILE"; then
        # 设置Type为oneshot
        sed -i "s|^Type=.*|Type=oneshot|g" "$SOURCE_SERVICE_FILE"
    else
        # 如果没有Type=，就在 [Service] 下面插入Type=oneshot
        sed -i "/\[Service\]/a Type=oneshot" "$SOURCE_SERVICE_FILE"
    fi

    # 设置 RemainAfterExit=yes
    if grep -q "^RemainAfterExit=" "$SOURCE_SERVICE_FILE"; then
        sed -i "s|^RemainAfterExit=.*|RemainAfterExit=yes|g" "$SOURCE_SERVICE_FILE"
    else
        sed -i "/\[Service\]/a RemainAfterExit=yes" "$SOURCE_SERVICE_FILE"
    fi

    # 设置 ExecStart 为 wait 调用
    # 开机时，执行 steam_fastboot.sh wait 命令，以关闭屏蔽规则
    sed -i "s|^ExecStart=.*|ExecStart=$CORE_SCRIPT wait|g" "$SOURCE_SERVICE_FILE"

    # 设置 ExecStop 为 on 调用
    # 关机时，执行 steam_fastboot.sh on 命令，写入屏蔽规则，为下次开机做准备
    sed -i "s|^ExecStop=.*|ExecStop=$CORE_SCRIPT on|g" "$SOURCE_SERVICE_FILE"

    # 4. 部署.service文件
    cp "$SOURCE_SERVICE_FILE" "$TARGET_SERVICE_FILE"
    chmod 644 "$TARGET_SERVICE_FILE"

    # 5. 激活服务
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    # 6. 重启服务以应用新配置
    # 注意：此时运行 restart 会触发 ExecStop(on) 然后 ExecStart(wait)
    # 如果你现在正在用 Steam，这也没关系，wait 会检测到日志并立即解封
    systemctl restart "$SERVICE_NAME"

    echo "✅ 服务已部署并激活！"
    echo "----------------------------------------"
    # 安装成功后自动检测一次屏蔽规则状态
    check_status
}
# 卸载服务
uninstall_service() {
    echo "🗑️ 正在卸载服务..."

    # 1. 停止并禁用，忽略报错
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # 2. 删除部署文件
    rm -f "$TARGET_SERVICE_FILE"
    
    # 3. 重载配置
    systemctl daemon-reload
    
    # 4. 关闭屏蔽
    echo "🧹 清理卸载残留状态..."
    if [ -f "$CORE_SCRIPT" ]; then
        "$CORE_SCRIPT" off
    fi

    echo "✅ 服务已移除。"
    echo "----------------------------------------"
    # 卸载成功后自动检测一次屏蔽规则状态
    check_status
}

# --- 主逻辑 ---
case "$1" in
    install)
        install_service
        ;;
    uninstall)
        uninstall_service
        ;;
    status)
        check_status
        ;;
    *)
        echo "用法: sudo $0 [install | uninstall | status]"
        echo "  install   : 部署并激活服务 (支持重复运行更新)"
        echo "  uninstall : 停止并移除服务 (支持重复运行)"
        echo "  status    : 查看服务运行状态和屏蔽状态"
        exit 1
        ;;
esac
