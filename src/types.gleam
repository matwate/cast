import gleam/dict
import gleam/erlang/process
import gleam/option.{type Option}

pub type CodeStore =
  dict.Dict(String, #(String, String))

pub type Context {
  Context(store: process.Subject(Message))
}

pub type Message {
  Store(username: String, filename: String, code: String)
  Get(code: String, reply: process.Subject(Option(#(String, String))))
}
