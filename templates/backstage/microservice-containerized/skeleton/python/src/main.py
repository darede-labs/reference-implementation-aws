from fastapi import FastAPI, Response
from prometheus_client import make_asgi_app, Counter, Histogram
import logging
import json
import os
import time
from datetime import datetime

# Structured JSON logging
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "level": record.levelname,
            "msg": record.getMessage(),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "service": os.getenv("APP_NAME", "microservice"),
            "hostname": os.uname().nodename,
        }
        if hasattr(record, "extra"):
            log_obj.update(record.extra)
        return json.dumps(log_obj)

# Configure logging
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.addHandler(handler)

# FastAPI app
app = FastAPI(
    title=os.getenv("APP_NAME", "microservice"),
    description=os.getenv("APP_DESCRIPTION", "Python microservice"),
    version="1.0.0"
)

# Prometheus metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint'],
    buckets=[0.1, 0.5, 1, 2, 5]
)

# Middleware for logging and metrics
@app.middleware("http")
async def log_requests(request, call_next):
    start_time = time.time()

    response = await call_next(request)

    duration = time.time() - start_time

    # Log request
    logger.info("Request completed", extra={
        "method": request.method,
        "path": request.url.path,
        "status": response.status_code,
        "duration_ms": round(duration * 1000, 2),
        "user_agent": request.headers.get("user-agent", "")
    })

    # Update metrics
    http_requests_total.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()

    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    return response

# Health endpoints
@app.get("/health")
def health():
    """Health check endpoint for liveness probe"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat() + "Z"}

@app.get("/ready")
def ready():
    """Readiness check endpoint for readiness probe"""
    # Add readiness checks here (database, cache, etc)
    return {"status": "ready", "timestamp": datetime.utcnow().isoformat() + "Z"}

# Application routes
@app.get("/")
def root():
    """Root endpoint with service information"""
    logger.info("Root endpoint accessed")
    return {
        "service": os.getenv("APP_NAME", "microservice"),
        "description": os.getenv("APP_DESCRIPTION", "Python microservice"),
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "hostname": os.uname().nodename
    }

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# Error handling
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled error: {str(exc)}", extra={
        "error": str(exc),
        "path": request.url.path
    })
    return Response(
        content=json.dumps({"error": "Internal server error"}),
        status_code=500,
        media_type="application/json"
    )
