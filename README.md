# FieldViz Desktop Releases

本仓库是 FieldViz 的公开发行仓库, 用于发布 Windows 安装包和经过签名的自动更新清单。应用源码保存在独立的私有仓库中, 本仓库不代表 FieldViz 主程序开源。

安装包仅作为 GitHub Release Assets 发布。客户端通过以下固定地址获取最新更新清单:

```text
https://github.com/AnatoForge/fieldviz_desktop/releases/latest/download/latest.json
```

## 发布工具

本仓库使用 PowerShell 校验发布产物, 使用 GitHub 官方 `gh` CLI 上传附件, 不依赖 Python 或 Node.js。

首次使用时, 通过统一命令隐藏输入一次 GitHub Personal Access Token。登录信息会保存在 Windows 凭据存储中, 后续不需要重复输入:

```powershell
.\build.cmd gh-login
```

使用 Classic Personal Access Token 时需要 `repo`、`read:org` 和 `gist` 权限。

检查指定版本是否满足发布条件。该命令会运行发布脚本自检、仓库与 GitHub 环境检查及实际产物校验:

```powershell
.\build.cmd test 0.0.2
```

发布仓库固定为 `AnatoForge/fieldviz_desktop`。发布时只需提供版本号, 工具会自动读取相邻私有仓库的 `fieldviz\release\vX.Y.Z`:

```powershell
.\build.cmd publish 0.0.2
```

GitHub CLI 会管理已输入的登录凭据。Token 不会写入命令行、脚本或日志。安装包、更新清单和签名私钥不得提交到本仓库的 Git 历史。
