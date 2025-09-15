package main

import (
	"fmt"

	"github.com/Caracal-IT/hydra/logger"
)

// Greeting returns the standard hydra greeting string.
func Greeting() string { return "Hello from Hydra!" }

func main() {
	// Initialize logger (exits on error).
	// Use empty path so Setup searches default locations instead of attempting
	// to open a relative file that may not exist from the current working dir.
	logger.MustSetup("")

	// Emit a dummy log entry
	if logger.Log != nil {
		logger.Log.WithFields(map[string]interface{}{
			"service": "hydra",
			"event":   "dummy_entry",
			"version": "0.1.0",
		}).Info("Dummy log entry: application initialized")
	}

	fmt.Println(Greeting())
}
