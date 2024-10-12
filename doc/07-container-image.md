# Container Image

現代では作成したアプリケーションのバイナリを直接サーバに配置するのではなく、コンテナなどを使ってデプロイ・オーケストレーションすることが多い。そのため、シングルバイナリとしてビルド出来るGoであってもコンテナイメージを作成することは多い。
通常であればDockerfileを記述してビルドしたり、[ko](https://github.com/ko-build/ko)を使ってイメージを作成する。ここではbazelを使ってどのようにコンテナイメージを作成するかを見ていく。

## Setup rules_oci

bazelではコンテナイメージの作成もルールという形で抽象化されている。以前は[rules_docker](https://github.com/bazelbuild/rules_docker)が使われていましたが、これは既にアーカイブされています。現在は[rules_oci](https://github.com/bazel-contrib/rules_oci)を使うのがスタンダードになっています。

まず`MODULE.bazel`にrules_ociのセットアップを追記する。また、ファイルなどをtarで固めてイメージに追加するために[rules_pkg](https://github.com/bazelbuild/rules_pkg)が必要なのでこれも追記する。

```python:MODULE.bazel
bazel_dep(name = "rules_oci", version = "2.0.0")
bazel_dep(name = "rules_pkg", version = "1.0.1")
```

## Build container image from scratch

これを使って、イメージをビルドする。`apps/hello_world/BUILD.bazel`に記述する。

!!! important
    以下ではホストのアーキテクチャがamd64であることを仮定しているが、もし異なる場合は適切なアーキテクチャにする。
    なお、macOSではRosetta2によりarm64なホストのDocker Desktopからamd64なコンテナを実行できる。

```python:apps/hello_world/BUILD.bazel
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("@rules_oci//oci:defs.bzl", "oci_image")

# 中略

# tarに固める
pkg_tar(
    name = "pkg",
    srcs = [":hello_world_linux_amd64"],
)

# コンテナイメージをビルドする
oci_image(
    name = "image_amd64",
    architecture = "amd64",
    entrypoint = ["/hello_world_linux_amd64"],
    os = "linux",
    # イメージに追加するtarを指定する
    tars = [":pkg"],
)
```

```
❯ bazel build //apps/hello_world:image
INFO: Analyzed target //apps/hello_world:image (0 packages loaded, 138 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:image up-to-date:
  bazel-bin/apps/hello_world/image
INFO: Elapsed time: 0.954s, Critical Path: 0.76s
INFO: 7 processes: 4 internal, 3 darwin-sandbox.
INFO: Build completed successfully, 7 total actions
```

このままでは単にビルドしただけで実行できない。手元のDockerでこのイメージを動かせるよう、イメージのロードを追加する。

```python:apps/hello_world/BUILD.bazel
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")

# 中略

oci_load(
    name = "image_amd64_load",
    image = ":image_amd64",
    repo_tags = ["hello_world:latest"],
)
```

Dockerデーモンにイメージをロードするにはrunする。

```
❯ bazel run //apps/hello_world:image_amd64_load
INFO: Analyzed target //apps/hello_world:image_load (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:image_load up-to-date:
  bazel-bin/apps/hello_world/image_load.sh
INFO: Elapsed time: 0.135s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/apps/hello_world/image_load.sh
8a60cf1c47f0: Loading layer [==================================================>]   1.72MB/1.72MB
Loaded image: hello_world:latest
```

これによりこのイメージをDockerデーモンで実行できるようになる。

```
❯ docker run --rm hello_world:latest           
Hello, World!(119e1658-47f6-482a-9859-adb430300b79)
Reversed: !dlroW ,olleH
OsName: linux
```
