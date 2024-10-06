package main

import (
	"fmt"

	"github.com/google/uuid"
)

func main() {
	uuidStr := uuid.NewString()
	fmt.Printf("Hello, World!(%s)\n", uuidStr)
}
