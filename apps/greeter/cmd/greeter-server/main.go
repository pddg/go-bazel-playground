package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"

	"google.golang.org/grpc"

	greeterserver "github.com/pddg/go-bazel-playground/apps/greeter/server"
	hellov1 "github.com/pddg/go-bazel-playground/proto/hello/v1"
)

func main() {
	server := grpc.NewServer()
	hellov1.RegisterGreeterServer(server, greeterserver.NewGreeterServer())

	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to listen: %v\n", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	go func() {
		if err := server.Serve(listener); err != nil {
			fmt.Fprintf(os.Stderr, "failed to serve: %v\n", err)
		}
	}()
	<-ctx.Done()
	server.GracefulStop()
}
