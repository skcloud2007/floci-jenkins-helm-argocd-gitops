const express = require("express");
const client = require("prom-client");

const app = express();
const port = process.env.PORT || 3000;
const version = process.env.APP_VERSION || "local";

client.collectDefaultMetrics({
  prefix: "gitops_demo_app_"
});

const httpRequestDurationSeconds = new client.Histogram({
  name: "gitops_demo_app_http_request_duration_seconds",
  help: "HTTP request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5]
});

const httpRequestsTotal = new client.Counter({
  name: "gitops_demo_app_http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"]
});

app.use((req, res, next) => {
  const endTimer = httpRequestDurationSeconds.startTimer();

  res.on("finish", () => {
    const route = req.route && req.route.path ? req.route.path : req.path;

    const labels = {
      method: req.method,
      route,
      status_code: String(res.statusCode)
    };

    httpRequestsTotal.inc(labels);
    endTimer(labels);
  });

  next();
});

app.get("/", (_req, res) => {
  res.json({
    app: "gitops-demo-app",
    message: "Hello from production-style GitOps monitoring",
    version,
    status: "running"
  });
});

app.get("/healthz", (_req, res) => {
  res.status(200).json({ status: "ok" });
});

app.get("/readyz", (_req, res) => {
  res.status(200).json({ status: "ready" });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(port, () => {
  console.log(`gitops-demo-app listening on port ${port}`);
});
