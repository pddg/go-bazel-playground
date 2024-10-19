# Versioning Artifacts

例えばコンテナイメージはタグを用いてバージョンを指定することが一般的である。ここまでの例では常に `latest` というタグを用いていたが、本番環境で `latest` を利用することはアンチパターンの一つとされている。

また、実行コマンドにバージョン情報などを動的に埋め込むこともよく行われている。 `--version` オプションや `version` サブコマンドを持つコマンドラインツールなどがその例である。

bazelを用いて生成したコンテナイメージやバイナリに対して、このようなバージョン情報を埋め込む方法を考える。

## How to inject version information

### Go Binary

方法としてはいくつかあるが、まずは伝統的な `-ldflags` オプションを利用する方法を紹介する。

```go
package main

import (
  "fmt"
)

var Version string

func main() {
  fmt.Println("Version: " + Version)
}
```

このようなコードをビルドする際に `-ldflags` オプションを指定することで、バイナリにバージョン情報を埋め込める。

```sh
$ go build -ldflags "-X main.Version=1.0.0" -o main main.go
$ ./main
Version: 1.0.0
```

同様の設定がbazelでも可能である。
Ref: https://github.com/bazel-contrib/rules_go/blob/master/docs/go/core/defines_and_stamping.md#defines-and-stamping

まずhello_worldコマンドにバージョンを埋め込む。

```diff:apps/hello_world/main.go
diff --git a/apps/hello_world/main.go b/apps/hello_world/main.go
index a18d207..0ab0dc1 100644
--- a/apps/hello_world/main.go
+++ b/apps/hello_world/main.go
@@ -4,10 +4,14 @@ import (
        "fmt"
 
        "github.com/google/uuid"
+
        "github.com/pddg/go-bazel-playground/internal/reverse"
 )
 
+var Version = "dev"
+
 func main() {
+       fmt.Printf("Version: %s\n", Version)
        uuidStr := uuid.NewString()
        fmt.Printf("Hello, World!(%s)\n", uuidStr)
        fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"))
```

そして以下の様に `go_binary` ルールを設定する。

```python:apps/hello_world/BUILD.bazel
go_binary(
    name = "hello_world",
    embed = [":hello_world_lib"],
    visibility = ["//visibility:public"],
    x_defs = {
      "Version": "1.0.0",
    },
)
```

これにより、bazelでのビルド時に `-X main.Version=1.0.0` が指定された状態でビルドされる。

```
❯ bazel run //apps/hello_world     
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.130s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/apps/hello_world/hello_world_/hello_world
Version: 1.0.0
Hello, World!(c18327c7-9f6a-4e57-b4f1-8c780765f1a2)
Reversed: !dlroW ,olleH
OsName: darwin
```

### Container Image

rules_ociでは `oci_push` ルールの `remote_tags` にリモートリポジトリにpushする際のタグを指定できる。

```python:apps/fortune_cowsay/BUILD.bazel
oci_push(
    name = "image_push",
    image = ":image_index",
    # here
    remote_tags = ["1.0.0"],
    repository = REPOSITORY,
)
```

## Versioning strategies

### Manual

最も一般的なバージョニング手法はSemantic Versioningと言って良いだろう。これはバージョン番号を `Major.Minor.Patch` の形式で表現するものである。例えば `1.0.0` など。

BUILDファイル内で `VERSION` のような変数を宣言すれば、Goのバイナリとそのコンテナに同じバージョン情報を付与出来る。

- Pros
  - 一般的なバージョニング手法であるため、他の開発者が理解しやすい。
- Cons
  - 新しい変更をリリースするためには人が手動でバージョン番号を更新する必要がある。
  - 手動での指定は人為的なミスが発生しやすい。
    - 変更を忘れる
    - ブランチ間で重複するバージョン番号を指定する
    - バージョン番号のフォーマットを間違える
    - ...etc
