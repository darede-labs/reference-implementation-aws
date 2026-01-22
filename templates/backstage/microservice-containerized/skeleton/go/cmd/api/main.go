package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: []float64{0.1, 0.5, 1, 2, 5},
		},
		[]string{"method", "endpoint"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

// StructuredLogger middleware for JSON logging
func StructuredLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		startTime := time.Now()

		c.Next()

		duration := time.Since(startTime).Milliseconds()

		logEntry := map[string]interface{}{
			"level":      "info",
			"msg":        "Request completed",
			"timestamp":  time.Now().UTC().Format(time.RFC3339),
			"service":    getEnv("APP_NAME", "microservice"),
			"hostname":   getHostname(),
			"method":     c.Request.Method,
			"path":       c.Request.URL.Path,
			"status":     c.Writer.Status(),
			"duration_ms": duration,
			"user_agent": c.Request.UserAgent(),
		}

		logJSON, _ := json.Marshal(logEntry)
		fmt.Println(string(logJSON))
	}
}

// PrometheusMiddleware for metrics collection
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		startTime := time.Now()

		c.Next()

		duration := time.Since(startTime).Seconds()

		httpRequestsTotal.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
			fmt.Sprintf("%d", c.Writer.Status()),
		).Inc()

		httpRequestDuration.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
		).Observe(duration)
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getHostname() string {
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	return hostname
}

func main() {
	// Set Gin mode
	gin.SetMode(gin.ReleaseMode)

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(StructuredLogger())
	r.Use(PrometheusMiddleware())

	// Health endpoints
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":    "healthy",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	r.GET("/ready", func(c *gin.Context) {
		// Add readiness checks here (database, cache, etc)
		c.JSON(200, gin.H{
			"status":    "ready",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	})

	// Root endpoint
	r.GET("/", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"service":     getEnv("APP_NAME", "microservice"),
			"description": getEnv("APP_DESCRIPTION", "Go microservice"),
			"version":     "1.0.0",
			"timestamp":   time.Now().UTC().Format(time.RFC3339),
			"hostname":    getHostname(),
		})
	})

	// Prometheus metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	port := getEnv("PORT", "8080")
	log.Printf("Starting server on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}
