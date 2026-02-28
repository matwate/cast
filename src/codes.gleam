import gleam/dict
import wisp

pub type CodeStore =
  dict.Dict(String, #(String, String))

pub fn generate_cast_code(store: CodeStore) -> String {
  // Basically generate until it never collides.
  let code = wisp.random_string(6)
  case dict.has_key(store, code) {
    True -> generate_cast_code(store)
    False -> code
  }
}
