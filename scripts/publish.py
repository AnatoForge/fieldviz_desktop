from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "scripts" / "release-config.json").read_text(encoding="utf-8"))
GITHUB = CONFIG["github"]
API_ROOT = "https://api.github.com"
VERSION_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
EXPECTED_ASSETS = {"latest.json", "latest.json.sig"}


def parse_version(value: str) -> str:
    if not VERSION_PATTERN.fullmatch(value):
        raise ValueError(f"版本号必须是 X.Y.Z, 收到: {value}")
    return value


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_release_directory(version: str, directory: Path) -> list[Path]:
    parse_version(version)
    if not directory.is_dir():
        raise RuntimeError(f"发布目录不存在: {directory}")
    state = json.loads((directory / "release-state.json").read_text(encoding="utf-8"))
    if state.get("version") != version or state.get("sourceTag") != f"v{version}":
        raise RuntimeError("release-state.json 与版本不匹配")
    assets = state.get("assets")
    if not isinstance(assets, dict):
        raise RuntimeError("release-state.json 缺少 assets")
    installer_names = [name for name in assets if name.endswith("_x64_Setup.exe")]
    expected_names = EXPECTED_ASSETS | set(installer_names)
    if len(installer_names) != 1 or set(assets) != expected_names:
        raise RuntimeError("应当包含一个 x64 安装包、latest.json 和 latest.json.sig")
    paths = []
    for name, expected in assets.items():
        path = directory / name
        if not path.is_file():
            raise RuntimeError(f"缺少发布文件: {name}")
        if path.stat().st_size != expected.get("size") or hash_file(path) != expected.get("sha256"):
            raise RuntimeError(f"发布文件校验失败: {name}")
        paths.append(path)
    manifest = json.loads((directory / "latest.json").read_text(encoding="utf-8"))
    target = manifest.get("platforms", {}).get("windows-x86_64", {})
    expected_prefix = (
        f"https://github.com/{GITHUB['owner']}/{GITHUB['repo']}/releases/download/v{version}/"
    )
    if manifest.get("version") != version or not target.get("url", "").startswith(expected_prefix):
        raise RuntimeError("latest.json 的版本或安装包地址无效")
    return paths


def git(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
    )
    return result.stdout.strip()


def require_public_repository() -> None:
    if git("status", "--porcelain"):
        raise RuntimeError("公开发行仓库工作树必须干净")
    if git("branch", "--show-current") != GITHUB["branch"]:
        raise RuntimeError(f"必须在 {GITHUB['branch']} 分支发布")
    remote = git("remote", "get-url", "origin")
    if f"{GITHUB['owner']}/{GITHUB['repo']}" not in remote:
        raise RuntimeError("origin 不是预期的公开发行仓库")


class GitHubClient:
    def __init__(self, token: str):
        self.token = token

    def request(
        self,
        method: str,
        url: str,
        data: bytes | None = None,
        content_type: str = "application/json",
        timeout: int = 30,
    ):
        target = url if url.startswith("https://") else f"{API_ROOT}{url}"
        request = urllib.request.Request(
            target,
            data=data,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": GITHUB["apiVersion"],
                "Content-Type": content_type,
                "User-Agent": "fieldviz-release-tool",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"GitHub API {method} {target} 失败: {error.code}: {detail}") from error

    def json(self, method: str, path: str, payload: dict | None = None):
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        return self.request(method, path, data)

    def find_release(self, tag: str):
        releases = self.json(
            "GET",
            f"/repos/{GITHUB['owner']}/{GITHUB['repo']}/releases?per_page=100",
        )
        return next((release for release in releases if release["tag_name"] == tag), None)

    def upload(self, release: dict, path: Path):
        upload_url = release["upload_url"].split("{")[0]
        url = f"{upload_url}?name={urllib.parse.quote(path.name)}"
        content_type = {
            ".exe": "application/vnd.microsoft.portable-executable",
            ".json": "application/json",
            ".sig": "text/plain",
        }.get(path.suffix.lower(), "application/octet-stream")
        return self.request("POST", url, path.read_bytes(), content_type, timeout=600)


def remote_asset_matches(asset: dict, path: Path) -> bool:
    if asset.get("size") != path.stat().st_size:
        return False
    digest = asset.get("digest")
    return digest is None or digest == f"sha256:{hash_file(path)}"


def publish(version: str, directory: Path) -> None:
    require_public_repository()
    assets = verify_release_directory(version, directory)
    token = os.environ.get("FIELDVIZ_RELEASE_TOKEN")
    if not token:
        raise RuntimeError("缺少 FIELDVIZ_RELEASE_TOKEN")
    client = GitHubClient(token)
    tag = f"v{version}"
    release = client.find_release(tag)
    if release is None:
        release = client.json(
            "POST",
            f"/repos/{GITHUB['owner']}/{GITHUB['repo']}/releases",
            {
                "tag_name": tag,
                "target_commitish": GITHUB["branch"],
                "name": f"FieldViz {tag}",
                "body": f"FieldViz {version}",
                "draft": True,
                "prerelease": False,
            },
        )
    remote_assets = {asset["name"]: asset for asset in release.get("assets", [])}
    for path in assets:
        existing = remote_assets.get(path.name)
        if existing and remote_asset_matches(existing, path):
            continue
        if not release["draft"]:
            raise RuntimeError(f"已发布 Release 中的附件不匹配, 拒绝覆盖: {path.name}")
        if existing:
            client.json(
                "DELETE",
                f"/repos/{GITHUB['owner']}/{GITHUB['repo']}/releases/assets/{existing['id']}",
            )
        client.upload(release, path)
    if release["draft"]:
        client.json(
            "PATCH",
            f"/repos/{GITHUB['owner']}/{GITHUB['repo']}/releases/{release['id']}",
            {"draft": False, "make_latest": "true"},
        )
    print(f"已发布 {tag}")


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("用法: py scripts/publish.py X.Y.Z D:\\path\\to\\release\\vX.Y.Z")
    publish(parse_version(sys.argv[1]), Path(sys.argv[2]).resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
