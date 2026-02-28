import gleam/int

pub type Config {
  Config(
    server_host: String,
    server_port: Int,
    websocket_url: String,
    websocket_port: Int,
    slides_dir: String,
    view_dir: String,
    qr_dir: String,
  )
}

pub fn get_config() -> Config {
  // WebSocket URL should be passed via environment variable
  // Example: export WEBSOCKET_URL="ws://matwa.is-cool.dev/ws/"
  // Default: ws://localhost:8080
  // Set this in your .bashrc or before running the application

  let ws_url = "ws://localhost:8080"

  Config(
    server_host: "0.0.0.0",
    server_port: 6767,
    websocket_url: ws_url,
    websocket_port: 8080,
    slides_dir: "./slides",
    view_dir: "./view",
    qr_dir: "./qr",
  )
}

pub fn with_websocket_url(config: Config, url: String) -> Config {
  Config(..config, websocket_url: url)
}
