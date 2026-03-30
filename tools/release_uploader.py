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
# Upload the rootfs tarball, preformatted VHDX for /home, and bootstrap.sh
ASSETS = [
    ("ubuntu-noble-amd64.tar.gz", "application/gzip"),
    ("home.vhdx", "application/octet-stream"),
    ("provision/bootstrap.sh", "text/x-shellscript"),
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

    # Step 1: Delete existing release (if any)
    release = None
    for r in repo.get_releases():
        if r.tag_name == TAG:
            release = r
            break
    if release:
        print(f"Deleting existing release for tag {TAG}...")
        try:
            release.delete_release()
        except Exception as e:
            print(f"Warning: failed to delete release: {e}")

    # Step 2: Delete tag ref (if any)
    ref = None
    try:
        ref = repo.get_git_ref(f"tags/{TAG}")
        print(f"Deleting tag ref {TAG}...")
        ref.delete()
    except github.GithubException as e:
        if e.status == 404:
            print(f"Tag ref {TAG} not found (OK)")
        else:
            print(f"Warning: failed to delete tag ref: {e}")
    except Exception as e:
        print(f"Warning: failed to delete tag ref: {e}")

    # Step 3: Get latest commit SHA on default branch
    try:
        default_branch = repo.default_branch
        sha = repo.get_branch(default_branch).commit.sha
        print(f"Using commit {sha} from branch {default_branch} for tag {TAG}")
    except Exception as e:
        print(f"Error: could not get latest commit SHA: {e}", file=sys.stderr)
        return 4

    # Step 4: Recreate tag
    try:
        repo.create_git_ref(ref=f"refs/tags/{TAG}", sha=sha)
        print(f"Created tag {TAG} at {sha}")
    except Exception as e:
        print(f"Error: failed to create tag: {e}", file=sys.stderr)
        return 5

    # Step 5: Create new release
    try:
        release = repo.create_git_release(tag=TAG, name=TAG, message="Automated rootfs", draft=False, prerelease=False)
        print(f"Created new release for tag {TAG}")
    except Exception as e:
        print(f"Error: failed to create release: {e}", file=sys.stderr)
        return 6

    # Step 6: Upload assets
    for name, content_type in ASSETS:
        try:
            uploaded = release.upload_asset(name, name=name, label=name, content_type=content_type)
            print(uploaded.browser_download_url)
        except Exception as e:
            print(f"Error uploading {name}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
