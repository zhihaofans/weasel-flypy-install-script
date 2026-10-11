# Rime 小狼毫 + 雾凇拼音 一键安装

一条命令在新 Windows 10/11 电脑上装好 Rime 小狼毫输入法、部署雾凇拼音方案、并切换到小鹤双拼。

## 在线一键安装（推荐）

打开 PowerShell（**不用管理员**，脚本会自己提权），粘贴一行命令回车：

```powershell
irm https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/install.ps1 | iex
```

`raw.githubusercontent.com` 是 GitHub 官方源，**即时更新、无缓存**，推荐优先使用。

> **如果官方源连不上**（国内常见），改用 CDN 镜像：
>
> ```powershell
> irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1 | iex
> ```
>
> ⚠️ jsDelivr 对 `@master` 有缓存（可能滞后几小时）。如果刚更新过仓库，CDN 上可能还是旧版，遇到奇怪报错时优先换官方源。

引导器会自动挑一个能通的源把主脚本下下来，然后启动安装。约 3-5 分钟。装完任务栏出现『小狼毫』图标，**默认就是小鹤双拼**。

> **引导器的提示是英文的**——这是刻意的：`irm | iex` 路径下 PowerShell 5.1 会按 GBK 解码响应，任何中文（哪怕在注释里）都会变成乱码，甚至会破坏脚本解析（报 `Unexpected attribute 'CmdletBinding'`）。真正的安装过程和结果都是完整中文（主脚本走 `-File` 路径，有 BOM 保护）。详见下文[编码铁律](#-编码铁律两个文件要求完全相反本项目最大的坑)。

想装 GitHub 官方源版（不用国内镜像）：

```powershell
& ([scriptblock]::Create((irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1))) -Source github
```

### 在线方式为什么不是直接 `irm .../install-rime-cn.ps1 | iex`

| 原因 | 说明 |
|---|---|
| `exit` 会关窗口 | 主脚本有 6 处 `exit`。`iex` 内联执行时 `exit` 会直接关掉你正在用的 PowerShell 窗口，**出错连提示都看不到** |
| 自提权会失效 | 主脚本提权依赖 `$PSCommandPath`，而 `iex` 下它是空的，脚本会直接报错退出 |
| 看不完输出 | 安装要几分钟，内联执行结束时窗口就没了 |

所以 `install.ps1` 是个**引导器**：下载 → 存成临时文件 → 用 `-File` 启动独立子进程。这样子进程的 `exit` 只结束它自己，你的窗口留着，报错和结果都能看完。

引导时想加参数（透传给主脚本）：

```powershell
# 只更新方案，不重装输入法
& ([scriptblock]::Create((irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1))) -SkipInstall

# 自定义候选词个数
& ([scriptblock]::Create((irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1))) -PageSize 7
```

### 安全检查（可选）

不放心直接跑远程脚本的话，先下来看一眼再执行：

```powershell
# 存到本地查看
irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1 -OutFile .\install.ps1
notepad .\install.ps1
```

## 本地方式（不用在线）

把仓库克隆或下载下来，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `install.ps1` | **在线引导器**（上面那一行命令跑的就是它） |
| `install-rime-cn.ps1` | 主安装脚本 · 国内镜像优先，失败自动回退 GitHub（**国内推荐**） |
| `install-rime.ps1` | 主安装脚本 · GitHub 官方源 |

两个主脚本**除下载源外完全一致**，都带 SHA256 校验。镜像与官方文件字节相同，共用同一 hash——校验和既能防损坏，也能证明镜像未被篡改。

## 零前置依赖

只用 Windows 自带组件，**不需要**预先安装任何东西：

| 用途 | 使用的系统自带能力 |
|---|---|
| 脚本引擎 | PowerShell 5.1（Win10/11 内置） |
| 下载 | `Invoke-WebRequest` |
| 校验 | `Get-FileHash`（SHA256） |
| 解压 | `tar.exe`（Win10 1803+ 内置），回退 `Expand-Archive` |
| 静默安装 | NSIS `/S` 参数 |

## 装了什么

| 组件 | 版本 | 来源 |
|---|---|---|
| 小狼毫 Weasel | `0.17.4` | [rime/weasel](https://github.com/rime/weasel/releases/tag/0.17.4) |
| 雾凇拼音 rime-ice | `2026.06.30` | [iDvel/rime-ice](https://github.com/iDvel/rime-ice/releases/tag/2026.06.30) |

镜像源（CN 版，已验证 hash 与官方一致）：

| 组件 | 镜像 |
|---|---|
| 小狼毫 | 山東大學 `mirrors.sdu.edu.cn/github-release/rime_weasel/` |
| 雾凇拼音 | 南京大學 `mirror.nju.edu.cn/github-release/iDvel/rime-ice/` |

两个包都带 **SHA256 校验**，来源为 GitHub release 正式版（hash 永久稳定）。校验不通过会中止，不会装到损坏或被篡改的文件。

## 脚本做了什么

引导器（`install.ps1`）：下载主脚本（3 源轮询）→ 落盘 → `-File` 启动子进程 → 清理临时文件。

主脚本：

1. 检查系统、TLS 1.2、管理员权限（不足则自动提权重启）
2. 下载小狼毫安装器 → 校验 SHA256 → `/S` 静默安装
3. 下载雾凇拼音 `full.zip` → 校验 SHA256 → 解压
4. **备份**你已有的 `*.custom.yaml`、`userdb/`、`sync/`（只保留最近 3 份）
5. 部署方案到 `%APPDATA%\Rime`（跳过 `build/`、`.git` 等）
6. 写 `default.custom.yaml`：方案列表 = **小鹤双拼 + 全拼**，候选词 9 个
7. 写 `double_pinyin_flypy.custom.yaml`（已存在则不覆盖）
8. 调用 `WeaselDeployer.exe /deploy` 重新部署
9. 清理临时文件

脚本**可重复运行**：重跑会先备份你的自定义配置，不会冲掉手工改动。

## 参数

主脚本参数（本地方式直接用；在线方式通过引导器透传）：

```powershell
# 只更新方案，不重装输入法
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1 -SkipInstall

# 自定义候选词个数
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1 -PageSize 7

# 指定配置目录
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1 -RimeDir "D:\Rime"

# 保留临时文件（排查问题用）
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1 -KeepDownload
```

引导器独有参数：

```powershell
# 换成 GitHub 官方源版
.\install.ps1 -Source github
```

## 装完怎么用

| 操作 | 方式 |
|---|---|
| 切换方案 | `F4` 或 `` Ctrl+` `` |
| 重新部署 | 右键任务栏『小狼毫』图标 → 重新部署 |
| 改候选词数等 | 编辑 `%APPDATA%\Rime\default.custom.yaml` |
| 加自定义短语 | `%APPDATA%\Rime\custom_phrase_double.txt`（双拼用，需手动建） |

## 升级版本（两版同步）

上游发新版时，两个脚本**各改 2 处**（都在文件顶部的「配置区」）：

1. `$WeaselVersion` / `$IceVersion` → 改成新的 release tag
2. `$WeaselSha256` / `$IceSha256` → 改成新版本的 hash

hash 获取方式：

```bash
# GitHub API 的 digest 字段（推荐，权威）
curl -s https://api.github.com/repos/rime/weasel/releases/latest | grep digest
curl -s https://api.github.com/repos/iDvel/rime-ice/releases/latest | grep digest
```

镜像 URL 里含版本号（`.../$WeaselVersion/...`），会**自动跟随**新版本变化，一般不用改。
即使镜像还没同步到新版，脚本也会自动回退 GitHub 原版，不会失败。

## 说明与注意事项

- **小狼毫装在系统默认位置**（`%ProgramFiles%\Rime`），不是便携安装。它是系统输入法组件（要注册 TSF、写注册表），必须如此。
- 首次部署 Rime 会编译词库，等几十秒；期间托盘图标转圈属正常。
- 若装完任务栏没图标：注销/重启一次，或运行 `WeaselSetup.exe` 注册输入法。
- 装了第三方杀软可能拦截静默安装，届时手动确认一次。
- 本脚本不处理卸载（按需求）。要卸载：设置 → 应用 → 找到 Rime 卸载；配置目录 `%APPDATA%\Rime` 手动删。
- **在线运行的安全性**：`irm | iex` 是"下载即执行"，本质是信任仓库作者。本仓库全部脚本开源、单文件、零依赖，可先 `-OutFile` 下来审阅再跑（见上文「安全检查」）。引导器只从本仓库拉取主脚本，不执行任何其他远程代码。

## 引导器维护说明

引导器里的 3 个下载源都指向本仓库 `master` 分支，**主脚本更新后不用改引导器**，推送即生效。

新增下载源（比如再加一个代理）时，改 `install.ps1` 里的 `$baseUrls` 数组即可。

顺序规则：**官方源 `raw.githubusercontent` 必须排第一**，因为 jsDelivr 的 `@master` 有缓存、可能滞后数小时，而缓存里的旧版主脚本可能缺 BOM（导致中文乱码）。CDN 和代理作为回退放在后面。脚本会按顺序试，且**每个源下载后都会校验内容**（体积、特征串），不合格自动换下一个。

引导器的自检：`python3 tests/bootstrap-check.py`（会联网验证 3 个地址是否真的 200）。

### ⚠️ 编码铁律：两个文件要求完全相反（本项目最大的坑）

Windows PowerShell 5.1 对编码的处理有个老毛病，而本项目**同时踩在两条不同的执行路径上**，两条路的编码要求是**相反的**：

| 文件 | 执行路径 | 编码要求 | 原因 |
|---|---|---|---|
| `install.ps1`（引导器） | `irm ... \| iex` | **纯 ASCII + 无 BOM** | `irm` 对无 charset 的响应按系统 ANSI(GBK) 解码。任何非 ASCII 字符（**包括注释里的中文**）都会乱码；**带 BOM 更致命**——BOM 三字节会被 GBK 拼成一个非法字符 `锘`，卡在脚本第一行行首，PowerShell 直接抛 `ParseError`，脚本一行都执行不了 |
| `install-rime*.ps1`（主脚本） | 引导器 `-OutFile` 落盘 → `-File` 执行 | **UTF-8 with BOM** | 走真实文件路径时 PS5.1 按 BOM 判定编码。**无 BOM 就按 GBK 解码**，中文全乱码（`正在下载` → `姝ｅ湪涓嬭浇`），且 UTF-8 字节被误读后可能破坏引号边界、引发语法错误 |

**为什么这么绕？** 因为这两条路各自"应该有的编码"正好是对方"绝对不能有的编码"：

```
irm | iex  这条路：文件在内存里是【字符串】，编码信息已经丢了 → 只能靠纯 ASCII 保平安
-File      这条路：文件在磁盘上是【字节】，BOM 能告诉 PS 怎么解码 → 必须带 BOM
```

所以：
- `install.ps1` 保持 **纯 ASCII、无 BOM**（连注释都是英文，就是怕中文乱码后产生 `` ` `` 或引号破坏语法）
- 两个主脚本保持 **UTF-8 with BOM**
- 引导器下载主脚本后会**检测并补写 BOM**（CDN/代理可能把 BOM 丢掉），这就是让主脚本中文正常的关键一步

自己编辑时注意：
- 改 `install.ps1` → **不要加任何中文**，存成 `UTF-8`（无 BOM）
- 改主脚本 → 存成 `UTF-8 with BOM`（VS Code 右下角选 `UTF-8 with BOM`；记事本选 `带 BOM 的 UTF-8`）
