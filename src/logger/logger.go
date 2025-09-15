package logger

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
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
		Enabled  bool   `mapstructure:"enabled"`
		URL      string `mapstructure:"url"`
		Index    string `mapstructure:"index"`
		Username string `mapstructure:"username"`
		Password string `mapstructure:"password"`
		// advanced options (kept for compatibility but unused in option 1)
		QueueSize     int    `mapstructure:"queue_size"`
		BatchSize     int    `mapstructure:"batch_size"`
		FlushInterval string `mapstructure:"flush_interval"` // duration string
		Retries       int    `mapstructure:"retries"`
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

	if configPath == "" {
		v.SetConfigName("logger")
		v.AddConfigPath(".")
	} else {
		v.SetConfigFile(configPath)
	}
	v.SetEnvPrefix("LOGGER")
	v.AutomaticEnv()

	if err := v.ReadInConfig(); err != nil {
		// allow missing config file but warn
		_, _ = fmt.Fprintf(os.Stderr, "logger: no configuration file found: %v\n", err)
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

	// Elasticsearch hook (option 1): simple per-entry indexing
	if cfg.Elasticsearch.Enabled {
		esCfg := elasticsearch.Config{
			Addresses: []string{cfg.Elasticsearch.URL},
			Username:  cfg.Elasticsearch.Username,
			Password:  cfg.Elasticsearch.Password,
		}
		es, err := elasticsearch.NewClient(esCfg)
		if err != nil {
			return fmt.Errorf("failed to create elasticsearch client: %w", err)
		}
		hook := &ESHook{Client: es, Index: cfg.Elasticsearch.Index}
		log.AddHook(hook)
	}

	Log = log
	return nil
}

// ESHook is a simple Logrus hook that indexes each log entry into Elasticsearch.
type ESHook struct {
	Client *elasticsearch.Client
	Index  string
}

func (h *ESHook) Levels() []logrus.Level {
	return logrus.AllLevels
}

func (h *ESHook) Fire(entry *logrus.Entry) error {
	data := make(map[string]interface{})
	for k, v := range entry.Data {
		data[k] = v
	}
	data["message"] = entry.Message
	data["level"] = entry.Level.String()
	data["time"] = entry.Time.Format(time.RFC3339)

	b, err := json.Marshal(data)
	if err != nil {
		return err
	}

	index := h.Index
	if index == "" {
		index = "logs"
	}

	ctx := context.Background()
	res, err := h.Client.Index(
		index,
		bytes.NewReader(b),
		h.Client.Index.WithContext(ctx),
	)
	if err != nil {
		return err
	}
	_ = res.Body.Close()
	return nil
}

// MustSetup exits on error.
func MustSetup(configPath string) {
	if err := Setup(configPath); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "logger setup failed: %v\n", err)
		os.Exit(1)
	}
}

// reference exported symbol to satisfy some static analyzers when package is not
// otherwise used in the current workspace
var _ = Log
