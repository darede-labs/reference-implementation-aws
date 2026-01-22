const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

// Structured JSON logging
const log = (level, msg, meta = {}) => {
  console.log(JSON.stringify({
    level,
    msg,
    timestamp: new Date().toISOString(),
    hostname: os.hostname(),
    service: process.env.APP_NAME || 'microservice',
    ...meta
  }));
};

// Middleware: Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration_ms = Date.now() - start;
    log('info', 'Request completed', {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms,
      user_agent: req.get('user-agent')
    });
  });
  next();
});

// Health endpoints
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/ready', (req, res) => {
  // Add readiness checks here (database, cache, etc)
  res.json({ status: 'ready', timestamp: new Date().toISOString() });
});

// Prometheus metrics endpoint
const client = require('prom-client');
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5]
});
register.registerMetric(httpRequestDuration);

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Application routes
app.get('/', (req, res) => {
  log('info', 'Root endpoint accessed');
  res.json({
    service: process.env.APP_NAME || 'microservice',
    description: process.env.APP_DESCRIPTION || 'Node.js microservice',
    version: process.env.APP_VERSION || '1.0.0',
    timestamp: new Date().toISOString(),
    hostname: os.hostname()
  });
});

// Error handling
app.use((err, req, res, next) => {
  log('error', 'Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path
  });
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
  log('info', 'Server started', { port: PORT });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log('info', 'SIGTERM received, shutting down gracefully');
  process.exit(0);
});
