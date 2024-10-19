package main

import (
	"fmt"

	"github.com/google/uuid"

	"github.com/pddg/go-bazel-playground/internal/reverse"
)

var Version = "dev"

func main() {
	fmt.Printf("Version: %s\n", Version)
	uuidStr := uuid.NewString()
	fmt.Printf("Hello, World!(%s)\n", uuidStr)
	fmt.Printf("Reversed: %s\n", reverse.String("Hello, World!"))
	fmt.Printf("OsName: %s\n", OsName)
}
