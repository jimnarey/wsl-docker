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
# Upload both the rootfs tarball and the preformatted VHDX for /home
ASSETS = [
    ("ubuntu-noble-amd64.tar.gz", "application/gzip"),
    ("home.vhdx", "application/octet-stream"),
]


def main() -> int:
    repo_name = os.environ.get(REPO_ENV)
    token = os.environ.get(TOKEN_ENV)
    if not repo_name or not token:
        print(f"Environment variables {REPO_ENV} and {TOKEN_ENV} must be set", file=sys.stderr)
        return 2

    for name, _ in ASSETS:
        if not Path(name).exists():
            print(f"Asset not found: {name}", file=sys.stderr)
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

    # Remove any existing assets with the same names, then upload each
    existing = {a.name: a for a in release.get_assets()}
    for name, content_type in ASSETS:
        if name in existing:
            existing[name].delete_asset()
        uploaded = release.upload_asset(name, name=name, label=name, content_type=content_type)
        try:
            print(uploaded.browser_download_url)
        except Exception:
            print(f"Uploaded: {name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
