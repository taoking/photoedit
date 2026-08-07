你现在作为本项目的主开发 Agent 和阶段验收 Agent 工作。

项目根目录已有：

- `plan.md`：整个项目 Phase 1 ~ Phase 8 的长期开发计划
- `prompt.md`：Phase 1 的详细开发规范以及后续阶段架构要求

请先完整阅读：

```text
plan.md
prompt.md
README.md
AGENTS.md（如果存在）
当前源代码
当前测试
```

然后执行：

```bash
git status
git branch --show-current
git log --oneline -10
```

## 总目标

严格按照 `plan.md` 定义的 Phase 顺序持续开发整个项目。

执行顺序必须是：

```text
Phase 1
↓
开发
↓
测试
↓
Build
↓
验收
↓
发现问题则修复
↓
重新测试 / Build / 验收
↓
PASS
↓
Git Commit
↓
Phase 2
↓
重复以上流程
↓
Phase 3
...
↓
直到 plan.md 中所有阶段完成
```

不要完成 Phase 1 后停止询问我是否继续。

如果当前 Phase 验收通过：

**自动进入下一 Phase。**

不需要等待我的人工确认。

但是：

**任何 Phase 没有通过验收时，禁止进入下一 Phase。**

---

# 一、阶段执行原则

每次只能把一个 Phase 作为当前主要开发目标。

例如正在执行：

```text
Phase 2
```

就不要同时开始实现：

```text
Phase 3 RAW
Phase 4 Batch
Phase 5 Technical LUT
```

除非 Phase 2 为后续阶段增加必要的接口或架构扩展点。

禁止以“后续再完善”为理由跳过当前 Phase 的 P0 功能。

---

# 二、每个 Phase 开始前

必须重新阅读 `plan.md` 中当前 Phase 内容。

然后检查当前代码。

输出当前阶段内部计划：

```text
Current Phase: Phase N

Existing:
- 已经具备的能力

Missing:
- 当前 Phase 尚缺功能

Implementation:
- 本阶段准备修改的模块

Validation:
- 本阶段准备执行的测试和 Build
```

计划完成后直接开始开发。

不要等待我的确认。

---

# 三、开发

按当前 Phase 的要求完成真实代码。

必须优先：

```text
正确性
>
稳定性
>
性能
>
架构
>
UI polish
```

不要为了视觉效果跳过核心能力。

禁止：

```text
TODO 占位代替实现
Fake implementation
Mock 假装功能完成
只创建 UI 没有真实 pipeline
只写 interface 不实现
为了通过测试硬编码结果
```

---

# 四、每阶段必须测试

完成代码后运行当前项目能够执行的测试。

例如：

```bash
swift test
```

或者：

```bash
xcodebuild test
```

根据项目实际结构选择正确命令。

重点运行：

```text
Unit Tests
LUT Tests
Image Pipeline Tests
State Tests
Parser Tests
Export Tests
Regression Tests
```

如果测试失败：

```text
禁止继续下一阶段。
```

分析失败原因、修复并重新执行。

重复：

```text
TEST
→ FIX
→ TEST
```

直到通过。

---

# 五、每阶段必须 Build

每一个 Phase 必须进行真实 Build。

使用项目实际 scheme / workspace / project。

例如：

```bash
xcodebuild \
  -scheme <AppScheme> \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

实际参数应根据当前项目自动确定，不要机械复制示例。

如果模拟器型号不存在：

先查询：

```bash
xcrun simctl list devices available
```

选择当前机器真实存在的模拟器。

Build 出现：

```text
error
warning
Swift concurrency warning
linker problem
resource problem
```

需要检查。

Compiler Error 必须全部修复。

严重 warning 必须处理。

---

# 六、阶段验收

测试和 Build 通过以后，对照 `plan.md` 当前 Phase 的验收要求逐条检查。

生成：

```text
PHASE N ACCEPTANCE

[PASS] requirement 1
[PASS] requirement 2
[PASS] requirement 3
...

Tests:
PASS

Build:
PASS

Architecture:
PASS

Regression:
PASS
```

如果任何关键验收项目为：

```text
FAIL
```

则：

```text
PHASE N = FAILED
```

继续修复。

不得进入下一 Phase。

---

# 七、不能自动验证的项目

iOS 项目有一些项目可能必须真机验证，例如：

```text
真实 Photos 权限
某些 PhotoKit 行为
真实相册保存
真实相机 RAW 文件
HDR Display
特定 GPU / Metal 行为
视觉效果人工判断
```

这种情况禁止伪造 PASS。

使用：

```text
AUTOMATED: PASS

MANUAL VERIFICATION REQUIRED:
- xxx
- xxx
```

如果不影响当前架构和自动测试，可以继续阶段开发。

但是必须记录在项目进度文件中，最终统一提供给我人工验证。

---

# 八、阶段完成条件

只有同时满足以下条件才认为一个 Phase 完成：

```text
Implementation PASS
Tests PASS
Build PASS
Acceptance PASS
No known P0 blocker
Docs updated
Git diff reviewed
```

然后才能：

```text
PHASE N = COMPLETED
```

---

# 九、Git 规则

每完成一个 Phase 创建一个独立 commit。

例如：

```text
feat: complete phase 1 photo editing and LUT pipeline
feat: complete phase 2 advanced color adjustments
feat: complete phase 3 RAW workflow
feat: complete phase 4 batch editing workflow
```

实际 commit message 根据真实实现调整。

不要：

```text
git push
force push
修改远程分支
rebase 用户已有提交
删除用户已有 commit
```

除非用户之后明确要求。

---

# 十、阶段 Commit 前检查

执行：

```bash
git status
git diff --stat
git diff
```

检查：

```text
DerivedData
build artifacts
用户照片
大型测试文件
API Key
Secrets
临时文件
调试垃圾
```

不得进入 commit。

---

# 十一、建立开发进度文件

创建：

```text
docs/development-progress.md
```

持续维护。

格式：

```text
# Development Progress

## Phase 1
Status: COMPLETED

Commit:
<hash>

Tests:
PASS

Build:
PASS

Implemented:
...

Manual Verification:
...

Known Limitations:
...

---

## Phase 2
Status: IN_PROGRESS
```

进入下一阶段时更新状态。

这个文件是阶段状态的唯一记录。

---

# 十二、回归测试

Phase 2 开始之后，每阶段验收不能只测试新功能。

例如：

```text
Phase 3 RAW
```

完成后仍需要确认：

```text
JPEG import
HEIC import
basic adjustments
LUT
crop
export
preset
HSL
curve
```

没有被破坏。

也就是说：

```text
每阶段测试
=
当前 Phase Tests
+
已有核心功能 Regression Tests
```

---

# 十三、Phase 之间禁止重构失控

如果发现之前架构需要修改，可以重构。

但是必须遵循：

```text
先有测试
→ 重构
→ 测试
→ 功能继续
```

不要因为进入新 Phase 就大规模重写整个项目。

优先增量演进。

---

# 十四、性能回归

涉及 Image Pipeline 的 Phase 必须关注：

```text
12MP
24MP
48MP
```

以及后续：

```text
RAW
Batch
HDR
```

重点避免：

```text
UIImage / CGImage / CIImage 大量重复转换
Full resolution preview
无限 cache
大量并发 full-resolution render
MainActor image processing
```

发现明显性能问题必须解决后再继续。

---

# 十五、Phase 5 色彩管理特别规则

进入：

```text
Technical LUT
Color Management
S-Log3
Rec.709
Display P3
```

以后：

禁止凭经验猜测色彩转换。

必须明确：

```text
Input Color Space
Working Color Space
Technical Transform
Creative LUT
Output Color Space
```

并补充测试及文档。

Preview 和 Export 必须尽量保持一致。

---

# 十六、Phase 6 HDR 特别规则

HDR 开发不得破坏 SDR。

必须同时保留：

```text
SDR input
SDR preview
SDR export
```

回归测试。

如果设备/模拟器无法验证真实 HDR Display：

明确加入 Manual Verification。

---

# 十七、Phase 7 Mask 特别规则

局部蒙版不能污染全局 EditState。

保持类似：

```text
Global EditState

LocalAdjustment
    ├── Mask
    └── Adjustments
```

不要把几十个局部参数继续堆进根 EditState。

---

# 十八、Phase 8 Video 特别规则

视频可以复用：

```text
LUT parser
adjustment models
color management
```

但是：

```text
Photo Render Pipeline
```

和：

```text
Video Render Pipeline
```

必须保持合理隔离。

不要为了复用代码破坏已经稳定的照片 pipeline。

---

# 十九、出现问题时

如果某个实现方案失败：

不要停下来询问用户普通技术决策。

自己：

```text
分析
→ 尝试合理替代方案
→ 测试
→ 记录决定
```

只有存在真正无法继续的外部阻塞，例如：

```text
缺少必要签名
缺少开发者账号
缺少只能由用户提供的文件
缺少物理设备
系统权限无法自动授予
```

才记录：

```text
EXTERNAL BLOCKER
```

并继续完成所有不受该 blocker 影响的任务。

---

# 二十、禁止提前宣布完成

不能因为：

```text
代码已经写完
```

就认为阶段完成。

必须经过：

```text
CODE
→ TEST
→ BUILD
→ ACCEPTANCE
→ REGRESSION
→ COMMIT
```

才能标记：

```text
COMPLETED
```

---

# 二十一、持续执行

当前 Phase 完成并 commit 后：

重新读取：

```text
plan.md
docs/development-progress.md
```

找到下一个：

```text
NOT_STARTED
```

Phase。

标记：

```text
IN_PROGRESS
```

然后自动开始。

不要向用户询问：

```text
是否继续？
是否开始下一阶段？
```

默认答案始终是：

```text
继续。
```

直到 `plan.md` 中规划阶段全部执行完成，或者遇到真正无法绕过的外部 blocker。

---

# 二十二、最终验收

全部 Phase 完成后进行一次项目级最终回归。

检查：

```text
Photo Import
Basic Adjustments
HSL
Curves
Histogram
LUT
Preset
RAW
Batch
Color Management
HDR
Masks
Video（如果 plan 最终包含）
Export
Persistence
Memory
Concurrency
```

运行完整：

```text
Tests
Build
```

然后检查：

```bash
git status
git log --oneline
```

---

# 二十三、最终报告

全部完成后输出：

```text
PROJECT DEVELOPMENT COMPLETE
```

然后提供：

```text
Completed Phases
Phase Commit List
Architecture
Implemented Features
Test Results
Build Results
Performance Results
Manual Verification Required
Known Limitations
Remaining Technical Debt
Recommended Real-device Verification
```

最后给出：

```text
git status
```

状态。

不要自动 push。

---

现在开始。

首先读取 `plan.md`、`prompt.md` 和当前仓库代码，建立 `docs/development-progress.md`。

然后从当前尚未完成的最早 Phase 开始执行。

如果项目目前尚未开发，则从：

Phase 1

开始。

完成、测试、验收、commit 后自动进入 Phase 2。

持续执行直到 `plan.md` 全部阶段完成。