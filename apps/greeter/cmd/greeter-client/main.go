package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	hellov1 "github.com/pddg/go-bazel-playground/proto/hello/v1"
)

func main() {
	serverAddr := flag.String("server", "localhost:8080", "server address")
	flag.Parse()

	name := flag.Arg(0)

	client, err := grpc.NewClient(
		*serverAddr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create client: %v\n", err)
	}
	res, err := hellov1.NewGreeterClient(client).SayHello(context.Background(), &hellov1.HelloRequest{
		Name: name,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to call SayHello: %v\n", err)
	}
	fmt.Println(res.Message)
}
