#!/bin/bash

# 卸载 VCAM 插件

echo "🗑️  卸载 VCAM 插件..."
echo ""

ssh -p 2222 root@localhost << 'ENDSSH'
echo "📋 当前安装的版本："
dpkg -l | grep vcam

echo ""
echo "🗑️  执行卸载..."
dpkg -r com.trizau.sileo.vcam

echo ""
echo "✅ 卸载完成！正在重启 SpringBoard..."
killall -9 SpringBoard
ENDSSH

echo ""
echo "✅ 卸载完成！"
