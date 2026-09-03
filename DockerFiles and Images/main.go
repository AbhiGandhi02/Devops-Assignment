package main

import (
	"fmt"
	"net/http"
)

const listenAddr = ":8080"

func main() {
	http.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		fmt.Fprintln(writer, "Hello World from Abhi's Docker multi-stage build!")
	})

	fmt.Println("Server listening on port 8080")
	http.ListenAndServe(listenAddr, nil)
}
