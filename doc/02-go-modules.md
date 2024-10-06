# Go Modules

## Setup Gazelle

[Gazelle](https://github.com/bazelbuild/bazel-gazelle)はGoの依存関係を解析して、Bazelのビルドファイルを生成するツールである。
`MODULE.bazel`に追記する。

```python
bazel_dep(name = "gazelle", version = "0.39.1", repo_name = "gazelle")

go_deps = use_extension("@gazelle//:extensions.bzl", "go_deps")
go_deps.from_file(go_mod = "//:go.mod")
```

bazelを通してgazelleを実行するが、簡単に実行できるようにするためリポジトリのルートに`BUILD.bazel`を作成し、以下の内容を記述する。

```python:BUILD.bazel
load("@gazelle//:def.bzl", "gazelle")

# gazelle:prefix github.com/pddg/go-bazel-playground
gazelle(name = "gazelle")
```

`gazelle:prefix` にはこのリポジトリのパスを指定する必要があることに注意する。

これで`bazel run //:gazelle`を実行する。

```
❯ bazel run //:gazelle
INFO: Analyzed target //:gazelle (50 packages loaded, 13768 targets configured).
INFO: Found 1 target...
Target //:gazelle up-to-date:
  bazel-bin/gazelle-runner.bash
  bazel-bin/gazelle
INFO: Elapsed time: 1.147s, Critical Path: 0.03s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/gazelle
```

すると、リポジトリのルートに`deps.bzl`が生成される。

```python:deps.bzl
def go_repos():
    pass
```

また、gazelleは自動でGoプロジェクトの依存関係を解析して`BUILD.bazel`を生成する。
既存の `apps/hello_world/BUILD.bazel` が以下の様に更新されているはずだ。

```diff
diff --git a/apps/hello_world/BUILD.bazel b/apps/hello_world/BUILD.bazel
index 6d825be..0256c1e 100644
--- a/apps/hello_world/BUILD.bazel
+++ b/apps/hello_world/BUILD.bazel
@@ -1,7 +1,14 @@
-load("@rules_go//go:def.bzl", "go_binary")
+load("@rules_go//go:def.bzl", "go_binary", "go_library")
 
 go_binary(
     name = "hello_world",
-    srcs = ["main.go"],
+    embed = [":hello_world_lib"],
     visibility = ["//visibility:public"],
 )
+
+go_library(
+    name = "hello_world_lib",
+    srcs = ["main.go"],
+    importpath = "github.com/pddg/go-bazel-playground/apps/hello_world",
+    visibility = ["//visibility:private"],
+)
```

このようにgazelleは面倒な `BUILD.bazel` の記述を自動で行ってくれる。

## Install third-party dependencies

今回はHello Worldアプリケーションに、uuidの出力を追加する（意味は特にない）。
uuidのライブラリは `github.com/google/uuid` であるため、`go get` コマンドでインストールする。

```bash
bazel run @rules_go//go -- get github.com/google/uuid
```

また、hello_worldアプリケーションにuuidを出力するコードを追加する。

```go:apps/hello_world/main.go
package main

import (
	"fmt"

	"github.com/google/uuid"
)

func main() {
	uuidStr := uuid.NewString()
	fmt.Printf("Hello, World!(%s)\n", uuidStr)
}
```

新しいモジュールを追加したため、gazelleにその依存関係を認識させる。以下のコマンドを実行する。

```bash
# go.modとgo.sumを更新
bazel run @rules_go//go -- mod tidy
# ↑を元にgazelleに依存関係を認識させる
bazel run //:gazelle -- update-repos -from_file=go.mod -to_macro=deps.bzl%go_repos -prune -bzlmod
```

次に、`BUILD.bazel`を更新する。

```bash
bazel run //:gazelle
```

これで、`apps/hello_world/BUILD.bazel`が以下の様に更新される。

```diff
diff --git a/apps/hello_world/BUILD.bazel b/apps/hello_world/BUILD.bazel
index 0256c1e..5572835 100644
--- a/apps/hello_world/BUILD.bazel
+++ b/apps/hello_world/BUILD.bazel
@@ -11,4 +11,5 @@ go_library(
     srcs = ["main.go"],
     importpath = "github.com/pddg/go-bazel-playground/apps/hello_world",
     visibility = ["//visibility:private"],
+    deps = ["@com_github_google_uuid//:uuid"],
 )
```

gazelleの長い引数を覚えるのは面倒なので、`BUILD.bazel`に以下の内容を追記する。

```python:BUILD.bazel
gazelle(
    name = "update-go-repos",
    args = [
        "-from_file=go.mod",
        "-to_macro=deps.bzl%go_repos",
        "-bzlmod",
        "-prune",
    ],
    command = "update-repos",
)
```

これで、`bazel run //:update-go-repos`でgazelleによるサードパーティの依存モジュールの解決を実行できる。

## Build and Run

`bazel run //apps/hello_world:hello_world`を実行する。

```bash
❯ bazel run //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (2 packages loaded, 21 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.984s, Critical Path: 0.24s
INFO: 5 processes: 2 internal, 3 linux-sandbox.
INFO: Build completed successfully, 5 total actions
INFO: Running command line: bazel-bin/apps/hello_world/hello_world_/hello_world
Hello, World!(42b29365-410c-4ce4-b1c2-d6973382d36f)
```

`Hello, World!`の後にuuidが出力されていることが確認できる。

## Conclusion

Gazelleを使ってGoの依存関係を解析し、Bazelのビルドファイルを生成できるようになった。
サードパーティの依存を追加する際は、以下の様にする。

```bash
bazel run @rules_go//go -- get ${MODULE}
bazel run @rules_go//go -- mod tidy
bazel run //:update-go-repos
bazel run //:gazelle
```
