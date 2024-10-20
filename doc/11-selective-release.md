# Selective release

前章でアーティファクトへのバージョンの埋め込みを自動化できるようになった。しかし、個別に対象を指定しない限り、全てのアーティファクトに対してバージョンを埋め込んでしまい、本来変更とは無関係な変更に対しても新しいバージョンをリリースしてしまう。

この章では、Gitの履歴を活用して変更に関連するアーティファクトのみをリリースする手法について検討する。

## target-determinator

[target-determinator](https://github.com/bazel-contrib/target-determinator) は、Gitの履歴を元に指定したバージョン間の変更によって影響を受けたターゲットを特定するツールである。
まずはGitHub Releasesからバイナリをダウンロードしてインストールする。

```sh
VERSION=v0.28.0
OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
REPO=github.com/bazel-contrib/target-determinator
wget -O target-determinator \
  "https://${REPO}/releases/download/${VERSION}/target-determinator.${OS}.${ARCH}"
chmod +x ./target-determinator
sudo mv ./target-determinator /usr/local/bin/target-determinator
```

target-determinatorは、現在のworkspaceがuncleanな場合git worktreeを、そうでない場合現在のworkspace内を利用して指定したバージョン間の変更によって影響を受けたターゲットを特定する。

```sh
# 一番最近のweekly tagからの変更によって影響を受けたターゲット一覧
target-determinator $(git describe --tags --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" --abbrev=0)
```

さらに `bazel query` を使って、特定の種類のターゲットのみを抽出することもできる。例えば下記の様にクエリを指定すれば、指定したコミットから現在の最新までの間で依存に変更があった `oci_push` ターゲットのみを抽出できる。

```sh
BEFORE=$(git describe --tags --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" --abbrev=0)
target-determinator \
    -targets='kind("oci_push", //...)' \
    "${BEFORE}"
```

```
❯ BEFORE=$(git describe --tags --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" --abbrev=0)
❯ target-determinator \
    -targets='kind("oci_push", //...)' \
    "${BEFORE}"
2024/10/20 10:07:16 Processing revision 'before' (2024.42, sha: ccb03e0bdbf3a38d6365cd63d6be753c2cbb14da)
2024/10/20 10:07:16 Current working tree has 1 non-ignored untracked files:
2024/10/20 10:07:16  ?? doc/11-selective-release.md
2024/10/20 10:07:16 Workspace is unclean, using git worktree. This will be slower the first time. You can avoid this by committing local changes and ignoring untracked files.
2024/10/20 10:07:16 Reusing git worktree in /Users/pddg/.cache/target-determinator/td-worktree-go-bazel-playground-dbff8ee1a2b23a9e0fdf11953e2cd230ddd83c9e
2024/10/20 10:07:17 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:07:24 Running cquery on deps(kind("oci_push", //...))
2024/10/20 10:07:25 Running cquery on kind("oci_push", //...)
2024/10/20 10:07:26 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:07:28 Matching labels to configurations
2024/10/20 10:07:29 Hashing targets
2024/10/20 10:07:29 Processing revision 'after' (current working directory state)
2024/10/20 10:07:32 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:07:38 Running cquery on deps(kind("oci_push", //...))
2024/10/20 10:07:40 Running cquery on kind("oci_push", //...)
2024/10/20 10:07:41 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:07:43 Matching labels to configurations
2024/10/20 10:07:43 Hashing targets
//apps/fortune_cowsay:image_push
//apps/hello_world:image_push
2024/10/20 10:07:45 Finished after 31.322594917s
```

変更が無かった直前のバージョンを指定すると、これらのターゲットは表示されない。

```
❯ target-determinator -targets='kind("oci_push", //...)' 53567fdfa4c31dddaba8a328eba747807f74918c 
2024/10/20 10:14:53 Processing revision 'before' (sha: 53567fdfa4c31dddaba8a328eba747807f74918c)
2024/10/20 10:14:53 Current working tree has 1 non-ignored untracked files:
2024/10/20 10:14:53  ?? doc/11-selective-release.md
2024/10/20 10:14:53 Workspace is unclean, using git worktree. This will be slower the first time. You can avoid this by committing local changes and ignoring untracked files.
2024/10/20 10:14:53 Reusing git worktree in /Users/pddg/.cache/target-determinator/td-worktree-go-bazel-playground-dbff8ee1a2b23a9e0fdf11953e2cd230ddd83c9e
2024/10/20 10:14:54 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:15:01 Running cquery on deps(kind("oci_push", //...))
2024/10/20 10:15:03 Running cquery on kind("oci_push", //...)
2024/10/20 10:15:04 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:15:06 Matching labels to configurations
2024/10/20 10:15:07 Hashing targets
2024/10/20 10:15:08 Processing revision 'after' (current working directory state)
2024/10/20 10:15:10 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:15:15 Running cquery on deps(kind("oci_push", //...))
2024/10/20 10:15:17 Running cquery on kind("oci_push", //...)
2024/10/20 10:15:18 Finding compatible targets under kind("oci_push", //...)
2024/10/20 10:15:20 Matching labels to configurations
2024/10/20 10:15:21 Hashing targets
2024/10/20 10:15:22 Finished after 30.559654917s
```

これにより、push時に変更があったターゲットのみをリリースできる。

## Setup CI

ここではGitHub Actionsを利用する。まずは普通にビルド・テストを行うジョブを設定する。これでテストが落ちるような変更のマージをブロックできるようにする。

```yaml:.github/workflows/build.yml
name: Build

on:
  pull_request:
    branches:
      - main

permissions:
  contents: read

jobs:
  build:
    strategy:
      matrix:
        os:
          - ubuntu-latest
          - macOS-latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: build
        run: |
          bazel build //...
      - name: test
        run: |
          bazel test //...
```

そしてpull requestがマージされた時に、変更があったターゲットのみをリリースするジョブを追加する。そのためにtarget-determinatorをセットアップするアクションを作る。

```yaml:.github/actions/setup-target-determinator/action.yaml
name: Setup target-determinator
description: Setup target-determinator
inputs:
  os:
    description: OS name (e.g. Linux, Darwin ...etc)
    required: true
  arch:
    description: Archtecture name (e.g. amd64, arm64 ...etc)
    required: true
runs:
  using: composite
  steps:
    - shell: bash
      env:
        OSNAME_RAW: ${{ inputs.os }}
        ARCHNAME_RAW: ${{ inputs.arch }}
      run: |
        echo "::group::Setup env vars"
        VERSION=0.28.0
        REPO="https://github.com/bazel-contrib/target-determinator"
        OSNAME=$(echo "${OSNAME_RAW}" | awk '{print tolower($0)}')
        ARCHNAME=$(echo "${ARCHNAME_RAW}" | awk '{print tolower($0)}')
        echo "VERSION=${VERSION}"
        echo "REPO=${REPO}"
        echo "OSNAME=${OSNAME}"
        echo "ARCHNAME=${ARCHNAME}"
        echo "::endgroup::"

        echo "::group::Download target-determinator and driver"
        wget -q -O /tmp/target-determinator "${REPO}/releases/download/v${VERSION}/target-determinator.${OSNAME}.${ARCHNAME}"
        wget -q -O /tmp/driver "${REPO}/releases/download/v${VERSION}/driver.${OSNAME}.${ARCHNAME}"
        echo "::endgroup::"

        # TODO: Add checksum/signature verification

        echo "::group::Install target-determinator and driver"
        chmod +x /tmp/target-determinator
        chmod +x /tmp/driver
        mv /tmp/target-determinator /usr/local/bin
        mv /tmp/driver /usr/local/bin

        target-determinator -version
        driver -version

        echo "::endgroup::"
```

実際にリリースを行うワークフローを追加する。再利用できるようにReusable Workflowを使う。

```yaml:.github/workflows/release.yml
name: Release

on:
  workflow_call:
    inputs:
      last_release_commit:
        type: string
        description: 'The commit hash/tag of the last release.'
        required: false

concurrency:
  # Only one instance of this workflow can run at a time
  # https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs
  group: release

jobs:
  container_image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true
          # Use blob less clone to speed up the checkout
          # https://github.blog/jp/2021-01-13-get-up-to-speed-with-partial-clone-and-shallow-clone/
          filter: blob:none
      - uses: actions/cache/restore@v4
        with:
          key: ${{ runner.os }}-release-cache-${{ github.sha }}
          path: /tmp/last-release-commit.txt
          restore-keys: |
            ${{ runner.os }}-release-cache-
      - name: Get last release commit
        env:
          LAST_RELEASE_COMMIT: ${{ github.event.inputs.last_release_commit }}
        run: |
          if [ -z "${LAST_RELEASE_COMMIT}" ]; then
            # If there is no input, use the cache
            if [ -f /tmp/last-release-commit.txt ]; then
              LAST_RELEASE_COMMIT=$(cat /tmp/last-release-commit.txt)
            else
              # If there is no cache, use the latest tag as the last release commit
              LAST_RELEASE_COMMIT=$(git describe --tags --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" --abbrev=0)
            fi
          fi
          echo "LAST_RELEASE_COMMIT=${LAST_RELEASE_COMMIT}" >> $GITHUB_ENV
      - uses: ./.github/actions/setup-target-determinator
        with:
          os: linux
          arch: amd64
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Push changed container images
        run: |
          target-determinator \
            -targets='kind("oci_push", //...)' \
            ${LAST_RELEASE_COMMIT} \
            | tee /tmp/changed-images.txt
          if [ -z "$(cat /tmp/changed-images.txt)" ]; then
            echo "No changed images found."
            exit 0
          fi
          bazel run \
            --stamp \
            "$(cat /tmp/changed-images.txt)"
          # Save the last release commit to cache
          echo "${{ github.sha }}" > /tmp/last-release-commit.txt
      - uses: actions/cache/save@v4
        with:
          key: ${{ runner.os }}-release-cache-${{ github.sha }}
          path: /tmp/last-release-commit.txt
```

そしてpull requestがマージされた時に、releaseジョブを呼び出す。

```yaml:.github/workflows/release-when-pr-merged.yml
name: Release when PR merged

on:
  pull_request:
    types:
      - closed

permissions:
  contents: read
  packages: write

jobs:
  release:
    uses: ./.github/workflows/release.yaml
    if: github.event.pull_request.merged == true
    with:
      # Pass the base commit of the PR as the last release commit
      last_release_commit: ${{ github.event.pull_request.base.sha }}
```

これで、変更があったターゲットのみをリリースするワークフローが完成した。
