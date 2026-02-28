import gleam/dict
import gleam/erlang/process
import gleam/option.{type Option}
import gleam/otp/actor
import types.{type Message, Get, Store}

pub fn start() {
  let empty_codestore: types.CodeStore = dict.new()
  let assert Ok(store) =
    actor.new(empty_codestore)
    |> actor.on_message(handle_message)
    |> actor.start
  store.data
}

pub fn handle_message(state: types.CodeStore, msg: Message) {
  case msg {
    Store(username, filename, code) -> {
      let new_store = dict.insert(state, code, #(username, filename))
      actor.continue(new_store)
    }
    Get(code, reply) -> {
      let data = dict.get(state, code)
      actor.send(reply, option.from_result(data))
      actor.continue(state)
    }
  }
}

pub fn get(
  store: process.Subject(Message),
  code: String,
) -> Option(#(String, String)) {
  process.call(store, 100, Get(code, _))
}

pub fn set(
  store: process.Subject(Message),
  username: String,
  filename: String,
  code: String,
) -> Nil {
  actor.send(store, Store(username, filename, code))
}
