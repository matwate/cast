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

pub const server_ip: String = "https://cast.matwa.dev"

pub const websocket_url: String = "ws://cast.matwa.dev/ws/"

type ThisThingError {
  NoUsername
  NoFile
  UnsupportedFileFormat
  InvalidCastCode
  FailedGenerating(why: List(#(String, String)))
}

pub fn handle_convert(req: wisp.Request, ctx: types.Context) -> wisp.Response {
  // Single-file HTML decks (videos inlined) get big.
  let req = wisp.set_max_files_size(req, 512_000_000)
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

    // An explicit cast code lets a deck keep the same code across uploads.
    use cast_code <- result.try(
      case list.key_find(formdata.values, "cast_code") {
        Ok(code) -> string.trim(code)
        Error(_) -> ""
      }
      |> choose_cast_code,
    )

    use _ <- result.try(case determine_filetype(filename) {
      Pdf -> convert_pdf(filename, path, username, cast_code)
      Pptx -> convert_pptx(filename, path, username, cast_code)
      Html -> convert_html(filename, path, username, cast_code)
      Unsupported -> Error(UnsupportedFileFormat)
    })

    store.set(ctx.store, username, filename, cast_code)

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
        InvalidCastCode ->
          wisp.html_response(
            "Cast codes can only use letters, numbers, - and _ (max 32)",
            400,
          )
        FailedGenerating(why) ->
          wisp.html_response(
            "Unprocessable file format: " <> string.inspect(why),
            422,
          )
      }
  }
}

fn choose_cast_code(code: String) -> Result(String, ThisThingError) {
  case code {
    "" -> Ok(wisp.random_string(6))
    _ ->
      case is_valid_cast_code(code) {
        True -> Ok(code)
        False -> Error(InvalidCastCode)
      }
  }
}

pub fn is_valid_cast_code(code: String) -> Bool {
  let length = string.length(code)
  length > 0
  && length <= 32
  && code
  |> string.to_graphemes
  |> list.all(fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
      c,
    )
  })
}

/// The name the generated presentation is saved under in ./view/<username>/.
pub fn view_filename(filename: String) -> String {
  case determine_filetype(filename) {
    Pdf -> string.replace(filename, ".pdf", ".html")
    Pptx -> string.replace(filename, ".pptx", ".html")
    Html | Unsupported -> filename
  }
}

fn remote_script_tag(cast_code: String) -> String {
  "<script src='/assets/cast-remote.js' data-cast-code='"
  <> cast_code
  <> "'></script>"
}

// Uploaded HTML is assumed to already be a Reveal.js deck (e.g. manim-slides),
// so it only needs the remote script before the closing </body>.
fn convert_html(
  filename: String,
  path: String,
  username: String,
  cast_code: String,
) -> Result(Nil, ThisThingError) {
  let fail = fn(why) { Error(FailedGenerating([#(why, "simplifile")])) }
  case simplifile.read(path) {
    Error(_) -> fail("Failed to read uploaded HTML")
    Ok(html) -> {
      let tag = remote_script_tag(cast_code)
      let html = case string.split(html, "</body>") |> list.reverse {
        [last, ..rest] if rest != [] ->
          string.join(list.reverse(rest), "</body>") <> tag <> "</body>" <> last
        _ -> html <> tag
      }
      case simplifile.create_directory_all(view_output_dir <> username) {
        Error(_) -> fail("Failed to create view directory")
        Ok(_) ->
          case
            simplifile.write(
              view_output_dir <> username <> "/" <> filename,
              html,
            )
          {
            Ok(_) -> Ok(Nil)
            Error(_) -> fail("Failed to write HTML file")
          }
      }
    }
  }
}

fn generate_qr_code(cast_code: String) -> Result(Nil, List(#(String, String))) {
  let qr_url = server_ip <> "/controls/" <> cast_code
  let qr_path = qr_output_dir <> "/" <> cast_code <> ".png"
  let _ = simplifile.create_directory_all(qr_output_dir)

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
    </style>
  </head>
  <body>
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
    " <> remote_script_tag(cast_code) <> "
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
  Html
  Unsupported
}

fn determine_filetype(filename: String) -> Filetype {
  let lower = string.lowercase(filename)
  case
    string.ends_with(lower, ".pdf"),
    string.ends_with(lower, ".pptx"),
    string.ends_with(lower, ".html") || string.ends_with(lower, ".htm")
  {
    True, _, _ -> Pdf
    _, True, _ -> Pptx
    _, _, True -> Html
    _, _, _ -> Unsupported
  }
}
