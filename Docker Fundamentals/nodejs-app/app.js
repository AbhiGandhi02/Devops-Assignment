const http = require('http');

const PORT_NUMBER = 3000;

const httpServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end("<h1>Hello World from Abhi's Node.js app!</h1>");
});

httpServer.listen(PORT_NUMBER, () => {
  console.log(`Node.js app listening on port ${PORT_NUMBER}`);
});
