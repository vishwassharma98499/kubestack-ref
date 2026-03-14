package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	version   = "0.1.0"
	buildTime = "unknown"
	ready     int32
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests"},
		[]string{"method", "path", "status_code"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Request duration", Buckets: prometheus.DefBuckets},
		[]string{"method", "path"},
	)
	appInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{Name: "app_info", Help: "Build info"},
		[]string{"version", "go_version", "environment"},
	)
)

func init() { prometheus.MustRegister(httpRequestsTotal, httpRequestDuration, appInfo) }

type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.statusCode = code
	r.ResponseWriter.WriteHeader(code)
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func instrument(path string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, statusCode: 200}
		h(rec, r)
		httpRequestsTotal.WithLabelValues(r.Method, path, fmt.Sprintf("%d", rec.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
	}
}

func main() {
	appEnv := env("APP_ENV", "development")
	logLevel := env("LOG_LEVEL", "info")
	serverPort := env("SERVER_PORT", "8080")
	metricsPort := env("METRICS_PORT", "9090")

	var level slog.Level
	switch logLevel {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})))
	appInfo.WithLabelValues(version, runtime.Version(), appEnv).Set(1)

	api := http.NewServeMux()
	api.HandleFunc("/", instrument("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"service": "kubestack-ref-api", "version": version, "environment": appEnv,
			"go_version": runtime.Version(), "timestamp": time.Now().UTC().Format(time.RFC3339), "status": "operational",
		})
	}))
	api.HandleFunc("/healthz", instrument("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	}))
	api.HandleFunc("/readyz", instrument("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&ready) == 1 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
		} else {
			w.WriteHeader(503)
			json.NewEncoder(w).Encode(map[string]string{"status": "not ready"})
		}
	}))
	api.HandleFunc("/info", instrument("/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"version": version, "build_time": buildTime, "go_version": runtime.Version(),
			"environment": appEnv, "db_host": env("DB_HOST", "not configured"),
			"log_level": logLevel, "goroutines": runtime.NumGoroutine(),
		})
	}))

	apiSrv := &http.Server{Addr: ":" + serverPort, Handler: api, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second}
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsSrv := &http.Server{Addr: ":" + metricsPort, Handler: metricsMux}

	go func() {
		slog.Info("metrics server starting", "port", metricsPort)
		if err := metricsSrv.ListenAndServe(); err != http.ErrServerClosed {
			slog.Error("metrics server failed", "error", err)
		}
	}()
	go func() {
		slog.Info("api server starting", "port", serverPort, "env", appEnv, "version", version)
		if err := apiSrv.ListenAndServe(); err != http.ErrServerClosed {
			slog.Error("api server failed", "error", err)
		}
	}()

	atomic.StoreInt32(&ready, 1)
	slog.Info("application ready", "version", version, "environment", appEnv)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	slog.Info("shutting down")
	atomic.StoreInt32(&ready, 0)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	apiSrv.Shutdown(ctx)
	metricsSrv.Shutdown(ctx)
	slog.Info("shutdown complete")
}
