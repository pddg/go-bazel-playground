# Unit test

ここでは、 `go test` コマンドを使って単体テストを実行する方法を説明する。

## Create a test file

前回作成した `reverse` パッケージに対して、単体テストを実装する。

```go:internal/reverse/string_test.go
package reverse_test

import (
    "testing"

    "github.com/pddg/go-bazel-playground/internal/reverse"
)

func TestString(t *testing.T) {
    t.Parallel()
    tests := []struct {
        name     string
        given    string
        expected string
    }{
        {
            name:     "empty",
            given:    "",
            expected: "",
        },
        {
            name:     "single",
            given:    "a",
            expected: "a",
        },
        {
            name:     "multiple",
            given:    "abc",
            expected: "cba",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            actual := reverse.String(tt.given)
            if actual != tt.expected {
                t.Errorf("expected: %s, actual: %s", tt.expected, actual)
            }
        })
    }
}
```

## Run the test

Bazelでは単体テストもビルドと同様に抽象化されたルールを通して実行する。
これによりBazelはテストの依存関係を解決し、必要なテストのみを実行する。

rules_goでは `go_test` というルールが用意されている。Gazelleを使うことでテストファイルの依存関係を解決し、 `BUILD.bazel` に自動で追記できる。

```bash
bazel run //:gazelle
```

これにより、 `internal/reverse/BUILD.bazel` が以下の様に更新される。

```diff:internal/reverse/BUILD.bazel
diff --git a/internal/reverse/BUILD.bazel b/internal/reverse/BUILD.bazel
index dd7f598..43227d0 100644
--- a/internal/reverse/BUILD.bazel
+++ b/internal/reverse/BUILD.bazel
@@ -1,4 +1,4 @@
-load("@rules_go//go:def.bzl", "go_library")
+load("@rules_go//go:def.bzl", "go_library", "go_test")
 
 go_library(
     name = "reverse",
@@ -6,3 +6,9 @@ go_library(
     importpath = "github.com/pddg/go-bazel-playground/internal/reverse",
     visibility = ["//:__subpackages__"],
 )
+
+go_test(
+    name = "reverse_test",
+    srcs = ["string_test.go"],
+    deps = [":reverse"],
+)
```

`bazel test` コマンドでテストを実行する。

```bash
bazel test //internal/reverse:reverse_test
```

```
❯ bazel test //internal/reverse:reverse_test
INFO: Analyzed target //internal/reverse:reverse_test (4 packages loaded, 27 targets configured).
INFO: Found 1 test target...
Target //internal/reverse:reverse_test up-to-date:
  bazel-bin/internal/reverse/reverse_test_/reverse_test
INFO: Elapsed time: 0.582s, Critical Path: 0.32s
INFO: 12 processes: 4 internal, 8 linux-sandbox.
INFO: Build completed successfully, 12 total actions
//internal/reverse:reverse_test                                          PASSED in 0.0s

Executed 1 out of 1 test: 1 test passes.
There were tests whose specified size is too big. Use the --test_verbose_timeout_warnings command line option to see which ones these are.
```

テストが成功したことが確認できる。二度目以降の実行はキャッシュされており実行されない。

```
❯ bazel test //internal/reverse:reverse_test
INFO: Analyzed target //internal/reverse:reverse_test (0 packages loaded, 0 targets configured).
INFO: Found 1 test target...
Target //internal/reverse:reverse_test up-to-date:
  bazel-bin/internal/reverse/reverse_test_/reverse_test
INFO: Elapsed time: 0.139s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
//internal/reverse:reverse_test                                 (cached) PASSED in 0.0s

Executed 0 out of 1 test: 1 test passes.
There were tests whose specified size is too big. Use the --test_verbose_timeout_warnings command line option to see which ones these are.
```

## Tips: テストサイズ

上記の実行結果にはWarningが表示されている。表示されている通り、`--test_verbose_timeout_warnings` オプションを使うことで詳細な情報を表示することができる。
このオプションはコマンドラインから指定しても良いが、`.bazelrc` ファイルに設定することでデフォルトで有効にすることができる。

```bash
test --test_output=errors --test_verbose_timeout_warnings
```

この状態でテストを再実行してみる。

```
❯ bazel test //internal/reverse:reverse_test
INFO: Analyzed target //internal/reverse:reverse_test (1 packages loaded, 4 targets configured).
INFO: Found 1 test target...
Target //internal/reverse:reverse_test up-to-date:
  bazel-bin/internal/reverse/reverse_test_/reverse_test
INFO: Elapsed time: 0.182s, Critical Path: 0.02s
INFO: 2 processes: 1 internal, 1 linux-sandbox.
INFO: Build completed successfully, 2 total actions
//internal/reverse:reverse_test                                          PASSED in 0.0s
  WARNING: //internal/reverse:reverse_test: Test execution time (0.0s excluding execution overhead) outside of range for MODERATE tests. Consider setting timeout="short" or size="small".

Executed 1 out of 1 test: 1 test passes.
```

このWarningはテストの実行時間が指定されたタイムアウト時間 `MODERATE` に対して小さすぎるために発生している。

bazelではテストに対しその大きさを指定することができる。テストの大きさは以下の4つのカテゴリに分類される。
また、各テストサイズには暗黙的にタイムアウトが設定されている。

| size     | timeout label | timeout (sec) |
|----------|---------------|---------------|
| small    | short         | 60            |
| medium   | moderate      | 300           |
| large    | long          | 900           |
| enormous | eternal       | 3600          |

Ref: https://bazel.build/reference/test-encyclopedia#role-test-runner

デフォルトではタイムアウトに `MODERATE` が設定されているため、 `MODERATE` に対して小さすぎるテストはWarningが表示される。

テストの大きさは `size` パラメータで指定することができるため、gazelleが生成した `BUILD.bazel` に `size` パラメータを追記することでWarningを解消できる。

```diff:internal/reverse/BUILD.bazel
diff --git a/internal/reverse/BUILD.bazel b/internal/reverse/BUILD.bazel
index 43227d0..aab058e 100644
--- a/internal/reverse/BUILD.bazel
+++ b/internal/reverse/BUILD.bazel
@@ -9,6 +9,7 @@ go_library(
 
 go_test(
     name = "reverse_test",
+    size = "small",
     srcs = ["string_test.go"],
     deps = [":reverse"],
 )
```

これでWarningが表示されなくなる。

```
❯ bazel test //internal/reverse:reverse_test
INFO: Analyzed target //internal/reverse:reverse_test (1 packages loaded, 4 targets configured).
INFO: Found 1 test target...
Target //internal/reverse:reverse_test up-to-date:
  bazel-bin/internal/reverse/reverse_test_/reverse_test
INFO: Elapsed time: 0.187s, Critical Path: 0.02s
INFO: 2 processes: 1 internal, 1 linux-sandbox.
INFO: Build completed successfully, 2 total actions
//internal/reverse:reverse_test                                          PASSED in 0.0s

Executed 1 out of 1 test: 1 test passes.
```

## Conclusion

Bazelを使ってGoアプリケーションの単体テストを実行する方法を学んだ。
Bazelでは単体テストもビルドと同様に抽象化されたルールを通して実行でき、Bazelはその依存関係を解決して必要なテストのみを実行する。
テストにはサイズとタイムアウトという概念があり、テストの大きさによって暗黙的に設定されるタイムアウトが異なる。適切なテストサイズ・タイムアウトを指定するべきである。
