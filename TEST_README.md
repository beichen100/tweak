# VCAM Hello World 测试指南

## 🎯 测试目的

通过一个最简单的 "Hello World" 版本来验证：
1. **编译环境是否正确**（SDK、工具链等）
2. **基础 Hook 功能是否正常**
3. **是否会导致 SpringBoard 崩溃**

如果这个简化版本能正常工作，说明问题出在原项目的复杂代码逻辑上，而**不是 SDK 版本**的问题。

---

## 📦 当前测试版本

- **代码**: 极简 Hello World（约 80 行）
- **功能**: 
  - Hook SpringBoard 启动
  - 打印日志到系统
  - 显示一个测试弹窗
- **依赖**: 仅 UIKit + Foundation
- **大小**: 4.7KB（原版 28KB）

---

## 🚀 安装测试

### 步骤 1: 确保设备已连接

```bash
# 检查设备连接
ideviceinfo -k ProductVersion
```

应该显示: `14.6`

### 步骤 2: 运行安装脚本

```bash
cd /Users/beichen/Documents/tweak
./install-test.sh
```

**脚本会自动：**
1. 启动 iproxy
2. 传输 deb 到设备
3. 安装插件
4. 重启 SpringBoard

**期望结果：**
- ✅ SpringBoard 正常重启（不崩溃）
- ✅ 3秒后弹出 "VCAM Test" 提示框
- ✅ 系统日志中有 VCAM 相关信息

### 步骤 3: 查看日志

```bash
./check-logs.sh
```

**应该看到：**
```
🔧 VCAM Test Plugin Loaded Successfully!
📅 Load Time: 2025-11-13 ...
✅ VCAM Test: Constructor executed
🎉 VCAM Test Hook Success! Call count: 1
```

---

## 🔍 测试结果判断

### ✅ 成功（证明不是 SDK 问题）

如果看到：
- SpringBoard 正常重启
- 弹出测试提示框
- 日志中有 VCAM 输出
- **没有崩溃或 panic**

**结论**: 
- ✅ 编译环境正常
- ✅ SDK 版本可用
- ❌ **原项目代码有问题**（可能是 AVFoundation Hook 的问题）

### ❌ 失败（可能是 SDK 问题）

如果出现：
- SpringBoard 崩溃
- 设备重启/白苹果
- 产生新的 panic 日志

**结论**:
- ❌ 可能确实是 SDK 兼容性问题
- 需要使用 Docker 或 GitHub Actions 编译

---

## 🧹 卸载测试版本

```bash
./uninstall.sh
```

---

## 📊 对比分析

| 项目 | 原版 VCAM | Hello World 测试版 |
|------|-----------|-------------------|
| 代码行数 | ~2000+ | ~80 |
| deb 大小 | 28KB | 4.7KB |
| 依赖框架 | 7个 | 2个 |
| Hook 类数 | 10+ | 2 |
| 复杂度 | 高 | 极低 |

---

## 🔧 如果测试成功，下一步

1. **逐步添加功能**
   - 先添加基础的相机 Hook
   - 再添加视频替换
   - 最后添加音频等高级功能

2. **找出问题代码**
   - 对比哪个 Hook 导致崩溃
   - 检查 iOS 14.6 的 API 差异
   - 优化内存管理

3. **渐进式测试**
   - 每添加一个功能就测试一次
   - 确定是哪部分代码导致问题

---

## 📝 当前文件结构

```
tweak/
├── Tweak.x                    # Hello World 测试代码
├── Tweak.x.backup            # 原始代码备份
├── Makefile                  # 简化的编译配置
├── install-test.sh           # 安装脚本
├── check-logs.sh             # 查看日志脚本
├── uninstall.sh              # 卸载脚本
├── TEST_README.md            # 本文档
└── packages/
    └── com.trizau.sileo.vcam_1.0.0_iphoneos-arm.deb  # 测试版本
```

---

## 🎓 测试方法学习

这就是标准的**最小化复现（Minimal Reproduction）**调试方法：

1. **简化到最小**：移除所有复杂逻辑，只保留核心功能
2. **逐步添加**：一次添加一个功能，每次测试
3. **二分查找**：快速定位问题代码
4. **隔离变量**：确定是环境问题还是代码问题

**这是专业开发者的标准做法！** 👍
