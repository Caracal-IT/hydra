package main

import (
	"bytes"
	"fmt"
	"os"
	"testing"
)

func TestGreeting(t *testing.T) {
	// Validate Greeting logic
	got := Greeting()
	want := "Hello from Hydra!"
	if got != want {
		t.Fatalf("Greeting() = %q, want %q", got, want)
	}

	// Capture and validate main() output (consolidated from former main_extra_test.go)
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe error: %v", err)
	}

	// Ensure stdout restoration and reader closure even on failure
	os.Stdout = w
	defer func() {
		// restore stdout unconditionally
		os.Stdout = orig
		// best-effort close reader
		if cerr := r.Close(); cerr != nil {
			// use t.Log rather than failing inside defer
			t.Logf("warning: failed to close pipe reader: %v", cerr)
		}
	}()

	// Run main which writes to stdout
	main()

	// Close writer to signal EOF to reader
	if cerr := w.Close(); cerr != nil {
		t.Fatalf("failed to close pipe writer: %v", cerr)
	}

	// Read captured output
	var buf bytes.Buffer
	if _, err := buf.ReadFrom(r); err != nil {
		t.Fatalf("failed to read from pipe: %v", err)
	}
	out := buf.String()
	if out != "Hello from Hydra!\n" {
		t.Fatalf("unexpected main output: %q", out)
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
