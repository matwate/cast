// Connects a Reveal.js deck to the cast relay so a phone can drive it.
// Usage: <script src="/assets/cast-remote.js" data-cast-code="CODE"></script>
// placed after Reveal is loaded.
(function () {
  const castCode = document.currentScript.dataset.castCode;
  const protocol = window.location.protocol === "https:" ? "wss://" : "ws://";
  const WS_URL =
    protocol +
    "cast.matwa.dev/ws/?cast_code=" +
    encodeURIComponent(castCode) +
    "&type=presentation";

  const style = document.createElement("style");
  style.textContent = `
    .cast-status {
      position: fixed; top: 16px; right: 16px; z-index: 9999;
      display: flex; align-items: center; gap: 8px;
      padding: 8px 16px; border-radius: 0;
      background: #1b3331; color: #f2efe6;
      font: 12px/16px "Space Mono", ui-monospace, "Courier New", monospace;
      letter-spacing: 0.08em;
      transition: opacity 0.3s ease;
    }
    .cast-status__dot {
      width: 8px; height: 8px; border-radius: 999px;
      border: 1px solid #f2efe6;
    }
    .cast-status.connected .cast-status__dot { background: #09aea1; border-color: #09aea1; }
    .cast-status.disconnected .cast-status__dot { background: #f5505d; border-color: #f5505d; }
    .cast-status.connecting .cast-status__dot { animation: cast-blink 1s steps(2, start) infinite; }
    .cast-status.hidden { opacity: 0; pointer-events: none; }
    @keyframes cast-blink { to { visibility: hidden; } }
  `;
  document.head.appendChild(style);

  const statusEl = document.createElement("div");
  statusEl.innerHTML =
    '<span class="cast-status__dot"></span><span class="cast-status__text"></span>';
  document.body.appendChild(statusEl);

  const labels = {
    connecting: "Connecting to remote",
    connected: "Remote active",
    disconnected: "Remote lost, retrying",
  };

  let socket = null;
  let hideTimeout = null;

  function updateConnectionStatus(status) {
    clearTimeout(hideTimeout);
    statusEl.className = "cast-status " + status;
    statusEl.querySelector(".cast-status__text").textContent = labels[status];
    // Get out of the way once the remote is working.
    if (status === "connected") {
      hideTimeout = setTimeout(() => statusEl.classList.add("hidden"), 3000);
    }
  }

  function broadcastState() {
    if (socket && socket.readyState === WebSocket.OPEN) {
      const indices = Reveal.getIndices();
      socket.send(
        JSON.stringify({
          type: "state",
          indexh: indices.h,
          indexv: indices.v,
          total: Reveal.getTotalSlides(),
        }),
      );
    }
  }

  function connect() {
    updateConnectionStatus("connecting");
    socket = new WebSocket(WS_URL);

    socket.onopen = () => {
      updateConnectionStatus("connected");
      broadcastState();
    };

    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === "cmd") {
        if (data.action === "next") Reveal.next();
        if (data.action === "prev") Reveal.prev();
      }
    };

    socket.onclose = () => {
      updateConnectionStatus("disconnected");
      setTimeout(connect, 3000);
    };

    socket.onerror = (error) => {
      console.error("cast: WebSocket error", error);
    };
  }

  function start() {
    Reveal.on("slidechanged", broadcastState);
    Reveal.on("fragmentshown", broadcastState);
    Reveal.on("fragmenthidden", broadcastState);
    connect();
  }

  if (Reveal.isReady()) {
    start();
  } else {
    Reveal.on("ready", start);
  }
})();
