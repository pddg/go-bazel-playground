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

## Build container image from distroless

既にあるイメージをベースにする場合、まずは `MODULE.bazel` 内でそれらのイメージをpullして利用可能な状態にする。

```python:MODULE.bazel
oci = use_extension("@rules_oci//oci:extensions.bzl", "oci")
oci.pull(
    name = "distroless_static_debian12",
    image = "gcr.io/distroless/static-debian12",
    platforms = [
        "linux/amd64",
        "linux/arm64",
    ],
    tag = "nonroot",
)
use_repo(oci, "distroless_static_debian12", "distroless_static_debian12_linux_amd64", "distroless_static_debian12_linux_arm64")
```

実際には `use_repo(...` は記述せずに `bazel mod tidy` とすれば自動で生成される。ではこれをベースにhello_worldイメージを変更する。
そしてこれをbaseになるように `oci_image` ルールを書き換える。

```python:BUILD.bazel
diff --git a/apps/hello_world/BUILD.bazel b/apps/hello_world/BUILD.bazel
index 0ac4679..4c19ca7 100644
--- a/apps/hello_world/BUILD.bazel
+++ b/apps/hello_world/BUILD.bazel
@@ -53,9 +53,8 @@ pkg_tar(
 
 oci_image(
     name = "image_amd64",
-    architecture = "amd64",
+    base = "@distroless_static_debian12_linux_amd64",
     entrypoint = ["/hello_world_linux_amd64"],
-    os = "linux",
     tars = [":pkg"],
 )
```

architectureおよびosの指定はbaseから自ずと定まるため、指定したままではエラーになる。

では、これをloadして実行してみる。

```
❯ bazel run //apps/hello_world:image_amd64_load
INFO: Analyzed target //apps/hello_world:image_amd64_load (0 packages loaded, 12 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:image_amd64_load up-to-date:
  bazel-bin/apps/hello_world/image_amd64_load.sh
INFO: Elapsed time: 0.909s, Critical Path: 0.72s
INFO: 8 processes: 5 internal, 2 darwin-sandbox, 1 local.
INFO: Build completed successfully, 8 total actions
INFO: Running command line: bazel-bin/apps/hello_world/image_amd64_load.sh
d37950ece3d3: Loading layer [==================================================>]  104.2kB/104.2kB
8fa10c0194df: Loading layer [==================================================>]  13.36kB/13.36kB
ddc6e550070c: Loading layer [==================================================>]  536.8kB/536.8kB
4d049f83d9cf: Loading layer [==================================================>]      67B/67B
af5aa97ebe6c: Loading layer [==================================================>]     188B/188B
ac805962e479: Loading layer [==================================================>]     122B/122B
bbb6cacb8c82: Loading layer [==================================================>]     168B/168B
2a92d6ac9e4f: Loading layer [==================================================>]      93B/93B
1a73b54f556b: Loading layer [==================================================>]     385B/385B
f4aee9e53c42: Loading layer [==================================================>]     321B/321B
b336e209998f: Loading layer [==================================================>]  130.5kB/130.5kB
509aadc7ac0e: Loading layer [==================================================>]  1.567MB/1.567MB
The image hello_world:latest already exists, renaming the old one with ID sha256:0bb6ae9b08fabe53141dfdabfac7a10fb8028896ba44d5b51850394f71a77e7f to empty string
Loaded image: hello_world:latest

❯ docker run --rm hello_world:latest
Hello, World!(cea92ed4-9cb6-49da-afed-90b10fc162fb)
Reversed: !dlroW ,olleH
OsName: linux
```

なお、このままでは `nonroot` というタグしか指定していないため、結果が異なってしまう可能性がある。正しく固定するためにはdigestを指定する。

```diff:MODULE.bazel
diff --git a/MODULE.bazel b/MODULE.bazel
index e0ae79e..7a4f968 100644
--- a/MODULE.bazel
+++ b/MODULE.bazel
@@ -30,6 +30,7 @@ bazel_dep(name = "rules_pkg", version = "1.0.1")
 oci = use_extension("@rules_oci//oci:extensions.bzl", "oci")
 oci.pull(
     name = "distroless_static_debian12",
+    digest = "sha256:26f9b99f2463f55f20db19feb4d96eb88b056e0f1be7016bb9296a464a89d772",
     image = "gcr.io/distroless/static-debian12",
     platforms = [
         "linux/amd64",
```


