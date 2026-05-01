///|
pub(all) enum PathSegment {
  Field(String)
  Index(Int)
} derive(Eq, Debug, FromJson, ToJson)

///|
pub(all) enum PatchOp {
  Set(path~ : Array[PathSegment], value~ : Json)
  Remove(path~ : Array[PathSegment])
  Insert(path~ : Array[PathSegment], index~ : Int, value~ : Json)
  Delete(path~ : Array[PathSegment], index~ : Int)
  Move(path~ : Array[PathSegment], from_index~ : Int, to_index~ : Int)
} derive(Eq, Debug, FromJson, ToJson)

///|
fn path_with_field(
  path : Array[PathSegment],
  key : String,
) -> Array[PathSegment] {
  let next = path.copy()
  next.push(Field(key))
  next
}

///|
fn path_with_index(
  path : Array[PathSegment],
  index : Int,
) -> Array[PathSegment] {
  let next = path.copy()
  next.push(Index(index))
  next
}

///|
fn sorted_keys(obj : Map[String, Json]) -> Array[String] {
  let keys = Array::new(capacity=obj.length())
  for key, _ in obj {
    keys.push(key)
  }
  keys.sort()
  keys
}

///|
fn json_id(value : Json) -> String? {
  guard value is Object(obj) else { return None }
  guard obj.get("id") is Some(String(id)) else { return None }
  Some(id)
}

///|
fn unique_string_ids(values : Array[Json]) -> Array[String]? {
  let ids = Array::new(capacity=values.length())
  let seen : Map[String, Bool] = {}
  for value in values {
    guard json_id(value) is Some(id) else { return None }
    if seen.contains(id) {
      return None
    }
    seen.set(id, true)
    ids.push(id)
  }
  Some(ids)
}

///|
fn has_id_from(ids : Array[String], start : Int, target : String) -> Bool {
  for index in start..<ids.length() {
    if ids[index] == target {
      return true
    }
  }
  false
}

///|
fn find_id_from(ids : Array[String], start : Int, target : String) -> Int? {
  for index in start..<ids.length() {
    if ids[index] == target {
      return Some(index)
    }
  }
  None
}

///|
fn[T] move_in_place(items : Array[T], from_index : Int, to_index : Int) -> Unit {
  let item = items[from_index]
  ignore(items.remove(from_index))
  items.insert(to_index, item)
}

///|
fn collect_keyed_array_diff(
  path : Array[PathSegment],
  old_arr : Array[Json],
  new_arr : Array[Json],
  old_ids : Array[String],
  new_ids : Array[String],
  patches : Array[PatchOp],
) -> Unit {
  let working = old_arr.copy()
  let working_ids = old_ids.copy()

  let mut new_index = 0
  while new_index < new_ids.length() {
    let new_id = new_ids[new_index]
    if new_index >= working_ids.length() {
      patches.push(Insert(path~, index=new_index, value=new_arr[new_index]))
      working.insert(new_index, new_arr[new_index])
      working_ids.insert(new_index, new_id)
      new_index = new_index + 1
      continue
    }

    let current_id = working_ids[new_index]
    if current_id == new_id {
      collect_json_diff(
        path_with_index(path, new_index),
        working[new_index],
        new_arr[new_index],
        patches,
      )
      working[new_index] = new_arr[new_index]
      new_index = new_index + 1
      continue
    }

    if !has_id_from(new_ids, new_index, current_id) {
      patches.push(Delete(path~, index=new_index))
      ignore(working.remove(new_index))
      ignore(working_ids.remove(new_index))
      continue
    }

    match find_id_from(working_ids, new_index + 1, new_id) {
      Some(old_index) => {
        patches.push(Move(path~, from_index=old_index, to_index=new_index))
        move_in_place(working, old_index, new_index)
        move_in_place(working_ids, old_index, new_index)
        collect_json_diff(
          path_with_index(path, new_index),
          working[new_index],
          new_arr[new_index],
          patches,
        )
        working[new_index] = new_arr[new_index]
        new_index = new_index + 1
        continue
      }
      None => {
        patches.push(Insert(path~, index=new_index, value=new_arr[new_index]))
        working.insert(new_index, new_arr[new_index])
        working_ids.insert(new_index, new_id)
        new_index = new_index + 1
        continue
      }
    }
  }

  if working.length() > new_arr.length() {
    for index = working.length() - 1
        index >= new_arr.length()
        index = index - 1 {
      patches.push(Delete(path~, index~))
      ignore(working.remove(index))
      ignore(working_ids.remove(index))
    }
  }
}

///|
fn collect_object_diff(
  path : Array[PathSegment],
  old_obj : Map[String, Json],
  new_obj : Map[String, Json],
  patches : Array[PatchOp],
) -> Unit {
  let old_keys = sorted_keys(old_obj)
  for key in old_keys {
    if !new_obj.contains(key) {
      patches.push(Remove(path=path_with_field(path, key)))
    }
  }

  let new_keys = sorted_keys(new_obj)
  for key in new_keys {
    match old_obj.get(key) {
      Some(old_value) =>
        collect_json_diff(
          path_with_field(path, key),
          old_value,
          new_obj.get(key).unwrap(),
          patches,
        )
      None =>
        patches.push(
          Set(path=path_with_field(path, key), value=new_obj.get(key).unwrap()),
        )
    }
  }
}

///|
fn collect_array_diff(
  path : Array[PathSegment],
  old_arr : Array[Json],
  new_arr : Array[Json],
  patches : Array[PatchOp],
) -> Unit {
  match (unique_string_ids(old_arr), unique_string_ids(new_arr)) {
    (Some(old_ids), Some(new_ids)) => {
      collect_keyed_array_diff(
        path, old_arr, new_arr, old_ids, new_ids, patches,
      )
      return
    }
    _ => ()
  }

  let shared_len = if old_arr.length() < new_arr.length() {
    old_arr.length()
  } else {
    new_arr.length()
  }

  for i in 0..<shared_len {
    collect_json_diff(path_with_index(path, i), old_arr[i], new_arr[i], patches)
  }

  if old_arr.length() > shared_len {
    for i = old_arr.length() - 1; i >= shared_len; i = i - 1 {
      patches.push(Delete(path~, index=i))
    }
  }

  for i in shared_len..<new_arr.length() {
    patches.push(Insert(path~, index=i, value=new_arr[i]))
  }
}

///|
fn collect_json_diff(
  path : Array[PathSegment],
  old_json : Json,
  new_json : Json,
  patches : Array[PatchOp],
) -> Unit {
  if old_json == new_json {
    return
  }

  match (old_json, new_json) {
    (Object(old_obj), Object(new_obj)) =>
      collect_object_diff(path, old_obj, new_obj, patches)
    (Array(old_arr), Array(new_arr)) =>
      collect_array_diff(path, old_arr, new_arr, patches)
    _ => patches.push(Set(path~, value=new_json))
  }
}

///|
pub fn diff_json(old_json : Json, new_json : Json) -> Array[PatchOp] {
  let patches = Array::new()
  collect_json_diff([], old_json, new_json, patches)
  patches
}

///|
pub fn[T : ToJson] diff_value(old_value : T, new_value : T) -> Array[PatchOp] {
  diff_json(old_value.to_json(), new_value.to_json())
}

///|
fn apply_set(
  node : Json,
  path : Array[PathSegment],
  cursor : Int,
  value : Json,
) -> Json {
  if cursor == path.length() {
    return value
  }

  match path[cursor] {
    Field(key) => {
      guard node is Object(obj) else { abort("set path expected object") }
      let next = match obj.get(key) {
        Some(child) => child
        None => null
      }
      let out = obj.copy()
      out.set(key, apply_set(next, path, cursor + 1, value))
      Json::object(out)
    }
    Index(index) => {
      guard node is Array(arr) else { abort("set path expected array") }
      let out = arr.copy()
      out[index] = apply_set(arr[index], path, cursor + 1, value)
      Json::array(out)
    }
  }
}

///|
fn apply_remove(node : Json, path : Array[PathSegment], cursor : Int) -> Json {
  if cursor >= path.length() {
    return null
  }

  match path[cursor] {
    Field(key) => {
      guard node is Object(obj) else { abort("remove path expected object") }
      let out = obj.copy()
      if cursor == path.length() - 1 {
        out.remove(key)
        return Json::object(out)
      }
      let child = out.get(key).unwrap()
      out.set(key, apply_remove(child, path, cursor + 1))
      Json::object(out)
    }
    Index(index) => {
      guard node is Array(arr) else { abort("remove path expected array") }
      let out = arr.copy()
      if cursor == path.length() - 1 {
        out.remove(index) |> ignore
        return Json::array(out)
      }
      out[index] = apply_remove(arr[index], path, cursor + 1)
      Json::array(out)
    }
  }
}

///|
fn apply_insert(
  node : Json,
  path : Array[PathSegment],
  cursor : Int,
  index : Int,
  value : Json,
) -> Json {
  if cursor == path.length() {
    guard node is Array(arr) else { abort("insert path expected array") }
    let out = arr.copy()
    out.insert(index, value)
    return Json::array(out)
  }

  match path[cursor] {
    Field(key) => {
      guard node is Object(obj) else { abort("insert path expected object") }
      let out = obj.copy()
      let child = out.get(key).unwrap()
      out.set(key, apply_insert(child, path, cursor + 1, index, value))
      Json::object(out)
    }
    Index(path_index) => {
      guard node is Array(arr) else { abort("insert path expected array") }
      let out = arr.copy()
      out[path_index] = apply_insert(
        arr[path_index],
        path,
        cursor + 1,
        index,
        value,
      )
      Json::array(out)
    }
  }
}

///|
fn apply_delete(
  node : Json,
  path : Array[PathSegment],
  cursor : Int,
  index : Int,
) -> Json {
  if cursor == path.length() {
    guard node is Array(arr) else { abort("delete path expected array") }
    let out = arr.copy()
    out.remove(index) |> ignore
    return Json::array(out)
  }

  match path[cursor] {
    Field(key) => {
      guard node is Object(obj) else { abort("delete path expected object") }
      let out = obj.copy()
      let child = out.get(key).unwrap()
      out.set(key, apply_delete(child, path, cursor + 1, index))
      Json::object(out)
    }
    Index(path_index) => {
      guard node is Array(arr) else { abort("delete path expected array") }
      let out = arr.copy()
      out[path_index] = apply_delete(arr[path_index], path, cursor + 1, index)
      Json::array(out)
    }
  }
}

///|
fn apply_move(
  node : Json,
  path : Array[PathSegment],
  cursor : Int,
  from_index : Int,
  to_index : Int,
) -> Json {
  if cursor == path.length() {
    guard node is Array(arr) else { abort("move path expected array") }
    let out = arr.copy()
    move_in_place(out, from_index, to_index)
    return Json::array(out)
  }

  match path[cursor] {
    Field(key) => {
      guard node is Object(obj) else { abort("move path expected object") }
      let out = obj.copy()
      let child = out.get(key).unwrap()
      out.set(key, apply_move(child, path, cursor + 1, from_index, to_index))
      Json::object(out)
    }
    Index(path_index) => {
      guard node is Array(arr) else { abort("move path expected array") }
      let out = arr.copy()
      out[path_index] = apply_move(
        arr[path_index],
        path,
        cursor + 1,
        from_index,
        to_index,
      )
      Json::array(out)
    }
  }
}

///|
pub fn apply_patch(root : Json, patch : PatchOp) -> Json {
  match patch {
    Set(path~, value~) => apply_set(root, path, 0, value)
    Remove(path~) => apply_remove(root, path, 0)
    Insert(path~, index~, value~) => apply_insert(root, path, 0, index, value)
    Delete(path~, index~) => apply_delete(root, path, 0, index)
    Move(path~, from_index~, to_index~) =>
      apply_move(root, path, 0, from_index, to_index)
  }
}

///|
pub fn apply_patches(root : Json, patches : Array[PatchOp]) -> Json {
  let mut current = root
  for patch in patches {
    current = apply_patch(current, patch)
  }
  current
}

///|
pub fn[T : ToJson + FromJson] apply_to_value(
  value : T,
  patches : Array[PatchOp],
) -> T raise @json.JsonDecodeError {
  let patched_json = apply_patches(value.to_json(), patches)
  @json.from_json(patched_json)
}
