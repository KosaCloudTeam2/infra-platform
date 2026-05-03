const http = require("http");

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(
    JSON.stringify({
      service: "cloud-infra-sample-app",
      message: "deployment succeeded",
      timestamp: new Date().toISOString()
    })
  );
});

server.listen(port, () => {
  console.log(`sample app listening on ${port}`);
});
