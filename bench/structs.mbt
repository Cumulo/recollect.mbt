///|
/// Typed structs mirroring the benchmark fixture JSON schema.
/// Used to measure the additional overhead of struct ↔ JSON conversion
/// on top of the raw diff/patch operations.

///|
struct Meta {
  version : Int
  generated_at : Int
  description : String
} derive(ToJson, @json.FromJson)

///|
struct User {
  id : String
  name : String
  avatar : String
  online : Bool
  bio : String
  role : String
  joined_at : Int
} derive(ToJson, @json.FromJson)

///|
struct Reaction {
  emoji : String
  user_id : String
} derive(ToJson, @json.FromJson)

///|
struct Reply {
  id : String
  author_id : String
  author_name : String
  text : String
  ts : Int
  reactions : Array[Reaction]
  edited : Bool
} derive(ToJson, @json.FromJson)

///|
struct Thread {
  id : String
  author_id : String
  author_name : String
  title : String
  text : String
  ts : Int
  pinned : Bool
  tags : Array[String]
  reactions : Array[Reaction]
  replies : Array[Reply]
} derive(ToJson, @json.FromJson)

///|
struct Channel {
  id : String
  name : String
  description : String
  threads : Array[Thread]
} derive(ToJson, @json.FromJson)

///|
/// Root state — mirrors state_base.json / state_*.json
struct ChatState {
  meta : Meta
  users : Array[User]
  channels : Array[Channel]
} derive(ToJson, @json.FromJson)
