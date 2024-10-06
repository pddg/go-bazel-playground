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
