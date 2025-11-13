#!/bin/bash

# VCAM Hello World 测试安装脚本

echo "==============================================="
echo "🧪 VCAM Hello World 测试版安装"
echo "==============================================="
echo ""

DEB_FILE="packages/com.trizau.sileo.vcam_1.0.0_iphoneos-arm.deb"

if [ ! -f "$DEB_FILE" ]; then
    echo "❌ 找不到 deb 文件: $DEB_FILE"
    exit 1
fi

echo "📦 deb 文件: $DEB_FILE"
echo "📦 大小: $(ls -lh $DEB_FILE | awk '{print $5}')"
echo ""

# 检查 iproxy
if ! pgrep -x "iproxy" > /dev/null; then
    echo "🔧 启动 iproxy..."
    iproxy 2222 22 > /dev/null 2>&1 &
    sleep 3
fi

echo "📤 传输 deb 文件到设备..."
scp -P 2222 "$DEB_FILE" root@localhost:/var/root/vcam_test.deb

if [ $? -ne 0 ]; then
    echo "❌ 传输失败！请检查："
    echo "   1. iPhone 是否通过 USB 连接"
    echo "   2. SSH 是否已安装并运行"
    echo "   3. 密码是否为 alpine"
    exit 1
fi

echo ""
echo "📲 安装到设备..."
ssh -p 2222 root@localhost << 'ENDSSH'
dpkg -i /var/root/vcam_test.deb
echo ""
echo "✅ 安装完成！正在重启 SpringBoard..."
killall -9 SpringBoard
ENDSSH

if [ $? -eq 0 ]; then
    echo ""
    echo "==============================================="
    echo "✅ 安装成功！"
    echo "==============================================="
    echo ""
    echo "📝 测试说明："
    echo "   1. SpringBoard 会自动重启"
    echo "   2. 重启后等待 3 秒会弹出提示框"
    echo "   3. 查看系统日志验证 hook 是否工作"
    echo ""
    echo "🔍 查看日志命令："
    echo "   ssh -p 2222 root@localhost"
    echo "   log stream --predicate 'processImagePath contains \"SpringBoard\"' | grep VCAM"
    echo ""
else
    echo "❌ 安装失败"
    exit 1
fi
