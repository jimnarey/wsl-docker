#!/usr/bin/env python3
"""Minimal uploader: use env vars and fixed names.

Reads `GITHUB_REPOSITORY` and `GITHUB_TOKEN` from the environment.
Looks for `ubuntu-noble-amd64` release and creates it if missing.
Deletes any existing asset named `ubuntu-noble-amd64.tar.gz` and uploads
`./ubuntu-noble-amd64.tar.gz` as that asset. Prints the download URL.
"""
from pathlib import Path
import os
import sys
import github


REPO_ENV = "GITHUB_REPOSITORY"
TOKEN_ENV = "GITHUB_TOKEN"
TAG = "ubuntu-noble-amd64"
ASSET_NAME = "ubuntu-noble-amd64.tar.gz"
ASSET_PATH = Path(ASSET_NAME)


def main() -> int:
    repo_name = os.environ.get(REPO_ENV)
    token = os.environ.get(TOKEN_ENV)
    if not repo_name or not token:
        print(f"Environment variables {REPO_ENV} and {TOKEN_ENV} must be set", file=sys.stderr)
        return 2

    if not ASSET_PATH.exists():
        print(f"Asset not found: {ASSET_PATH}", file=sys.stderr)
        return 3

    gh = github.Github(auth=github.Auth.Token(token))
    repo = gh.get_repo(repo_name)

    release = None
    for r in repo.get_releases():
        if r.tag_name == TAG:
            release = r
            break

    if release is None:
        release = repo.create_git_release(tag=TAG, name=TAG, message="Automated rootfs", draft=False, prerelease=False)

    for asset in release.get_assets():
        if asset.name == ASSET_NAME:
            asset.delete_asset()

    uploaded = release.upload_asset(str(ASSET_PATH), name=ASSET_NAME, label=ASSET_NAME, content_type="application/gzip")
    try:
        print(uploaded.browser_download_url)
    except Exception:
        print("Upload complete")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
