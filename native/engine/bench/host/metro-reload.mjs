// Asks every app connected to Metro to reload, as `expo start`'s "r" key does: a broadcast on Metro's message socket.
const port = process.argv[2] || "20101";
const ws = new WebSocket(`ws://127.0.0.1:${port}/message`);
ws.onopen = () => { ws.send(JSON.stringify({ version: 2, method: "reload" })); setTimeout(() => { ws.close(); console.log("reload sent"); process.exit(0); }, 300); };
ws.onerror = (e) => { console.log("message socket error", e.message ?? ""); process.exit(1); };
