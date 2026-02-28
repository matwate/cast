import config
import document
import gleam/bytes_tree
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import mist
import simplifile
import store
import types
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let store = store.start()

  let secret_key_base = wisp.random_string(64)

  let ctx = types.Context(store:)
  let handler = fn(req) { routes(req, ctx) }

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(6767)
    |> mist.start

  process.sleep_forever()
}

fn routes(req: Request, ctx: types.Context) -> Response {
  use req <- web_middleware(req)

  case wisp.path_segments(req) {
    ["convert"] -> document.handle_convert(req, ctx)
    [] -> serve_index()

    ["view", username, filename] -> serve_view_page(username, filename)
    ["view", code] -> serve_view_connection_page(code, ctx)
    ["cast", code] -> handle_cast_code(code, ctx)
    ["code", code] -> handle_cast_code(code, ctx)
    ["controls", code] -> serve_controls_page(code, ctx)
    ["qr", route_code] -> serve_qr_code(route_code)
    ["slides", ..rest] -> serve_static_file("./slides/", rest)
    ["assets", ..rest] -> serve_asset(rest)
    _ -> wisp.not_found()
  }
}

fn handle_cast_code(code: String, ctx: types.Context) -> Response {
  case store.get(ctx.store, code) {
    Some(#(username, filename)) -> {
      let redirect_url = "/view/" <> username <> "/" <> filename
      wisp.redirect(redirect_url)
    }
    None -> wisp.html_response("Invalid or expired cast code", 404)
  }
}

fn serve_view_page(username: String, filename: String) -> Response {
  use <- wisp.rescue_crashes

  let safe_username = string.replace(username, "..", "")
  let safe_filename = string.replace(filename, "..", "")
  let html_path = "./view/" <> safe_username <> "/" <> safe_filename
  case simplifile.read(html_path) {
    Ok(content) -> wisp.html_response(content, 200)
    Error(_) -> wisp.html_response("Presentation not found", 404)
  }
}

fn serve_view_connection_page(code: String, ctx: types.Context) -> Response {
  case store.get(ctx.store, code) {
    Some(#(username, filename)) -> {
      use <- wisp.rescue_crashes

      // Get HTML extension based on original filename
      let html_filename = case string.ends_with(filename, ".pdf") {
        True -> string.replace(filename, ".pdf", ".html")
        False -> string.replace(filename, ".pptx", ".html")
      }

      // Construct URLs
      let qr_url = "/qr/" <> code
      let presentation_url = "/view/" <> username <> "/" <> html_filename
      let controls_url = "/controls/" <> code

      case simplifile.read("./public/view.html") {
        Ok(content) -> {
          let html =
            content
            |> string.replace("{{CAST_CODE}}", code)
            |> string.replace("{{QR_URL}}", qr_url)
            |> string.replace("{{PRESENTATION_URL}}", presentation_url)
            |> string.replace("{{CONTROLS_URL}}", controls_url)
            |> string.replace("{{USERNAME}}", username)
          wisp.html_response(html, 200)
        }
        Error(_) -> wisp.html_response("Connection page not found", 500)
      }
    }
    None -> wisp.redirect("/")
    // Invalid/expired code → redirect to index
  }
}

fn serve_controls_page(code: String, ctx: types.Context) -> Response {
  case store.get(ctx.store, code) {
    Some(#(username, filename)) -> {
      use <- wisp.rescue_crashes
      case simplifile.read("./public/controls.html") {
        Ok(content) -> {
          let content_with_code =
            string.replace(content, "{{CAST_CODE}}", code)
            |> string.replace("{{USERNAME}}", username)
          wisp.html_response(content_with_code, 200)
        }
        Error(_) -> wisp.html_response("Controls page not found", 404)
      }
    }
    None -> wisp.html_response("Invalid or expired cast code", 404)
  }
}

fn serve_qr_code(code: String) -> Response {
  use <- wisp.rescue_crashes

  let qr_path = "./qr/" <> code <> ".png"
  case simplifile.read_bits(qr_path) {
    Ok(content) ->
      wisp.response(200)
      |> wisp.set_header("content-type", "image/png")
      |> wisp.set_body(wisp.Bytes(bytes_tree.from_bit_array(content)))
    Error(_) -> wisp.html_response("QR code not found", 404)
  }
}

fn serve_static_file(base_path: String, segments: List(String)) -> Response {
  use <- wisp.rescue_crashes

  let safe_segments = list.map(segments, fn(s) { string.replace(s, "..", "") })
  let file_path = base_path <> string.join(safe_segments, "/")
  case simplifile.read_bits(file_path) {
    Ok(content) -> {
      let content_type = case string.ends_with(file_path, ".png") {
        True -> "image/png"
        False -> "image/jpeg"
      }

      wisp.response(200)
      |> wisp.set_header("content-type", content_type)
      |> wisp.set_body(wisp.Bytes(bytes_tree.from_bit_array(content)))
    }
    Error(_) -> wisp.html_response("File not found", 404)
  }
}

fn serve_asset(segments: List(String)) -> Response {
  use <- wisp.rescue_crashes

  let safe_segments = list.map(segments, fn(s) { string.replace(s, "..", "") })
  let file_path = "./public/assets/" <> string.join(safe_segments, "/")

  case simplifile.read_bits(file_path) {
    Ok(content) -> {
      let content_type = case string.ends_with(file_path, ".css") {
        True -> "text/css"
        False ->
          case string.ends_with(file_path, ".js") {
            True -> "application/javascript"
            False ->
              case string.ends_with(file_path, ".png") {
                True -> "image/png"
                False ->
                  case string.ends_with(file_path, ".jpg") {
                    True -> "image/jpeg"
                    False ->
                      case string.ends_with(file_path, ".woff") {
                        True -> "font/woff"
                        False -> "application/octet-stream"
                      }
                  }
              }
          }
      }

      wisp.response(200)
      |> wisp.set_header("content-type", content_type)
      |> wisp.set_body(wisp.Bytes(bytes_tree.from_bit_array(content)))
    }
    Error(_) -> wisp.html_response("Asset not found", 404)
  }
}

fn serve_index() -> Response {
  use <- wisp.rescue_crashes

  case simplifile.read("./public/index.html") {
    Ok(content) -> wisp.html_response(content, 200)
    Error(_) -> wisp.html_response("Error loading page", 500)
  }
}

pub fn web_middleware(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use req <- wisp.csrf_known_header_protection(req)

  handle_request(req)
}
