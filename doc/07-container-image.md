# Container Image

現代では作成したアプリケーションのバイナリを直接サーバに配置するのではなく、コンテナなどを使ってデプロイ・オーケストレーションすることが多い。そのため、シングルバイナリとしてビルド出来るGoであってもコンテナイメージを作成することは多い。
通常であればDockerfileを記述してビルドしたり、[ko](https://github.com/ko-build/ko)を使ってイメージを作成する。ここではbazelを使ってどのようにコンテナイメージを作成するかを見ていく。

## Setup rules_oci

bazelではコンテナイメージの作成もルールという形で抽象化されている。以前は[rules_docker](https://github.com/bazelbuild/rules_docker)が使われていたが、これは既にアーカイブされている。現在は[rules_oci](https://github.com/bazel-contrib/rules_oci)を使うのがスタンダードになっている。

まず`MODULE.bazel`にrules_ociのセットアップを追記する。また、ファイルなどをtarで固めてイメージに追加するために[rules_pkg](https://github.com/bazelbuild/rules_pkg)が必要なのでこれも追記する。

```python:MODULE.bazel
bazel_dep(name = "rules_oci", version = "2.0.0")
bazel_dep(name = "rules_pkg", version = "1.0.1")
```

rules_ociはdockerコマンドを使わないため、イメージをビルドするホストにDockerは必要無い。
ただし、実際に作成したイメージをコンテナとして動作させてチェックするために便利であるため、本書ではdockerコマンドを用いる箇所がある。

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
        "linux/arm64/v8",
    ],
    tag = "nonroot",
)
use_repo(oci, "distroless_static_debian12", "distroless_static_debian12_linux_amd64", "distroless_static_debian12_linux_arm64_v8")
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

## Build multi architecture image

ここまでは単一のアーキテクチャ向けにイメージをビルドしてきたが、現代ではApple Siliconなど主に開発環境を中心としてARMアーキテクチャの採用が広がっている。
サーバ環境でもAWS Gravitonプロセッサ、Azure Cobaltプロセッサ、Google Axionプロセッサ、Oracle CloudやAzureで提供されているAmpere Altraなど選択肢が増えつつある。
amd64はまだまだ豊富とはいえ、こういったARMプロセッサの環境で動作させたいという需要は増えている。これらを同時にターゲットにするため、マルチアーキテクチャイメージを生成するのが現代では一般的と言える。

rules_ociはこういったマルチアーキテクチャビルドの抽象化も提供している。これは `oci_image_index` という名前で提供されている。

```python:apps/hello_world/BUILD.bazel
load("@rules_go//go:def.bzl", "go_binary", "go_cross_binary", "go_library")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load")
load("@rules_pkg//:pkg.bzl", "pkg_tar")

ARCHS = [
    "amd64",
    "arm64",
]

# 中略

[
    pkg_tar(
        name = "pkg_" + arch,
        srcs = [":hello_world_linux_" + arch],
    )
    for arch in ARCHS
]

[
    oci_image(
        name = "image_" + arch,
        # Specifying variant 'v8' is needed for arm64
        base = "@distroless_static_debian12_linux_" + arch + ("_v8" if arch == "arm64" else ""),
        entrypoint = ["/hello_world_linux_" + arch],
        tars = [":pkg_" + arch],
    )
    for arch in ARCHS
]

oci_image_index(
    name = "index",
    images = [":image_" + arch for arch in ARCHS],
)

oci_load(
    name = "image_load",
    image = select({
      "@platforms//cpu:x86_64": ":image_amd64",
      "@platforms//cpu:arm64": ":image_arm64",
    }),
    repo_tags = ["hello_world:latest"],
)
```

単純に複数アーキテクチャ向けにイメージをビルドし、 `oci_image_index` でそれをまとめている。
`oci_load` で `select` を使って指定されたCPUアーキテクチャ次第で読み込まれるイメージを切り替えているが、amd64・arm64どちらのホストでも `image_load` すればこれで動くかなと思っただけなので、単純に `image_amd64_load` とかを作ってもよい。

### Use transition

bazelの[transition](https://bazel.build/extending/config#user-defined-transitions)という機能を使うことで、既存のターゲットに対して設定値の提供などを行うルールを記述できる。
これにより、バイナリのビルドからイメージのビルドまでplatformの一貫した選択などを行えるようになり、がんばってループを書かなくてもよくなる。

rules_ociのexampleにその一例がある。ここでは `multi_arch` という新しいルールを作っており、指定した `platform` に対して `oci_image` をビルドするようにしている。
https://github.com/bazel-contrib/rules_oci/tree/v2.0.0/examples/multi_architecture_image

このルールを拝借して、コンテナイメージ以外にも使えるよう名前だけ調整して追加してみる。

```sh
mkdir -p build_tools/transitions
touch build_tools/transitions/BUILD.bazel
```

```python:build_tools/transitions/multi_arch.bzl
# original: https://github.com/bazel-contrib/rules_oci/blob/v2.0.0/examples/multi_architecture_image/transition.bzl

def _multiarch_transition(settings, attr):
    return [
        # 指定されたplatformsをビルド時のコマンドラインオプションとして指定
        {"//command_line_option:platforms": str(platform)}
        for platform in attr.platforms
    ]

multiarch_transition = transition(
    implementation = _multiarch_transition,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    return DefaultInfo(files = depset(ctx.files.target))

multi_arch = rule(
    implementation = _impl,
    attrs = {
        "target": attr.label(cfg = multiarch_transition),
        "platforms": attr.label_list(),
        # このルールを使えるパッケージの許可リストを設定できる。
        # ここでは全て許可するようになっている。
        # transitionの追加はビルドの依存グラフを簡単に大きくしてしまえるため、
        # こういった保護機構があるらしい。
        # https://bazel.build/versions/7.0.0/extending/config#user-defined-transitions
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
```

これを使うと先ほどの例は以下の様に記述出来るようになる。

```python:apps/hello_world/BUILD.bazel
load("@rules_go//go:def.bzl", "go_binary", "go_cross_binary", "go_library")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load")
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("//build_tools/transitions:multi_arch.bzl", "multi_arch")

go_binary(
    name = "hello_world",
    # 省略
)

pkg_tar(
    name = "pkg",
    srcs = [":hello_world"],
)

oci_image(
    name = "image",
    base = "@distroless_static_debian12",
    entrypoint = ["/hello_world"],
    tars = [":pkg"],
)

multi_arch(
    name = "images",
    target = ":image",
    platforms = [
        "@rules_go//go/toolchain:linux_amd64",
        "@rules_go//go/toolchain:linux_arm64",
    ],
)

oci_image_index(
    name = "image_index",
    images = [":images"],
)
```

なんだか便利そうなので公式で入ったら良いのにと思うかも知れないが、rules_ociのメンテナはかなり慎重に考えているようだ。
（その割には公式のexampleとして特に注意書きもなしに載せるんだとは思った）
https://github.com/bazel-contrib/rules_oci/issues/228

前身である `rules_docker` でこのようなtransitionを提供したところ、Apple Siliconの普及に伴いamd64とarm64の違いによるビルドの失敗などがサポートコストを増やしたようだ。

transitionを使うことで記述は簡潔になるが、問題は残されている。`:image` を直接指定してビルドすると実行ホストのOS・アーキテクチャでビルドされたバイナリが使われるため、例えばamd64のmacOSでビルドするとdarwin_amd64向けにコンパイルされたバイナリがLinux向けイメージに追加される。

`oci_load` を使ってホストに作成したイメージを読み込ませたい場合、このようにビルドされたコンテナイメージを読み込んでしまうと、実行時に `exec format error` で失敗するようになる。このような意図しない結果を避けるため、ユーザは意識して `--platforms` オプションを使う必要がある。

`oci_load` 時のplatformを意識させないためには、ホストのアーキテクチャと一致し、ただし `GOOS` だけは `linux` になるようにビルドしてイメージを構築しなければならない。
`multi_arch` ルールでplatformの指定をまとめず、以下の様にそれぞれ宣言して利用した方が便利かもしれない。

```python:apps/hello_world/BUILD.bazel
ARCHS = [
    "amd64",
    "arm64",
]

[
    multi_arch(
        name = "image_" + arch,
        target = ":image",
        platforms = [
            "@rules_go//go/toolchain:linux_" + arch,
        ],
    )
    for arch in ARCHS
]

oci_image_index(
    name = "image_index",
    images = [":image_" + arch for arch in ARCHS],
)

oci_load(
    name = "image_load",
    image = select({
      "@platforms//cpu:x86_64": ":image_amd64",
      "@platforms//cpu:arm64": ":image_arm64",
    }),
    repo_tags = ["hello_world:latest"],
)
```

### Tips: Use macro

[macro](https://bazel.build/extending/macros)とは、典型的な操作をまとめてカプセル化して隠蔽したり、再利用可能なコードを作成するための機能である。
コンテナイメージを必要とする全てのアプリケーションで先ほどの記述を繰り返すのは面倒なので、macroを使ってまとめてみる。

```sh
mkdir -p build_tools/macros
touch build_tools/macros/BUILD.bazel
```

```python:build_tools/macros/oci.bzl
"""OCI image macros."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load")
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("//build_tools/transitions:multi_arch.bzl", "multi_arch")

ARCHS = [
    "amd64",
    "arm64",
]

def go_oci_image(name, base, entrypoint, srcs, architectures = ARCHS):
    """go_oci_image creates a multi-arch container image from Go binary.

    Args:
        name: The name of this targes.
        base: The base image to use.
        entrypoint: The entrypoint for the container.
        srcs: Go binaries to include the image.
        repo_tags: The repository tags to apply to the image when load it into host.
        architectures: The architectures to build for (default: ARCHS).
    """
    pkg_tar(
        name = name + "_pkg",
        srcs = srcs,
    )

    oci_image(
        name = name,
        base = base,
        entrypoint = entrypoint,
        tars = [":" + name + "_pkg"],
    )

    for arch in architectures:
        multi_arch(
            name = name + "_" + arch,
            target = ":" + name,
            platforms = [
                "@rules_go//go/toolchain:linux_" + arch,
            ],
        )

    oci_image_index(
        name = name + "_index",
        images = [":" + name + "_" + arch for arch in architectures],
    )

    oci_load(
        name = name + "_load",
        image = select({
          "@platforms//cpu:x86_64": ":" + name + "_amd64",
          "@platforms//cpu:arm64": ":" + name + "_arm64",
        }),
        repo_tags = repo_tags,
    )
```

これを使うと以下の様に記述できる。

```python:apps/hello_world/BUILD.bazel
load("//build_tools/macros:oci.bzl", "go_oci_image")

# 中略

go_oci_image(
    name = "image",
    srcs = [":hello_world"],
    base = "@distroless_static_debian12",
    entrypoint = ["/hello_world"],
    repo_tags = ["hello_world:latest"],
)
```

このmacroを使うだけで、複数アーキテクチャ向けのイメージをビルドするターゲットや、それをOCI Image Indexにまとめるターゲット、ホストのアーキテクチャに一致するイメージをロードするターゲットが自動で生成される。
ただ設定を後から注入することがほとんどできないので、実際に利用するならもう少し調整の必要があるだろう。
