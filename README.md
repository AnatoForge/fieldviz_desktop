# FieldViz Desktop Releases

本仓库是 FieldViz 的公开发行仓库, 用于发布 Windows 安装包和经过签名的自动更新清单。应用源码保存在独立的私有仓库中, 本仓库不代表 FieldViz 主程序开源。

安装包仅作为 GitHub Release Assets 发布。客户端通过以下固定地址获取最新更新清单:

```text
https://github.com/AnatoForge/fieldviz_desktop/releases/latest/download/latest.json
```

## 发布工具

本仓库使用 PowerShell 校验发布产物, 使用 GitHub 官方 `gh` CLI 上传附件, 不依赖 Python 或 Node.js。

发布工具自检:

```powershell
.\build.cmd test
```

首次使用需要安装并登录 GitHub CLI:

```powershell
winget install --id GitHub.cli --exact
gh auth login
```

在本仓库中可以独立发版本。下面的命令会提示输入 `X.Y.Z`, 并默认读取相邻私有仓库的 `fieldviz\release\vX.Y.Z`:

```powershell
.\build.cmd release
```

也可以显式指定版本号和任意发布产物目录:

```powershell
.\build.cmd release 0.0.2 D:\codes\fieldviz\qt\fieldviz\release\v0.0.2
```

安装包、更新清单、Token 和签名私钥都不得提交到本仓库的 Git 历史。
