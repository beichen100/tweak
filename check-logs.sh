#!/bin/bash

# 查看 VCAM 测试日志

echo "🔍 连接到设备查看日志..."
echo "按 Ctrl+C 退出"
echo "==============================================="
echo ""

ssh -p 2222 root@localhost << 'ENDSSH'
# 查看最近的 SpringBoard 崩溃日志
echo "📋 检查崩溃日志..."
ls -lt /var/mobile/Library/Logs/CrashReporter/*SpringBoard* 2>/dev/null | head -5

echo ""
echo "📋 检查 panic 日志（最近5分钟）..."
find /var/mobile/Library/Logs/CrashReporter -name "panic*.ips" -mmin -5 2>/dev/null

echo ""
echo "📋 查看系统日志（最后100行，包含 VCAM）..."
log show --last 5m --predicate 'eventMessage contains "VCAM"' 2>/dev/null | tail -50

echo ""
echo "📋 查看 syslog（如果可用）..."
tail -50 /var/log/syslog 2>/dev/null | grep -i vcam || echo "syslog 不可用"

echo ""
echo "📋 验证插件是否已加载..."
ls -lh /Library/MobileSubstrate/DynamicLibraries/VCAM.*

echo ""
echo "📋 检查 SpringBoard 进程..."
ps aux | grep SpringBoard | grep -v grep
ENDSSH
