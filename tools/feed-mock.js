// Minimal stand-in for your real data source: serves the JSON shape the app's
// "自定义信息源" card expects, so the whole chain (device -> HTTP -> render) is
// testable before touching production endpoints.
//
//   node tools/feed-mock.mjs 8788
//   然后在板子的设置页填: http://<这台机器的局域网IP>:8788/feed
//
// Phase 2 (盯盘) keeps the same contract: any endpoint returning
//   { "title": string, "lines": string[] }
// renders without changing app code.
const http = require('http');

const port = Number(process.argv[2] || 8788);
const lines = () => [
  `模拟信号 A  BUY  ${Math.round(Math.random() * 100)} / 100`,
  `模拟信号 B  HOLD ${new Date().toISOString().slice(11, 19)}`,
  `链路自检 ok  host=${require('os').hostname()}`,
];

http.createServer((req, res) => {
  if (req.url.startsWith('/feed')) {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ title: '本地模拟信息源', lines: lines() }));
    console.log(`${new Date().toISOString()} GET ${req.url} <- ${req.socket.remoteAddress}`);
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('use /feed');
}).listen(port, '0.0.0.0', () => {
  console.log(`feed mock listening on 0.0.0.0:${port}  ->  http://<this-host>:${port}/feed`);
});
