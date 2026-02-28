const WebSocket = require("ws");

const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

const presentations = new Map();
const controllers = new Map();

console.log(`WebSocket relay server running on ws://localhost:${PORT}`);

function getQueryParams(url) {
  const queryStart = url.indexOf('?');
  if (queryStart === -1) return {};
  
  const query = url.substring(queryStart + 1);
  const params = {};
  
  query.split('&').forEach(param => {
    const [key, value] = param.split('=');
    params[key] = value;
  });
  
  return params;
}

wss.on("connection", (ws, req) => {
  const params = getQueryParams(req.url);
  const castCode = params.cast_code;
  const clientType = params.type === "controller" ? "controller" : "presentation";
  
  console.log(`New ${clientType} connected for cast code: ${castCode || 'none'}`);

  if (!castCode) {
    console.log("Closing connection: no cast_code provided");
    ws.close(1008, "Missing cast_code");
    return;
  }

  if (clientType === "presentation") {
    // Store presentation client by cast code
    presentations.set(castCode, ws);

    ws.on("message", (data) => {
      const message = JSON.parse(data);

      if (message.type === "state") {
        broadcastToControllers(castCode, message);
      }
    });

    ws.on("close", () => {
      console.log(`Presentation disconnected for cast code: ${castCode}`);
      presentations.delete(castCode);
    });
  } else {
    // Store controller client by cast code
    if (!controllers.has(castCode)) {
      controllers.set(castCode, []);
    }
    controllers.get(castCode).push(ws);

    ws.on("message", (data) => {
      const message = JSON.parse(data);

      if (message.type === "cmd") {
        const presentation = presentations.get(castCode);
        if (presentation && presentation.readyState === WebSocket.OPEN) {
          presentation.send(JSON.stringify(message));
        }
      }
    });

    ws.on("close", () => {
      const controllerList = controllers.get(castCode);
      if (controllerList) {
        controllers.set(castCode, controllerList.filter((client) => client !== ws));
      }
      console.log(`Controller disconnected for cast code: ${castCode}`);
    });
  }

  ws.on("error", (error) => {
    console.error(`WebSocket error for cast code ${castCode}: ${error.message}`);
  });
});

function broadcastToControllers(castCode, message) {
  const controllerList = controllers.get(castCode);
  if (controllerList) {
    controllerList.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify(message));
      }
    });
  }
}

process.on("SIGINT", () => {
  console.log("\nShutting down WebSocket server...");
  wss.close(() => {
    process.exit(0);
  });
});
