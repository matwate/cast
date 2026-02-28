import config
import gleam/list
import gleam/result
import gleam/string
import gleamyshell
import simplifile
import store
import types
import wisp

const slides_output_dir: String = "./slides"

const view_output_dir: String = "./view/"

const qr_output_dir: String = "./qr"

pub const server_ip: String = "https://matwa.is-cool.dev"

pub const websocket_url: String = "ws://matwa.is-cool.dev/ws/" 

type ThisThingError {
  NoUsername
  NoFile
  UnsupportedFileFormat
  FailedGenerating(why: List(#(String, String)))
}

pub fn handle_convert(req: wisp.Request, ctx: types.Context) -> wisp.Response {
  use formdata <- wisp.require_form(req)
  let result: Result(#(String, String, String), ThisThingError) = {
    use username <- result.try(
      list.key_find(formdata.values, "username")
      |> result.map_error(fn(_) { NoUsername }),
    )
    use file <- result.try(
      list.key_find(formdata.files, "data")
      |> result.map_error(fn(_) { NoFile }),
    )

    let filename = file.file_name
    let path = file.path

    let cast_code = wisp.random_string(6)
    store.set(ctx.store, username, filename, cast_code)

    use _ <- result.try(case determine_filetype(filename) {
      Pdf -> convert_pdf(filename, path, username, cast_code)
      Pptx -> convert_pptx(filename, path, username, cast_code)
      Unsupported -> Error(UnsupportedFileFormat)
    })

    use _ <- result.try(
      generate_qr_code(cast_code)
      |> result.map_error(FailedGenerating),
    )

    Ok(#(username, filename, cast_code))
  }

  case result {
    Ok(#(_username, _filename, cast_code)) -> {
      let view_url = "/view/" <> cast_code
      wisp.redirect(view_url)
    }
    Error(e) ->
      case e {
        NoUsername -> wisp.html_response("No username", 400)
        NoFile -> wisp.html_response("No File", 400)
        UnsupportedFileFormat ->
          wisp.html_response("Could not determine file format", 442)
        FailedGenerating(why) ->
          wisp.html_response(
            "Unprocessable file format: " <> string.inspect(why),
            422,
          )
      }
  }
}

fn generate_qr_code(cast_code: String) -> Result(Nil, List(#(String, String))) {
  let qr_url = server_ip <> "/controls/" <> cast_code
  let qr_path = qr_output_dir <> "/" <> cast_code <> ".png"

  case
    gleamyshell.execute("qrrs", in: ".", args: [
      qr_url,
      qr_path,
    ])
  {
    Ok(gleamyshell.CommandOutput(0, _)) -> Ok(Nil)
    Ok(gleamyshell.CommandOutput(_, reason)) ->
      Error([#("QR code generation failed: " <> reason, "qrrs")])
    Error(_) -> Error([#("Failed to execute qrrs", "qrrs")])
  }
}

fn convert_pdf(
  filename: String,
  path: String,
  username: String,
  cast_code: String,
) -> Result(Nil, ThisThingError) {
  case convert_pdf_to_pngs(path, slides_output_dir, username, filename) {
    Ok(_) -> {
      case
        compress_pngs(slides_output_dir <> "/" <> username <> "/" <> filename)
      {
        Ok(_) -> {
          case
            generate_html_from_pngs(
              slides_output_dir <> "/" <> username <> "/" <> filename,
              username,
              filename,
              cast_code,
            )
          {
            Ok(html) -> {
              case
                simplifile.create_directory_all(view_output_dir <> username)
              {
                Ok(_) -> {
                  case
                    simplifile.write(
                      view_output_dir
                        <> username
                        <> "/"
                        <> string.replace(filename, ".pdf", ".html"),
                      html,
                    )
                  {
                    Ok(_) -> Ok(Nil)
                    Error(_) ->
                      Error(
                        FailedGenerating([
                          #("Failed to write HTML file", "simplifile"),
                        ]),
                      )
                  }
                }
                Error(_) ->
                  Error(
                    FailedGenerating([
                      #("Failed to create view directory", "simplifile"),
                    ]),
                  )
              }
            }
            Error(why) -> Error(FailedGenerating(why))
          }
        }
        Error(why) -> Error(FailedGenerating(why))
      }
    }
    Error(why) -> Error(FailedGenerating(why))
  }
}

fn convert_pptx(
  filename: String,
  path: String,
  username: String,
  cast_code: String,
) -> Result(Nil, ThisThingError) {
  case convert_pptx_to_pngs(path, slides_output_dir, username, filename) {
    Ok(_) -> {
      case
        compress_pngs(slides_output_dir <> "/" <> username <> "/" <> filename)
      {
        Ok(_) -> {
          case
            generate_html_from_pngs(
              slides_output_dir <> "/" <> username <> "/" <> filename,
              username,
              filename,
              cast_code,
            )
          {
            Ok(html) -> {
              case
                simplifile.create_directory_all(view_output_dir <> username)
              {
                Ok(_) -> {
                  case
                    simplifile.write(
                      view_output_dir
                        <> username
                        <> "/"
                        <> string.replace(filename, ".pptx", ".html"),
                      html,
                    )
                  {
                    Ok(_) -> Ok(Nil)
                    Error(_) ->
                      Error(
                        FailedGenerating([
                          #("Failed to write HTML file", "simplifile"),
                        ]),
                      )
                  }
                }
                Error(_) ->
                  Error(
                    FailedGenerating([
                      #("Failed to create view directory", "simplifile"),
                    ]),
                  )
              }
            }
            Error(why) -> Error(FailedGenerating(why))
          }
        }
        Error(why) -> Error(FailedGenerating(why))
      }
    }
    Error(why) -> Error(FailedGenerating(why))
  }
}

fn convert_pptx_to_pngs(
  pptx_path: String,
  output_dir: String,
  username: String,
  filename: String,
) -> Result(Nil, List(#(String, String))) {
  let base_name = filename
  let output_path = output_dir <> "/" <> username <> "/" <> base_name

  case simplifile.create_directory_all(output_path) {
    Ok(Nil) -> {
      case
        gleamyshell.execute("libreoffice", in: ".", args: [
          "--headless",
          "--convert-to",
          "png",
          "--outdir",
          output_path,
          pptx_path,
        ])
      {
        Ok(gleamyshell.CommandOutput(0, _)) -> Ok(Nil)
        Ok(gleamyshell.CommandOutput(_, reason)) ->
          Error([#("PPTX to PNG conversion failed: " <> reason, "libreoffice")])
        Error(_) -> Error([#("Failed to execute libreoffice", "libreoffice")])
      }
    }
    Error(_) -> Error([#("Failed to create output directory", "simplifile")])
  }
}

fn generate_html_from_pngs(
  dir: String,
  username: String,
  filename: String,
  cast_code: String,
) -> Result(String, List(#(String, String))) {
  let assert Ok(files) = simplifile.read_directory(dir)

  let png_files =
    files
    |> list.filter(fn(f) { string.ends_with(f, ".png") })
    |> list.sort(fn(a, b) { string.compare(a, b) })

  let slides_html =
    png_files
    |> list.map(fn(file) {
      "<section><img src='/slides/"
      <> username
      <> "/"
      <> filename
      <> "/"
      <> file
      <> "'></section>"
    })
    |> string.join("\n")
  // Generate HTML with correct plugin paths that will be served by our server
  let html = "<!doctype html>
<html>
  <head>
    <meta charset='utf-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>Presentation</title>

    <link rel='stylesheet' href='/assets/vendor/reveal.css'>
    <link rel='stylesheet' href='/assets/vendor/theme/black.css' id='theme'>
    <style>
      .reveal section img {
        max-width: 100%;
        max-height: 100vh;
        margin: 0;
        object-fit: contain;
      }
      .connection-status {
        position: fixed;
        top: 16px;
        right: 16px;
        z-index: 9999;
        background: rgba(0, 0, 0, 0.8);
        color: white;
        padding: 8px 16px;
        border-radius: 8px;
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 12px;
        font-weight: 500;
        transition: all 0.3s ease;
        backdrop-filter: blur(8px);
      }
      .connection-status.connected {
        background: rgba(34, 197, 94, 0.9);
      }
      .connection-status.disconnected {
        background: rgba(239, 68, 68, 0.9);
      }
      .connection-status.connecting {
        background: rgba(234, 179, 8, 0.9);
      }
      .connection-status .status-icon {
        font-size: 16px;
      }
      .connection-status.connecting .status-icon {
        animation: pulse 1.5s ease-in-out infinite;
      }
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }
      .connection-status.hidden {
        opacity: 0;
        pointer-events: none;
      }
    </style>
  </head>
  <body>
    <div id='connectionStatus' class='connection-status connecting'>
      <span class='status-icon'>●</span>
      <span class='status-text'>Connecting to remote...</span>
    </div>
    <div class='reveal'>
      <div class='slides'>" <> slides_html <> "</div>
    </div>
    <script src='/assets/vendor/reveal.js'></script>
    <script>
      Reveal.initialize({
        hash: true,
        transition: 'none',
        transitionSpeed: 'default',
        disableLayout: true,
      });
    </script>
    <script>
      (function() {
        const WS_URL = '" <> websocket_url <> "/?cast_code=" <> cast_code <> "&type=presentation';
        let socket = null;
        let reconnectTimeout = null;

        function updateConnectionStatus(status) {
          const statusEl = document.getElementById('connectionStatus');
          const statusText = statusEl.querySelector('.status-text');
          
          statusEl.className = 'connection-status ' + status;
          
          switch(status) {
            case 'connecting':
              statusText.textContent = 'Connecting to remote...';
              break;
            case 'connected':
              statusText.textContent = 'Remote control active';
              break;
            case 'disconnected':
              statusText.textContent = 'Remote control disconnected - reconnecting...';
              break;
          }
        }

        function connect() {
          if (reconnectTimeout) {
            clearTimeout(reconnectTimeout);
          }
          
          updateConnectionStatus('connecting');
          socket = new WebSocket(WS_URL);

          socket.onopen = () => {
            console.log('Connected to control server');
            updateConnectionStatus('connected');
            broadcastState();
          };

          socket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.type === 'cmd') {
              if (data.action === 'next') Reveal.next();
              if (data.action === 'prev') Reveal.prev();
            }
          };

          socket.onclose = () => {
            console.log('Disconnected from control server, reconnecting in 3s...');
            updateConnectionStatus('disconnected');
            reconnectTimeout = setTimeout(connect, 3000);
          };

          socket.onerror = (error) => {
            console.error('WebSocket error:', error);
            updateConnectionStatus('disconnected');
          };
        }

        function broadcastState() {
          if (socket && socket.readyState === WebSocket.OPEN) {
            const indices = Reveal.getIndices();
            const total = Reveal.getTotalSlides();
            socket.send(JSON.stringify({
              type: 'state',
              indexh: indices.h,
              indexv: indices.v,
              total: total
            }));
          }
        }

        Reveal.on('slidechanged', broadcastState);
        Reveal.on('fragmentshown', broadcastState);
        Reveal.on('fragmenthidden', broadcastState);
        
        // Start connection after Reveal is ready
        setTimeout(connect, 1000);
      })();
    </script>
  </body>
</html>"
  Ok(html)
}

// Takes the presentation path, and puts the images in ./slides/username/filename/
fn convert_pdf_to_pngs(
  pdf_path: String,
  output_dir: String,
  username: String,
  filename: String,
) -> Result(Nil, List(#(String, String))) {
  let base_name = filename

  // Construct the output path: output_dir/username/filename
  let output_path = output_dir <> "/" <> username <> "/" <> base_name

  case simplifile.create_directory_all(output_path) {
    Ok(Nil) -> {
      case
        gleamyshell.execute("pdftoppm", in: ".", args: [
          pdf_path,
          output_path <> "/" <> base_name,
          "-png",
        ])
      {
        Ok(gleamyshell.CommandOutput(0, _)) -> Ok(Nil)
        Ok(gleamyshell.CommandOutput(_, reason)) ->
          Error([#("PDF to PNG conversion failed: " <> reason, "pdftoppm")])
        Error(_) -> Error([#("Failed to execute pdftoppm", "pdftoppm")])
      }
    }
    Error(_) -> Error([#("Failed to create output directory: ", "simplifile")])
  }
}

fn compress_pngs(dir: String) -> Result(Nil, List(#(String, String))) {
  let files = simplifile.read_directory(dir)
  case files {
    Ok(files) -> {
      let png_files =
        files
        |> list.filter(fn(f) { string.ends_with(f, ".png") })
        |> list.map(fn(f) { dir <> "/" <> f })

      let results =
        png_files
        |> list.map(fn(file) {
          gleamyshell.execute("pngquant", in: ".", args: [
            file,
            "-s",
            "1",
            "-f",
            "-o",
            file,
          ])
        })
      case
        results
        |> list.all(fn(r) {
          case r {
            Ok(gleamyshell.CommandOutput(0, _)) -> True
            _ -> False
          }
        })
      {
        True -> Ok(Nil)
        False -> Error([#("PNG compression failed for some files", "pngquant")])
      }
    }
    Error(_) -> Error([#("PNG compression failed for some files", "pngquant")])
  }
}

type Filetype {
  Pdf
  Pptx
  Unsupported
}

fn determine_filetype(filename) -> Filetype {
  case string.ends_with(filename, ".pdf"), string.ends_with(filename, ".pptx") {
    True, _ -> Pdf
    _, True -> Pptx
    _, _ -> Unsupported
  }
}
