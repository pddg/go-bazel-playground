# Lint sources

Goといえば静的解析ツールが容易で、様々な側面からコードを自動的にチェックできる。
bazelを使う場合でもこれらの静的解析ツールによる指摘を通して、コード決済の品質を維持できる。

## Run lint with nogo

rules_goには `nogo` というルールが用意されている。
これは `golang.org/x/tools/go/analysis` パッケージを使ってGoの静的解析を行う。

`go vet` コマンドのヘルプに利用可能な解析器の一覧がある。

```
❯ bazel run @rules_go//go -- tool vet help
Starting local Bazel server and connecting to it...
INFO: Analyzed target @@rules_go~//go:go (103 packages loaded, 12207 targets configured).
INFO: Found 1 target...
Target @@rules_go~//go/tools/go_bin_runner:go_bin_runner up-to-date:
  bazel-bin/external/rules_go~/go/tools/go_bin_runner/bin/go
INFO: Elapsed time: 4.885s, Critical Path: 0.12s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/external/rules_go~/go/tools/go_bin_runner/bin/go tool vet help
vet is a tool for static analysis of Go programs.

vet examines Go source code and reports suspicious constructs,
such as Printf calls whose arguments do not align with the format
string. It uses heuristics that do not guarantee all reports are
genuine problems, but it can find errors not caught by the compilers.

Registered analyzers:

    appends      check for missing values after append
    asmdecl      report mismatches between assembly files and Go declarations
    assign       check for useless assignments
    atomic       check for common mistakes using the sync/atomic package
    bools        check for common mistakes involving boolean operators
    buildtag     check //go:build and // +build directives
    cgocall      detect some violations of the cgo pointer passing rules
    composites   check for unkeyed composite literals
    copylocks    check for locks erroneously passed by value
    defers       report common mistakes in defer statements
    directive    check Go toolchain directives such as //go:debug
    errorsas     report passing non-pointer or non-error values to errors.As
    framepointer report assembly that clobbers the frame pointer before saving it
    httpresponse check for mistakes using HTTP responses
    ifaceassert  detect impossible interface-to-interface type assertions
    loopclosure  check references to loop variables from within nested functions
    lostcancel   check cancel func returned by context.WithCancel is called
    nilfunc      check for useless comparisons between functions and nil
    printf       check consistency of Printf format strings and arguments
    shift        check for shifts that equal or exceed the width of the integer
    sigchanyzer  check for unbuffered channel of os.Signal
    slog         check for invalid structured logging calls
    stdmethods   check signature of methods of well-known interfaces
    stdversion   report uses of too-new standard library symbols
    stringintconv check for string(int) conversions
    structtag    check that struct field tags conform to reflect.StructTag.Get
    testinggoroutine report calls to (*testing.T).Fatal from goroutines started by a test
    tests        check for common mistaken usages of tests and examples
    timeformat   check for calls of (time.Time).Format or time.Parse with 2006-02-01
    unmarshal    report passing non-pointer or non-interface values to unmarshal
    unreachable  check for unreachable code
    unsafeptr    check for invalid conversions of uintptr to unsafe.Pointer
    unusedresult check for unused results of calls to some functions

# 以下略
```

まずは `BUILD.bazel` に `nogo` ルールを追加する。 `go vet` の提供する解析器を個別に指定することもできるが、rules_goの提供する `TOOLS_NOGO` という変数を使うことで全てを簡単に指定できる。
https://github.com/bazelbuild/rules_go/blob/9741b368beafbe8af173de66bf1ec649ce64c5b0/go/def.bzl#L81-L118

```python:BUILD.bazel
load("@rules_go//go:def.bzl", "nogo", "TOOLS_NOGO")

nogo(
    name = "my_nogo",
    deps = TOOLS_NOGO,
    visibility = ["//visibility:public"],
)
```

次に `MODULE.bazel` に今定義した `my_nogo` を使うように指定する。

```python:MODULE.bazel
go_sdk.nogo(
    nogo = "//:my_nogo",
    includes = [
        "//:__subpackages__",
    ],
)
```

これにより、ビルド時に自動で静的解析を実行するようになる。

```
❯ bazel build //...
INFO: Analyzed 7 targets (196 packages loaded, 17123 targets configured).
INFO: Found 7 targets...
INFO: Elapsed time: 3.134s, Critical Path: 1.52s
INFO: 84 processes: 15 internal, 69 linux-sandbox.
INFO: Build completed successfully, 84 total actions
```

試しに違反するコードを書いてみる。

```diff:apps/hello_world/main.go
❯ git diff apps/hello_world/main.go                                          
diff --git a/apps/hello_world/main.go b/apps/hello_world/main.go
index 84a2eaf..8697f5d 100644
--- a/apps/hello_world/main.go
+++ b/apps/hello_world/main.go
@@ -10,5 +10,5 @@ import (
 func main() {
        uuidStr := uuid.NewString()
        fmt.Printf("Hello, World!(%s)\n", uuidStr)
-       fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"))
+       fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"), "dummy")
 }
```

再度ビルドを実行すると、失敗することがわかる。
（二回エラーが出力されるのは、libraryとしてのビルド時と、実行バイナリのビルド時の両方からエラーが出るためで、おそらく二回実行しているわけではない）

```
❯ bazel build //apps/hello_world
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:9:11: Validating nogo output for //apps/hello_world:hello_world_lib failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world_lib) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world_lib.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:13:2: fmt.Printf call needs 1 arg but has 2 args (printf)

ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:3:10: Validating nogo output for //apps/hello_world:hello_world failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:13:2: fmt.Printf call needs 1 arg but has 2 args (printf)

Target //apps/hello_world:hello_world failed to build
Use --verbose_failures to see the command lines of failed build steps.
INFO: Elapsed time: 0.174s, Critical Path: 0.01s
INFO: 4 processes: 4 internal.
ERROR: Build did NOT complete successfully
```

## Use other linters

nogoは `Analyzer` という名前で [Analyzer](https://godoc.org/golang.org/x/tools/go/analysis#Analyzer) 型の変数を提供するパッケージと互換性がある。
これにより、自分で自前の解析器を作成することも、サードパーティの解析器を利用することもできる。

ここではまず、[nilerr](https://github.com/gostaticanalysis/nilerr)という解析器を利用してみる。
サードパーティの解析器を利用するためには、まずそのモジュールを依存関係に追加しなければならない。

```bash
bazel run @rules_go//go -- get github.com/gostaticanalysis/nilerr
cat << EOF > tools.go
package tools

import (
	_ "github.com/gostaticanalysis/nilerr"
)
EOF
bazel run @rules_go//go -- mod tidy
```

gazelleでこれらの変更を自動で反映させる。

```bash
bazel run //:update-go-repos
bazel run //:gazelle
```

`my_nogo` にnilerrを追加する。

```diff:BUILD.bazel
❯ git diff BUILD.bazel             
diff --git a/BUILD.bazel b/BUILD.bazel
index 7edba89..e489b5a 100644
--- a/BUILD.bazel
+++ b/BUILD.bazel
@@ -20,7 +20,9 @@ gazelle(
 nogo(
     name = "my_nogo",
     visibility = ["//visibility:public"],
-    deps = TOOLS_NOGO,
+    deps = TOOLS_NOGO + [
+        "@com_github_gostaticanalysis_nilerr//:nilerr",
+    ],
 )
```

ビルドを実行すると、nilerrによる解析も実行されるようになる。ここでは特に違反しないためビルドが通る。

```
❯ bazel build //apps/hello_world
INFO: Analyzed target //apps/hello_world:hello_world (1 packages loaded, 100 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 0.327s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
```

次に、違反するコードを追加してみる。

```diff:apps/hello_world/main.go
diff --git a/apps/hello_world/main.go b/apps/hello_world/main.go
index 84a2eaf..92762a2 100644
--- a/apps/hello_world/main.go
+++ b/apps/hello_world/main.go
@@ -7,8 +7,17 @@ import (
        "github.com/pddg/go-bazel-playground/internal/reverse"
 )
 
+func getUUID() (string, error) {
+       u, err := uuid.NewRandom()
+       if err != nil {
+               // This violates the rule of nilerr
+               return "", nil
+       }
+       return u.String(), nil
+}
+
 func main() {
-       uuidStr := uuid.NewString()
+       uuidStr, _ := getUUID()
        fmt.Printf("Hello, World!(%s)\n", uuidStr)
        fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"))
 }
```

このコードは、エラーを握りつぶしてnilを返している。これはnilerrによって違反として検出される。

```
❯ bazel build //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:3:10: Validating nogo output for //apps/hello_world:hello_world failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:14:3: error is not nil (line 11) but it returns nil (nilerr)

ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:9:11: Validating nogo output for //apps/hello_world:hello_world_lib failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world_lib) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world_lib.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:14:3: error is not nil (line 11) but it returns nil (nilerr)

Target //apps/hello_world:hello_world failed to build
Use --verbose_failures to see the command lines of failed build steps.
INFO: Elapsed time: 0.140s, Critical Path: 0.01s
INFO: 4 processes: 4 internal.
ERROR: Build did NOT complete successfully
```

## Use self-implemented linters

自前の解析器を作成することもできる。実装にはanalyticsパッケージを使うので、まずはそれを含む `golang.org/x/tools` パッケージを依存関係に追加する。

```bash
bazel run @rules_go//go -- get golang.org/x/tools
```

解析器を実装する。今回はサンプルであり、何でも良いので全ての関数を探索して `sample` という名前の関数があったら違反として報告させる。

```go:analyzers/sample/sample.go
package sample

import (
	"go/ast"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/passes/inspect"
	"golang.org/x/tools/go/ast/inspector"
)

var Analyzer = &analysis.Analyzer{
	Name: "sample",
	Doc:  "sample analyzer",
	Run:  run,
	Requires: []*analysis.Analyzer{
		inspect.Analyzer,
	},
}

func run(pass *analysis.Pass) (interface{}, error) {
	i := pass.ResultOf[inspect.Analyzer].(*inspector.Inspector)

	//  関数の定義定義のみを取得
	filter := []ast.Node{
		(*ast.FuncDecl)(nil),
	}
	i.Preorder(filter, func(n ast.Node) {
		fn := n.(*ast.FuncDecl)
		// 関数名がsampleの場合に警告を出す
		if fn.Name.Name == "sample" {
			pass.Reportf(fn.Pos(), "sample function found")
		}
	})
	return nil, nil
}
```

go mod tidyしてgazelleに依存を更新・BUILD.bazelを生成させる。

```bash
bazel run @rules_go//go -- mod tidy
bazel run //:update-go-repos
bazel run //:gazelle
```

`my_nogo` に `sample` を追加する。

```diff:BUILD.bazel
❯ git diff BUILD.bazel
diff --git a/BUILD.bazel b/BUILD.bazel
index e489b5a..5bacb0a 100644
--- a/BUILD.bazel
+++ b/BUILD.bazel
@@ -22,6 +22,7 @@ nogo(
     visibility = ["//visibility:public"],
     deps = TOOLS_NOGO + [
         "@com_github_gostaticanalysis_nilerr//:nilerr",
+        "//analyzers/sample:sample",
     ],
 )
```

ビルドを実行すると、sampleによる解析も実行されるようになる。今はsampleという関数はなく、ビルドは失敗しない。

```
❯ bazel build //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (3 packages loaded, 119 targets configured).
INFO: Found 1 target...
Target //apps/hello_world:hello_world up-to-date:
  bazel-bin/apps/hello_world/hello_world_/hello_world
INFO: Elapsed time: 1.423s, Critical Path: 1.23s
INFO: 62 processes: 2 internal, 60 linux-sandbox.
INFO: Build completed successfully, 62 total action
```

違反するコードを追加してみる。

```diff:apps/hello_world/main.go
diff --git a/apps/hello_world/main.go b/apps/hello_world/main.go
index 84a2eaf..77995ab 100644
--- a/apps/hello_world/main.go
+++ b/apps/hello_world/main.go
@@ -7,8 +7,13 @@ import (
        "github.com/pddg/go-bazel-playground/internal/reverse"
 )
 
+func sample() {
+       fmt.Println("sample")
+}
+
 func main() {
        uuidStr := uuid.NewString()
        fmt.Printf("Hello, World!(%s)\n", uuidStr)
        fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"))
+       sample()
 }
```

ビルドを実行すると、sample analyzerによる解析によって違反が検出され、ビルドが失敗する。

```
❯ bazel build //apps/hello_world:hello_world
INFO: Analyzed target //apps/hello_world:hello_world (0 packages loaded, 0 targets configured).
ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:9:11: Validating nogo output for //apps/hello_world:hello_world_lib failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world_lib) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world_lib.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:10:1: sample function found (sample)

ERROR: /home/pudding/ghq/github.com/pddg/go-bazel-playground/apps/hello_world/BUILD.bazel:3:10: Validating nogo output for //apps/hello_world:hello_world failed: (Exit 1): builder failed: error executing ValidateNogo command (from target //apps/hello_world:hello_world) bazel-out/k8-opt-exec-ST-d57f47055a04/bin/external/rules_go~~go_sdk~go-bazel-playground__download_0/builder_reset/builder nogovalidation bazel-out/k8-fastbuild/bin/apps/hello_world/hello_world.nogo ... (remaining 1 argument skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging

nogo: errors found by nogo during build-time code analysis:
apps/hello_world/main.go:10:1: sample function found (sample)

Target //apps/hello_world:hello_world failed to build
Use --verbose_failures to see the command lines of failed build steps.
INFO: Elapsed time: 0.170s, Critical Path: 0.03s
INFO: 6 processes: 4 internal, 2 linux-sandbox.
ERROR: Build did NOT complete successfully
```

## Conclusion

rules_goの提供するnogoを使うことで、ビルド時に静的解析を実行することができる。
この静的解析はGoの準標準パッケージである `golang.org/x/tools/go/analysis` を使って実装でき、go vetの提供する解析器を使うことも、サードパーティの解析器を使うことも、自前の解析器を作成することもできる。
