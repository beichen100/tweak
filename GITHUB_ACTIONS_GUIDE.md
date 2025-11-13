# GitHub Actions 构建指南

## 🎯 为什么使用 GitHub Actions？

经过测试确认：
- ❌ M4 Mac + iOS 26.1 SDK **无法**为 iOS 14.6 编译兼容插件
- ❌ 即使是最简单的 Hello World 也会导致 SpringBoard 崩溃
- ✅ **必须使用 iOS 14.x SDK** 才能生成兼容的二进制文件

**GitHub Actions 的优势：**
- ✅ 使用 Ubuntu Linux 环境
- ✅ 可以安装 iOS 14.5 SDK
- ✅ 完全自动化构建
- ✅ 免费使用（公开仓库）

---

## 📋 前置准备

### 1. 创建 GitHub 账号

如果还没有，请访问：https://github.com/signup

### 2. 创建新仓库

1. 登录 GitHub
2. 点击右上角 `+` → `New repository`
3. 填写信息：
   - **Repository name**: `vcam-test` (或任何名称)
   - **Visibility**: `Public` (私有仓库也可以，但免费配额更少)
   - **不要**勾选 "Add a README file"
4. 点击 `Create repository`

### 3. 记录仓库地址

创建完成后，复制显示的 HTTPS 地址，例如：
```
https://github.com/你的用户名/vcam-test.git
```

---

## 🚀 使用步骤

### 方法 1：使用脚本（推荐）

```bash
cd /Users/beichen/Documents/tweak

# 1. 配置远程仓库（仅首次需要）
git remote add origin https://github.com/你的用户名/vcam-test.git

# 2. 运行推送脚本
./push-to-github.sh
```

### 方法 2：手动操作

```bash
cd /Users/beichen/Documents/tweak

# 1. 初始化 git（如果还没有）
git init

# 2. 添加远程仓库
git remote add origin https://github.com/你的用户名/vcam-test.git

# 3. 添加文件
git add Tweak.x Makefile control .github/workflows/build.yml
git add *.plist postinst postrm

# 4. 提交
git commit -m "Test build with iOS 14.5 SDK"

# 5. 推送
git push -u origin master
```

---

## 📊 查看构建状态

### 1. 访问 Actions 页面

推送后，访问：
```
https://github.com/你的用户名/vcam-test/actions
```

### 2. 查看构建进度

你会看到一个名为 **"Build VCAM Test (iOS 14.6 Compatible)"** 的工作流正在运行。

**构建阶段：**
1. ⏳ Setup Build Environment (1-2分钟)
2. ⏳ Install Theos (首次: 5-8分钟，后续: 跳过/缓存)
3. ⏳ Build Project (1-2分钟)
4. ✅ Upload Artifacts

**总耗时：**
- 首次构建: 约 **8-10 分钟**
- 后续构建: 约 **2-3 分钟** (使用缓存)

### 3. 构建成功标志

- ✅ 绿色对勾
- 可以看到 "Upload Build Artifacts" 步骤

---

## 📦 下载编译好的 deb

### 方法 1：从 Actions 页面下载

1. 点击构建任务
2. 滚动到底部，找到 **Artifacts** 部分
3. 下载文件：
   - `VCAM-Test-iOS14.6-xxxxxx.zip` - deb 包
   - `build-info-xxxxxx.zip` - 构建信息

### 方法 2：使用 GitHub CLI（可选）

```bash
# 安装 GitHub CLI
brew install gh

# 登录
gh auth login

# 下载最新的 artifact
gh run download --repo 你的用户名/vcam-test
```

---

## 📱 安装测试

### 1. 解压下载的文件

```bash
unzip VCAM-Test-iOS14.6-*.zip
```

会得到 `com.trizau.sileo.vcam_1.0.0_iphoneos-arm.deb`

### 2. 传输到设备

```bash
# 确保 iproxy 运行
iproxy 2222 22 &

# 传输文件
scp -P 2222 com.trizau.sileo.vcam_1.0.0_iphoneos-arm.deb root@localhost:/var/root/
```

### 3. 安装

```bash
ssh -p 2222 root@localhost
# 密码: alpine

dpkg -i /var/root/com.trizau.sileo.vcam_1.0.0_iphoneos-arm.deb
killall -9 SpringBoard
```

### 4. 验证结果

**✅ 期望结果（证明 SDK 是问题）：**
- SpringBoard 正常重启
- 3秒后弹出 "VCAM Test" 提示框
- 系统稳定运行
- 没有崩溃

**❌ 如果还是崩溃：**
- 可能还有其他兼容性问题
- 需要检查 MobileSubstrate 版本
- 可能需要更旧的 SDK（iOS 13.7）

---

## 🔧 修改构建配置

如果需要修改 SDK 版本或其他设置，编辑：
```
.github/workflows/build.yml
```

然后重新推送即可触发新的构建。

---

## 📝 常见问题

### Q1: 构建失败怎么办？

**A**: 点击失败的任务，查看详细日志，通常会显示具体错误原因。

### Q2: 如何触发重新构建？

**A**: 
- 方法1: 推送新的 commit
- 方法2: 在 Actions 页面点击 "Re-run jobs"

### Q3: 私有仓库可以用吗？

**A**: 可以，但免费账户每月有 2000 分钟限制。公开仓库无限制。

### Q4: 如何使用其他 SDK 版本？

**A**: 修改 `.github/workflows/build.yml` 中的这行：
```yaml
export TARGET = iphone:clang:14.5:14.0
#                            ^^^^ 改成你想要的版本
```

可用版本：13.7, 14.0, 14.4, 14.5 等

---

## 🎓 下一步

如果 GitHub Actions 编译的版本能正常运行：
1. ✅ 证实了是 M4 Mac SDK 的问题
2. ✅ 可以恢复原始代码重新编译
3. ✅ 使用 Actions 作为正式构建环境

如果还是崩溃：
1. 尝试更旧的 SDK（iOS 13.7）
2. 检查设备的越狱环境
3. 检查 MobileSubstrate 版本

---

**祝你构建成功！** 🎉
