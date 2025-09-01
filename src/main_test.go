package main

import (
	"fmt"
	"testing"

	"github.com/Caracal-IT/hydra/src/gohydra"
)

func TestGreeting(t *testing.T) {
	got := gohydra.Greeting()
	want := "Hello from Hydra!"
	if got != want {
		t.Fatalf("Greeting() = %q, want %q", got, want)
	}
}

func BenchmarkGreeting(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_ = gohydra.Greeting()
	}
}

// ExampleGreeting shows the output of Greeting.
func ExampleGreeting() {
	fmt.Println(gohydra.Greeting())
	// Output:
	// Hello from Hydra!
}
