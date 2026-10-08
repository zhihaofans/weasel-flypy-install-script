# Rime 小狼毫 + 雾凇拼音 一键安装

一个 PowerShell 脚本，在新 Windows 10/11 电脑上装好 Rime 小狼毫输入法、部署雾凇拼音方案、并切换到小鹤双拼。

## 两个版本

| 文件 | 下载源 | 适用 |
|---|---|---|
| `install-rime-cn.ps1` | 国内镜像优先，失败自动回退 GitHub | **国内网络推荐** |
| `install-rime.ps1` | GitHub 官方 | 海外网络 / 镜像异常时 |

两版**除下载源外完全一致**，都带 SHA256 校验。镜像与官方文件字节相同，共用同一 hash——校验和既能防损坏，也能证明镜像未被篡改。

## 使用

把对应脚本拷到新电脑，然后任选一种方式（以 CN 版为例）：

```powershell
# 方式 A：右键 install-rime-cn.ps1 -> "使用 PowerShell 运行"
# 方式 B：命令行
powershell -ExecutionPolicy Bypass -File .\install-rime-cn.ps1
```

脚本会自动请求管理员权限（装输入法必需），全程无需干预。约 3-5 分钟（取决于网速）。

装完任务栏出现『小狼毫』图标，**默认就是小鹤双拼**。

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

1. 检查系统、TLS 1.2、管理员权限（不足则自动提权重启）
2. 下载小狼毫安装器 → 校验 SHA256 → `/S` 静默安装
3. 下载雾凇拼音 `full.zip` → 校验 SHA256 → 解压
4. **备份**你已有的 `*.custom.yaml`、`userdb/`、`sync/`
5. 部署方案到 `%APPDATA%\Rime`（跳过 `build/`、`.git` 等）
6. 写 `default.custom.yaml`：方案列表 = **小鹤双拼 + 全拼**，候选词 9 个
7. 写 `double_pinyin_flypy.custom.yaml`（已存在则不覆盖）
8. 调用 `WeaselDeployer.exe /deploy` 重新部署
9. 清理临时文件

脚本**可重复运行**：重跑会先备份你的自定义配置，不会冲掉手工改动。

## 参数

两版参数完全相同（示例用 CN 版，换 `install-rime.ps1` 亦可）：

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
