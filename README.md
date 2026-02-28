# REALLY IMPORTANT NOTE 

Ai wrote this readme, i apologize, i did read and removed the wrong and cringey things but still, this is written by ai


# Cast - Remote Presentation Control System


A self-hosted application that allows you to upload presentations (PDF/PPTX), convert them to web slides, and control them remotely from any device.


## Features

- 📤 Upload PDF or PPTX presentations
- 🔄 Automatic conversion to web slides
- 🎛️ Remote control via mobile device
- 📱 QR code for quick connection
- 🔌 Real-time WebSocket communication
- 📊 Slide state synchronization

## Quick Start with Nix

```bash
# Clone and enter the environment
git clone <repository-url>
cd cast
nix run .

# With custom WebSocket URL
WEBSOCKET_URL='ws://your-domain/ws/' nix run .
```

## Manual Setup

### Prerequisites

- Gleam (>= 1.3.0)
- Node.js (>= 18)
- poppler-utils (pdftoppm)
- LibreOffice (headless)
- pngquant
- qrrs
### Installation

```bash
# Install dependencies
npm install

# Build static assets
./setup.sh

# Build Gleam application
gleam build
```

### Running

```bash
# Start WebSocket relay (port 8080)
node websocket_relay.js &

# Start Gleam server (port 6767)
gleam run
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|----------|
| `WEBSOCKET_URL` | WebSocket server URL | `ws://localhost:8080` |
| `SERVER_HOST` | Server bind address | `0.0.0.0` |
| `SERVER_PORT` | Server port | `6767` |
| `SLIDES_DIR` | Slides output directory | `./slides` |
| `VIEW_DIR` | Presentation HTML directory | `./view` |
| `QR_DIR` | QR code directory | `./qr` |

### Example: Custom WebSocket URL

```bash
export WEBSOCKET_URL='ws://matwa.is-cool.dev/ws/'
gleam run
```

## Directory Structure

```
cast/
├── src/              # Gleam source code
├── public/            # Static assets
│   └── assets/
│       ├── css/      # Stylesheets
│       ├── js/       # JavaScript files
│       ├── fonts/    # Font files
│       └── vendor/   # Third-party libraries
├── slides/           # Generated slide images
├── view/             # Generated presentation HTML
├── qr/               # Generated QR codes
├── websocket_relay.js # WebSocket relay server
├── setup.sh          # Asset setup script
├── flake.nix         # Nix package definition
└── gleam.toml        # Gleam project config
```

## Architecture

### Components

1. **Gleam Server** (`src/cast.gleam`)
   - HTTP server on port 6767
   - Handles file uploads and conversions
   - Serves static files
   - Manages cast codes via OTP actor

2. **WebSocket Relay** (`websocket_relay.js`)
   - WebSocket server on port 8080
   - Routes messages between presentations and controllers
   - Supports multiple concurrent presentations

3. **Document Processor** (`src/document.gleam`)
   - Converts PDF to PNG using pdftoppm
   - Converts PPTX to PNG using LibreOffice
   - Optimizes PNGs using pngquant
   - Generates presentation HTML with Reveal.js
   - Creates QR codes using qrrs

 Controllers: `ws://host:8080/?cast_code={code}&type=controller`
``

