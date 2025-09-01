package gohydra

import (
	"fmt"
	"testing"
)

func TestGreeting(t *testing.T) {
	got := Greeting()
	want := "Hello from Hydra!!"
	if got != want {
		t.Fatalf("Greeting() = %q, want %q", got, want)
	}
}

func BenchmarkGreeting(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_ = Greeting()
	}
}

// ExampleGreeting shows the output of Greeting.
func ExampleGreeting() {
	fmt.Println(Greeting())
	// Output:
	// Hello from Hydra!
}
