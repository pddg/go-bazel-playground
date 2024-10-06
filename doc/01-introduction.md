# 01. Introduction

## Install bazel using bazelisk

[Bazelisk](https://github.com/bazelbuild/bazelisk)をインストールする。
Bazeliskは、bazelのバージョンを指定して実行するためのラッパースクリプトである。リポジトリのルートにある `.bazeliskrc` ファイルの設定に従って、実行されるbazelのバージョンを決める。
各自の環境にはbazeliskのみを入れておき、`.bazeliskrc` を通してプロジェクト内で使うbazelのバージョンを制御することが望ましい。

```bash
# Linux
ARTIFACT="bazelisk-linux-$(uname -m | sed 's/x86_64/amd64/')"
wget -O bazelisk \
  "https://github.com/bazelbuild/bazelisk/releases/latest/download/${ARTIFACT}"
chmod +x bazelisk
sudo mv bazel /usr/local/bin
# Install as `bazel`
sudo ln -s /usr/local/bin/bazel /usr/local/bin/bazelisk

# macOS
# This will install `bazelisk` and alias for it named`bazel`
brew install bazelisk
```

`bazel` コマンドで実行されるbazelのバージョンを決める。
ここでは、現在の最新安定版である 7.x を指定する。パッチバージョンまで決め打つこともできる。

```bash
cat  << EOF > .bazeliskrc
USE_BAZEL_VERSION=7.x
EOF
```

実行されるbazelのバージョンを確認する。

```
❯ bazel --version     
bazel 7.3.2
```

## Setup Go project

Goプロジェクトとして初期化する。

```bash
cat <<EOF > go.mod
module github.com/pddg/go-bazel-playground

go 1.23.2
EOF
```

この段階ではまだ動くGoコードは無くて良い。

## Setup rules_go

Bazelでは言語ごとにビルドツールの呼び出しを抽象化したルールを用意するのが慣習となっている。
これらは `rules_` というプレフィックスがついていることが多い。Go言語には[rules_go](https://github.com/bazelbuild/rules_go)が用意されている。

これらのruleを使うために、Bazelではモジュールの仕組みが用意されている。これはBzlmodと呼ばれる比較的新しい機能である。
リポジトリのルートに `MODULE.bazel` ファイルを作成する。このファイルは[Starlark](https://github.com/bazelbuild/starlark)というPythonのサブセットで書かれる。

```python
"""
This is a playground for developing application with Bazel.
"""

# このリポジトリの名前とバージョンを宣言する
module(
    name = "go-bazel-playground",
    version = "0.0.1",
)
```

rules_goを導入するため`MODULE.bazel`に追記する。最新のバージョンはGitHub Releasesの他、Bazel Central Registryからも確認できる。
https://registry.bazel.build/modules/rules_go

```python
bazel_dep(name = "rules_go", version = "0.50.1", repo_name = "rules_go")

go_sdk = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
go_sdk.download(version = "1.23.2")
```

`bazel mod tidy` コマンドを使えばフォーマットなどをしてくれる。

```bash
bazel mod tidy
```

これまでは `WORKSPACE.bazel` ファイルにてバージョンやそのチェックサムを指定していたが、中央集権リポジトリが整備されて名前とバージョンのみで簡潔に指定できるようになった。
一方で、まだ `WORKSPACE.bazel` ファイルを利用することはでき、その存在に依存するルールも多い。ここでは空ファイルだけを作成しておく。

```bash
touch WORKSPACE.bazel
```

## Run go command

前節で導入したrules_goは、`MODULE.bazel`の中で指定したバージョンのGo SDKをダウンロードしている。
このGo SDKを使って、`go` コマンドを実行する。

```bash
bazel run @rules_go//go -- version
```

以下の様にGoのバージョンが表示されれば成功である。

```
bazel run @rules_go//go -- version
INFO: Analyzed target @@rules_go~//go:go (2 packages loaded, 12 targets configured).
INFO: Found 1 target...
Target @@rules_go~//go/tools/go_bin_runner:go_bin_runner up-to-date:
  bazel-bin/external/rules_go~/go/tools/go_bin_runner/bin/go
INFO: Elapsed time: 0.428s, Critical Path: 0.03s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions
INFO: Running command line: bazel-bin/external/rules_go~/go/tools/go_bin_runner/bin/go version
go version go1.23.2 linux/amd64
```

## Build Go application

`apps` ディレクトリを作成し、`hello_world` というGoアプリケーションを作成する。
このアプリケーションは単に `Hello, World!` と出力するだけのものである。

```bash
mkdir -p apps/hello_world
cat <<EOF > apps/hello_world/main.go
package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
EOF
```

bazelでは、Goアプリケーションをビルドするために開発者が `go` コマンドの使い方を覚える必要は無い。
ビルドするアプリケーションのディレクトリに `BUILD.bazel` ファイルを作成し、ビルドルールを記述する。

```python:MODULE.bazel
load("@rules_go//go:def.bzl", "go_binary")

go_binary(
    name = "hello_world",
    srcs = ["main.go"],
    visibility = ["//visibility:public"],
)
```

`BUILD.bazel` ファイルを作成したら、`bazel build` コマンドでビルドする。

```bash
bazel build //apps/hello_world:hello_world
```

以下の様なログが表示されれば成功である。

```
❯ bazel build //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (72 packages loaded, 11985 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.727s, Critical Path: 0.09s
INFO: 6 processes: 4 internal, 2 linux-sandbox.
INFO: Build completed successfully, 6 total actions
```

実際にこのアプリケーションを実行してみる。

```bash
bazel run //apps/hello_world:hello_world
```

```
❯ bazel run //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.154s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/apps/hello_world/hello_world_/hello_world
Hello, World!
```

## Conclusion

Bazelを使ってGoアプリケーションをビルドするための環境を構築した。
Bazelでは、ビルドツールの呼び出しを抽象化したルールを用意することが慣習となっており、Goではrules_goが用意されている。
rules_goはBzlmodを使って導入することができ、Go SDKのダウンロードやビルドルールの記述を行うことができる。
rules_goを使ってGoアプリケーションをビルドするためには、`BUILD.bazel` ファイルを作成し、ビルドルールを記述する。
