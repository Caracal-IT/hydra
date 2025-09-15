package logger

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/elastic/go-elasticsearch/v8"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

// Config represents logger configuration loaded from a file.
type Config struct {
	Level         string `mapstructure:"level"`
	ConsoleFormat string `mapstructure:"console_format"` // "text" or "json"
	Elasticsearch struct {
		Enabled            bool   `mapstructure:"enabled"`
		URL                string `mapstructure:"url"`
		Index              string `mapstructure:"index"`
		Username           string `mapstructure:"username"`
		Password           string `mapstructure:"password"`
		InsecureSkipVerify bool   `mapstructure:"insecure_skip_verify"`
		Retries            int    `mapstructure:"retries"`
		QueueSize          int    `mapstructure:"queue_size"`
		BatchSize          int    `mapstructure:"batch_size"`
		FlushInterval      string `mapstructure:"flush_interval"` // duration string
	} `mapstructure:"elasticsearch"`
}

// Log is the package-level logger instance.
var Log *logrus.Logger

// Setup reads configuration from the provided path and configures the logger.
// If configPath is empty it will try to read ./logger.yaml or ./logger.json.
func Setup(configPath string) error {
	v := viper.New()
	// sensible defaults so env-only configs work
	v.SetDefault("level", "info")
	v.SetDefault("console_format", "text")
	v.SetDefault("elasticsearch.enabled", false)
	v.SetDefault("elasticsearch.url", "http://localhost:9200")
	v.SetDefault("elasticsearch.index", "logs")
	v.SetDefault("elasticsearch.insecure_skip_verify", false)
	v.SetDefault("elasticsearch.retries", 1)

	if configPath == "" {
		v.SetConfigName("logger")
		v.AddConfigPath(".")
	} else {
		v.SetConfigFile(configPath)
	}
	v.SetEnvPrefix("LOGGER")
	v.AutomaticEnv()
	_ = v.BindEnv("elasticsearch.insecure_skip_verify", "ELASTIC_INSECURE_SKIP_VERIFY")
	_ = v.BindEnv("elasticsearch.retries", "ELASTIC_RETRIES")

	// Try to read config from the usual locations. If not found, search up
	// ancestor directories for logger.example.yaml or logger.yaml as a fallback.
	if err := v.ReadInConfig(); err != nil {
		cwd, _ := os.Getwd()
		dir := cwd
		found := false
		for i := 0; i < 6 && dir != "." && dir != string(filepath.Separator); i++ {
			candidates := []string{
				filepath.Join(dir, "logger.example.yaml"),
				filepath.Join(dir, "logger.yaml"),
				filepath.Join(dir, "logger.yml"),
			}
			for _, cand := range candidates {
				if _, statErr := os.Stat(cand); statErr == nil {
					v.SetConfigFile(cand)
					if rcErr := v.ReadInConfig(); rcErr == nil {
						found = true
						break
					}
				}
			}
			if found {
				break
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
		if !found {
			_, _ = fmt.Fprintf(os.Stderr, "logger: no configuration file found: %v\n", err)
		}
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return fmt.Errorf("failed to decode logger config: %w", err)
	}

	log := logrus.New()
	// Formatter
	switch cfg.ConsoleFormat {
	case "json":
		log.Formatter = &logrus.JSONFormatter{TimestampFormat: time.RFC3339}
	default:
		log.Formatter = &logrus.TextFormatter{FullTimestamp: true, TimestampFormat: time.RFC3339}
	}

	// Level
	level, err := logrus.ParseLevel(cfg.Level)
	if err != nil {
		level = logrus.InfoLevel
	}
	log.SetLevel(level)

	// Output to stdout
	log.SetOutput(os.Stdout)

	// Elasticsearch hook: configure client and add hook if enabled
	if cfg.Elasticsearch.Enabled {
		// configure transport so TLS verification can be disabled when using self-signed certs
		transport := http.DefaultTransport.(*http.Transport).Clone()
		if cfg.Elasticsearch.InsecureSkipVerify {
			if transport.TLSClientConfig == nil {
				transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
			} else {
				transport.TLSClientConfig.InsecureSkipVerify = true
			}
		}

		esCfg := elasticsearch.Config{
			Addresses: []string{cfg.Elasticsearch.URL},
			Username:  cfg.Elasticsearch.Username,
			Password:  cfg.Elasticsearch.Password,
			Transport: transport,
		}
		es, err := elasticsearch.NewClient(esCfg)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "logger: failed to create elasticsearch client: %v\n", err)
		} else {
			// do not print ES Info on startup in production; keep hook installation silent
			hook := &ESHook{Client: es, Index: cfg.Elasticsearch.Index, Retries: cfg.Elasticsearch.Retries}
			log.AddHook(hook)
		}
	}

	Log = log
	return nil
}

// ESHook indexes each log entry into Elasticsearch (best-effort, non-fatal).
type ESHook struct {
	Client  *elasticsearch.Client
	Index   string
	Retries int
}

func (h *ESHook) Levels() []logrus.Level { return logrus.AllLevels }

func (h *ESHook) Fire(entry *logrus.Entry) error {
	// Prepare payload
	data := make(map[string]interface{})
	for k, v := range entry.Data {
		data[k] = v
	}
	// Add fields expected by Kibana: @timestamp and message
	data["@timestamp"] = entry.Time.Format(time.RFC3339)
	data["message"] = entry.Message
	data["level"] = entry.Level.String()
	data["timestamp"] = entry.Time.Format(time.RFC3339)

	b, err := json.Marshal(data)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "logger: failed to marshal log entry for ES: %v\n", err)
		return nil
	}

	index := h.Index
	if index == "" {
		index = "logs"
	}

	// Use a short timeout for indexing so hook doesn't block indefinitely
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	attempts := 1
	if h.Retries > 0 {
		attempts = h.Retries
	}

	for i := 0; i < attempts; i++ {
		res, err := h.Client.Index(index, bytes.NewReader(b), h.Client.Index.WithContext(ctx), h.Client.Index.WithRefresh("true"))
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "logger: ES index attempt %d/%d failed: %v\n", i+1, attempts, err)
			if ctx.Err() != nil {
				break
			}
			time.Sleep(100 * time.Millisecond)
			continue
		}
		if res != nil {
			bodyBytes, _ := io.ReadAll(res.Body)
			_ = res.Body.Close()
			if res.StatusCode < 200 || res.StatusCode >= 300 {
				_, _ = fmt.Fprintf(os.Stderr, "logger: ES responded with status=%d on attempt %d/%d body=%s\n", res.StatusCode, i+1, attempts, string(bodyBytes))
			}
		}
		break
	}

	return nil
}

// MustSetup exits on error.
func MustSetup(configPath string) {
	if err := Setup(configPath); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "logger setup failed: %v\n", err)
		os.Exit(1)
	}
}

// keep reference so linters don't complain
var _ = Log
