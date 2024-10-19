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

BUILDファイル内で `VERSION` のような変数を宣言し、Goのバイナリとそのコンテナにそれぞれ指定すれば同じバージョン情報を付与出来る。

- Pros
  - 一般的なバージョニング手法であるため、他の開発者が理解しやすい。
- Cons
  - 新しい変更をリリースするためには人が手動でバージョン番号を更新する必要がある。
  - 手動での指定は人為的なミスが発生しやすい。
    - 変更を忘れる
    - ブランチ間で重複するバージョン番号を指定する
    - バージョン番号のフォーマットを間違える
    - ...etc

### Auto

バージョンを手動で管理する場合、依存するライブラリなどが他の人・チームなどによって変更されたとき、そのままではバージョンが変更されず、新しい変更がリリースされない。bazelは逆依存を辿ることも出来るため、新しい変更を入れたチームがその依存関係を解析してバージョンを書き換えることは可能である。しかし、単純なSemantic Versioningでは変更が競合したり、異なるチームが異なる変更を同じバージョンでリリースしたりしてしまう可能性がある。

そこで、簡単には重複することがないバージョン番号を自動で生成する方法を考える。以下のブログで言及されている方法を紹介する。  
https://blog.aspect.build/versioning-releases-from-a-monorepo

まず、リポジトリに毎週タグを打つ。年と、年初からの週の数を用いる。例えば、2022年の第1週のタグは `2022.01` となる。そして、リリースするタイミングでは前回のタグから今までのコミット数を数え、それをバージョン番号の最後に付与する。例えば、2022年の第1週から2022年の第2週までに10回コミットがあった場合、そのリリースのバージョン番号は `2022.01.10` となる。そして最後にHEADのコミットハッシュを付与することで、重複することがないバージョン番号を生成する。

この毎週タグを打つためにGitHub Actionsを利用する。curlコマンドを使うことで、git cloneせずに最新のHEADにタグを打てる。これはいわゆる[lightweight tag](https://git-scm.com/book/en/v2/Git-Basics-Tagging)であり、単にバージョン計算の目印としてのみ利用する。  
Ref: https://gist.github.com/alexeagle/ad3f1f4f90a5394a866bbb3a3b8d1de9

```yaml:.github/workflows/weekly-tag.yml
on:
  schedule:
    # Sunday 15:00 UTC = Monday 00:00 JST 
    - cron: '0 15 * * 0'

permissions:
  # GitHub Token can create tags
  contents: write

jobs:
  tagger:
    runs-on: ubuntu-latest
    steps:
      - name: tag HEAD with date +%G.%V
        run: |
          curl --request POST \
            --url https://api.github.com/repos/${{ github.repository }}/git/refs \
            --header 'authorization: Bearer ${{ secrets.GITHUB_TOKEN }}' \
            --data @- << EOF
          {
            "ref": "refs/tags/$(date +%G.%V)",
            "sha": "${{ github.sha }}"
          }
          EOF
```

このように付加されたタグを用いて、今の最新のHEADからバージョンを計算する。

```sh
cat << 'EOF' > build_tools/integrations/version.sh
#!/bin/bash
set -e

# Calculate version
VERSION_WITH_HASH=$(git describe \
  --tags \
  --long \
  --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" \
  | sed -e 's/-/./;s/-g/+/')

# Show version with git hash
echo "VERSION_WITH_HASH ${VERSION_WITH_HASH}"
# Show version only
echo "VERSION $(echo ${VERSION_WITH_HASH} | cut -d+ -f1)"
# Show git hash only
echo "GIT_SHA $(echo ${VERSION_WITH_HASH} | cut -d+ -f2)"
EOF
chmod +x build_tools/integrations/version.sh
```

このスクリプトを実行すると以下の様に表示される。

```sh
❯ ./build_tools/integrations/version.sh
VERSION_WITH_HASH 2024.42.8+fe2517d
VERSION 2024.42.8
GIT_SHA fe2517d
```

Bazelには `--stamp` オプションおよび `--workspace_status_command` オプションを用いることで、ビルド時に任意の情報を埋め込む機能が存在する。これらを利用して動的に生成したこのバージョンを埋め込む。

```sh
echo 'build --workspace_status_command=build_tools/integrations/version.sh' >> .bazelrc
```

go_binaryルールに以下の様に設定する。

```python:apps/hello_world/BUILD.bazel
go_binary(
    name = "hello_world",
    embed = [":hello_world_lib"],
    visibility = ["//visibility:public"],
    x_defs = {
      "Version": "{VERSION}",
    },
)
```

これにより、bazelでのビルド時に `build_tools/integrations/version.sh` が実行され、その結果が `Version` として埋め込まれる。
ただし、これが実行されるとビルドがキャッシュされなくなるため、デフォルトでは埋め込みは行われない。

```sh
❯ bazel run //apps/hello_world
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.161s, Critical Path: 0.01s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/apps/hello_world/hello_world_/hello_world
Version: dev
Hello, World!(761a756f-b8e7-4bc8-93e4-ff5b945ea6e0)
Reversed: !dlroW ,olleH
OsName: darwin
```

`--stamp` オプションを利用することで、workspace_status_commandの結果をバイナリに埋め込める。

```sh
❯ bazel run --stamp //apps/hello_world
WARNING: Build option --stamp has changed, discarding analysis cache (this can be expensive, see https://bazel.build/advanced/performance/iteration-speed).
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 17633 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.690s, Critical Path: 0.29s
INFO: 2 processes: 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
INFO: Running command line: bazel-bin/apps/hello_world/hello_world_/hello_world
Version: 2024.42.8+fe2517d
Hello, World!(05fe0467-3613-4c5e-bc3c-0ca15f4943db)
Reversed: !dlroW ,olleH
OsName: darwin
```

少し方法は異なるが、イメージのpush時にもバージョン情報を埋め込むことが出来る。ただしコンテナイメージのタグには `+` が使えないことに注意する。
イメージのタグをファイルに書き込み、それを `oci_push` ルールで利用する。このファイルに書き込む際にバージョン情報で値を置換し、stampされたときのみ正しいバージョンを、それ以外では `latest` を使う。この操作を簡単にするために [bazel-lib](https://github.com/bazel-contrib/bazel-lib) を導入する。

```python:MODULE.bazel
bazel_dep(name = "aspect_bazel_lib", version = "2.9.3")
```

```python:apps/fortune_cowsay/BUILD.bazel
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template")

# 中略

expand_template(
    name = "image_tags",
    out = "_stamped.tags.txt",
    template = ["latest"],
    stamp_substitutions = {
        "latest": "{{VERSION}}",
    },
)
oci_push(
    name = "image_push",
    image = ":image_index",
    remote_tags = ":image_tags",
    repository = REPOSITORY,
)
```

更にannotationも同様に生成する。

```python:apps/fortune_cowsay/BUILD.bazel
expand_template(
    name = "image_annotations",
    out = "_stamped.annotations.txt",
    template = [
        "org.opencontainers.image.source=https://github.com/pddg/go-bazel-playground",
        "org.opencontainers.image.version=nightly",
        "org.opencontainers.image.revision=devel",
        "org.opencontainers.image.created=1970-01-01T00:00:00Z",
    ],
    stamp_substitutions = {
        "devel": "{{GIT_SHA}}",
        "nightly": "{{VERSION}}",
        "1970-01-01T00:00:00Z": "{{BUILD_TIMESTAMP_ISO8601}}",
    },
)
oci_image(
    name = "image_push",
    base = base,
    entrypoint = entrypoint,
    tars = tars,
    annotations = ":" + name + "_annotations",
    labels = ":" + name + "_annotations",
)
```

これを使ってイメージをpushする。

```sh
bazel run //apps/fortune_cowsay:image_push
```

https://github.com/pddg/go-bazel-playground/pkgs/container/go-bazel-playground-fortune-cowsay/291870304?tag=2024.42.8

annotationsが正しいかを確認する。

```sh
❯ docker buildx imagetools inspect \
    ghcr.io/pddg/go-bazel-playground-fortune-cowsay:2024.42.8@sha256:c9cb4af3aa8b0987924e895f628b57ed779bd9e59d6b794dc38c2d889d55aa3c \
    --raw \
    | jq -r .annotations
{
  "org.opencontainers.image.source": "https://github.com/pddg/go-bazel-playground",
  "org.opencontainers.image.version": "2024.42.8",
  "org.opencontainers.image.revision": "fe2517d",
  "org.opencontainers.image.created": "2024-10-19T11:59:12Z"
}
```
