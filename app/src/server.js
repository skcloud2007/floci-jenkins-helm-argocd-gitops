const express = require("express");

const app = express();
const port = process.env.PORT || 3000;
const version = process.env.APP_VERSION || "local";

app.get("/", (_req, res) => {
  res.json({
    app: "gitops-demo-app",
    message: "Hello from automated Jenkins GitOps deployment",
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

app.listen(port, () => {
  console.log(`gitops-demo-app listening on port ${port}`);
});
