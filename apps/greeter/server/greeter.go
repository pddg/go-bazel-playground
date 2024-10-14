package server

import (
	"context"

	hellov1 "github.com/pddg/go-bazel-playground/proto/hello/v1"
)

// GreeterServer is the server API for Greeter service.
type GreeterServer struct {
	hellov1.UnimplementedGreeterServer
}

// NewGreeterServer creates a new GreeterServer.
func NewGreeterServer() *GreeterServer {
	return &GreeterServer{}
}

// SayHello implements GreeterServer
func (s *GreeterServer) SayHello(ctx context.Context, in *hellov1.HelloRequest) (*hellov1.HelloResponse, error) {
	return &hellov1.HelloResponse{
		Message: "Hello, " + in.Name,
	}, nil
}
