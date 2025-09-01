package main

import (
	"fmt"
)

// Greeting returns the standard hydra greeting string.
func Greeting() string { return "Hello from Hydra!" }

func main() {
	fmt.Println(Greeting())
}
