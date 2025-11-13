#!/bin/bash

# 推送到 GitHub 触发自动构建

echo "=================================="
echo "🚀 推送到 GitHub Actions"
echo "=================================="
echo ""

# 检查是否在 git 仓库中
if [ ! -d ".git" ]; then
    echo "⚠️  这不是一个 git 仓库，正在初始化..."
    git init
    echo "✅ Git 仓库已初始化"
fi

# 检查远程仓库
REMOTE=$(git remote -v | grep origin | head -1)
if [ -z "$REMOTE" ]; then
    echo ""
    echo "❌ 未配置 GitHub 远程仓库"
    echo ""
    echo "请先创建 GitHub 仓库，然后运行："
    echo "  git remote add origin https://github.com/你的用户名/你的仓库名.git"
    echo ""
    exit 1
else
    echo "✅ 远程仓库: $REMOTE"
fi

echo ""
echo "📝 当前状态:"
git status --short

echo ""
echo "=== 添加文件 ==="

# 添加所有必要文件
git add Tweak.x
git add Makefile
git add control
git add .github/workflows/build.yml
git add *.plist 2>/dev/null || true
git add postinst postrm 2>/dev/null || true

echo "✅ 文件已暂存"

echo ""
read -p "📝 输入 commit 消息 (默认: Test build with iOS 14.5 SDK): " COMMIT_MSG
COMMIT_MSG=${COMMIT_MSG:-"Test build with iOS 14.5 SDK"}

git commit -m "$COMMIT_MSG"

if [ $? -eq 0 ]; then
    echo "✅ Commit 成功"
else
    echo "⚠️  没有更改需要提交"
fi

echo ""
echo "=== 推送到 GitHub ==="

# 获取当前分支
BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
    BRANCH="master"
    echo "⚠️  当前不在任何分支，使用: $BRANCH"
fi

echo "📤 推送分支: $BRANCH"
git push -u origin "$BRANCH"

if [ $? -eq 0 ]; then
    echo ""
    echo "=================================="
    echo "✅ 推送成功！"
    echo "=================================="
    echo ""
    echo "🔍 查看构建状态："
    echo "   访问你的 GitHub 仓库 → Actions 标签"
    echo ""
    echo "⏱️  预计构建时间："
    echo "   - 首次: 5-10 分钟（下载依赖）"
    echo "   - 后续: 1-2 分钟（使用缓存）"
    echo ""
    echo "📦 构建完成后："
    echo "   在 Actions 页面下载 Artifacts"
    echo "   文件名: VCAM-Test-iOS14.6-xxxxxx"
    echo ""
else
    echo "❌ 推送失败"
    echo ""
    echo "常见问题："
    echo "1. 检查是否已登录 GitHub"
    echo "2. 检查远程仓库地址是否正确"
    echo "3. 检查是否有推送权限"
    exit 1
fi
