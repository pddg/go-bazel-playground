# Editor integration

bazelでは自動で生成されるファイルはサンドボックス内に配置されるため、リポジトリにコミットされない。そのためgRPCの自動生成されたパッケージをインポートする場合、エディタがパッケージを見つけられない状態になる。

これは開発体験が非常に悪いので、補完などが動作するようにするための設定を行う。

過去の記事ではbazelが自動生成したファイルを実際にリポジトリ内に持ち込んでコミットし、それを参照する方法が紹介されていることが多かったが、現代では選択肢は他にもあるためそれを紹介する。

## integrate with gopls

goplsはGoのエディタサポートを提供するツールで、Language Server Protocolを実装している。これは通常リポジトリルートにある `go.mod` ファイルと、ホスト上の `~/go/mod` などを読み取ることで、補完などを提供している。

bazelによって生成されるファイルなどの情報をgoplsに提供するためには、 `GOPACKAGESDRIVER` という環境変数を利用する。
これは通常とは異なるビルドシステムを利用する場合でも、goパッケージを読み込みその依存関係を認識するために必要なメタデータを提供する、別のプログラムを指定できるようにする機能である。
rules_go にはこの機能が実装されている。

まずはこれを起動するためのスクリプトを作成する。

```sh
mkdir -p build_tools/integrations
cat << 'EOF' > build_tools/integrations/gopackagesdriver.sh
#!/usr/bin/env bash
# See https://github.com/bazelbuild/rules_go/wiki/Editor-setup#3-editor-setup
exec bazel run -- @rules_go//go/tools/gopackagesdriver "${@}"
EOF
chmod +x build_tools/integrations/gopackagesdriver.sh
```

ここでは例としてVSCodeを用いるが、vimなど他のエディタでもgoplsを用いる場合は概ね同様の設定をする。詳しくは以下を参照すること。
https://github.com/bazelbuild/rules_go/wiki/Editor-and-tool-integration

また、以下の拡張機能を予めインストールしておくこと。
https://marketplace.visualstudio.com/items?itemName=golang.Go

VSCodeは開いているプロジェクト直下に `.vscode` ディレクトリがある場合、そのディレクトリ内の設定ファイルを読み込む。これを利用してこのリポジトリにおける設定を一部上書きする。

```sh
mkdir -p .vscode
```

```json:.vscode/settings.json
{
    "go.goroot": "${workspaceFolder}/bazel-${workspaceFolderBasename}/external/rules_go~~go_sdk~${workspaceFolderBasename}__download_0/",
    "go.toolsEnvVars": {
        "GOPACKAGESDRIVER": "${workspaceFolder}/build_tools/integrations/gopackagesdriver.sh"
    },
    "gopls": {
        "build.directoryFilters": [
            "-bazel-bin",
            "-bazel-out",
            "-bazel-testlogs",
            "-bazel-mypkg",
        ],
    },
    "go.useLanguageServer": true,
}
```

最小限の設定としてはこうなる。wikiでは更に余計な機能の無効化や、フォーマット設定の変更などが記載されているので、必要に応じてそれらも設定する。

念のため利用時にはGo Language Serverを再起動する。 `Ctrl + Shift + P` でコマンドパレットを開き、 `Go: Restart Language Server` を選択する。

### Tips: import時にmodule not found

通常のGoの開発プロジェクトの場合、これは `go mod tidy` したり一度ビルドして依存関係をダウンロードすると、goplsがその依存関係を認識できるようになり、補完が動作するようになる。

bazelはBUILDファイル内で許可された依存関係のみを `GOPACKAGESDRIVER` を用いてgoplsに伝える。よって、 `go.mod`に記載されているからといって、あるモジュール内でそのモジュールの依存解決ができるわけではない。

例えば`go.mod` には `google.golang.org/grpc` があるが、ビルド対象の `main.go` に対応する `BUILD.bazel` 内でdependencyとして `google.golang.org/grpc` が指定されていなければ、goplsは存在しない依存として報告する。
この場合、gazelleを用いてビルドファイルを生成し、正しい依存関係をgoplsに伝える。

```sh
# 必要なら
# bazel run @rules_go//go -- mod tidy
# bazel run //:update-go-repos
bazel run //:gazelle
```

これにより必要な依存関係が追加されたビルドファイルが生成され、ビルド・エディタでの補完が動作するようになる。

### Pros/Cons

- Pros
  - bazelのビルドファイルを利用するため、bazelのビルド設定に従った補完が可能
  - bazelがルールに従って自動生成したファイルも補完対象になる
- Cons
  - 遅い
    - 内部的にはbazel queryなどを活用しているため、goplsのように単にファイルシステムをスキャンするだけのものよりも遅い
  - ビルドファイルの生成が必要
    - 依存関係が変わるたびにビルドファイルを更新する必要がある
    - 依存関係の変更は成熟したプロダクトではそれほど多い作業ではないものの、新規開発中などでは頻繁に行うことがある

結局bazelを使ってビルド・テストの実行を行うため、VSCodeのGo extensionにあるテストケースごとの実行などはサポートされていない。
go.modは維持しているため、bazelによる自動生成ファイルが依存上にないこと・サードパーティモジュールをbazelでパッチしていないことなど、いくつかの条件の上ではそれらを使うことは依然として可能であるが、やらない方が良いだろう。

## Conclusion

goplsを使っている場合、`GOPACKAGESDRIVER` 環境変数を利用することで、補完などの機能を使うことができる。
動作はやや遅いものの、bazelが自動生成したファイルや、パッチを当てたサードパーティモジュールなども補完対象になる。
ただし、bazelのビルドにおける依存関係をそのまま利用するため、必要なら依存が記述された正しいビルドファイルの生成が必要であることに注意する。
