///|
// FFI: File I/O and timing (Node.js JS target only)
// Run from project root: node _build/js/debug/build/bench/bench.js

extern "js" fn read_file_sync(path : String) -> String =
  #|(path) => require('fs').readFileSync(path, 'utf8')

///|
extern "js" fn perf_now() -> Double =
  #|() => typeof performance !== 'undefined' ? performance.now() : Number(process.hrtime.bigint()) / 1e6

///|
extern "js" fn memory_used_mb() -> Double =
  #|() => {
  #|  if (typeof process !== 'undefined' && process.memoryUsage) {
  #|    const m = process.memoryUsage();
  #|    return (m.heapUsed / 1024 / 1024);
  #|  }
  #|  return -1.0;
  #|}

///|
fn parse_json_file(path : String) -> Json raise @json.ParseError {
  @json.parse(read_file_sync(path))
}

///|
fn fmt3(d : Double) -> String {
  let x = (d * 1000.0).to_int().to_double() / 1000.0
  x.to_string()
}

///|
fn bench_fn(label : String, iters : Int, f : () -> Unit) -> Unit {
  let start = perf_now()
  for _ in 0..<iters {
    f()
  }
  let elapsed = perf_now() - start
  let per_iter = elapsed / iters.to_double()
  println(
    "  \{label}: \{iters}× → total \{fmt3(elapsed)}ms, \{fmt3(per_iter)}ms/iter",
  )
}

///|
fn print_sep() -> Unit {
  println(
    "─────────────────────────────────────────────",
  )
}

///|
fn main {
  let fixture_dir = "./bench/fixtures"
  println("Loading and deserializing fixtures (Json → ChatState) …")

  fn load_struct(name : String) -> ChatState {
    let json = parse_json_file(fixture_dir + "/" + name) catch {
      e => {
        println("Failed to load \{name}: \{e}")
        panic()
      }
    }
    @json.from_json(json) catch {
      e => {
        println("Failed to deserialize \{name}: \{e}")
        panic()
      }
    }
  }

  let base_struct = load_struct("state_base.json")
  let single_msg_struct = load_struct("state_single_msg.json")
  let bulk_status_struct = load_struct("state_bulk_status.json")
  let new_thread_struct = load_struct("state_new_thread.json")
  let reorder_struct = load_struct("state_reorder.json")

  println("✓ All fixtures loaded and deserialized")
  println("  Heap after loading: \{fmt3(memory_used_mb())} MB")
  print_sep()

  // ── diff_value (struct → Json internally, then diff) ─────────────────────
  let iters_diff = 20
  println("=== diff_value[ChatState] (\{iters_diff} iters each) ===")
  bench_fn("single_msg  diff", iters_diff, fn() {
    ignore(@recollect.diff_value(base_struct, single_msg_struct))
  })
  bench_fn("bulk_status diff", iters_diff, fn() {
    ignore(@recollect.diff_value(base_struct, bulk_status_struct))
  })
  bench_fn("new_thread  diff", iters_diff, fn() {
    ignore(@recollect.diff_value(base_struct, new_thread_struct))
  })
  bench_fn("reorder     diff", iters_diff, fn() {
    ignore(@recollect.diff_value(base_struct, reorder_struct))
  })
  print_sep()

  let tdiff_single = @recollect.diff_value(base_struct, single_msg_struct)
  let tdiff_bulk = @recollect.diff_value(base_struct, bulk_status_struct)
  let tdiff_thread = @recollect.diff_value(base_struct, new_thread_struct)
  let tdiff_reorder = @recollect.diff_value(base_struct, reorder_struct)

  println("Pre-computed patch op counts:")
  println("  single_msg  patch ops: \{tdiff_single.length()}")
  println("  bulk_status patch ops: \{tdiff_bulk.length()}")
  println("  new_thread  patch ops: \{tdiff_thread.length()}")
  println("  reorder     patch ops: \{tdiff_reorder.length()}")
  print_sep()

  // ── apply_to_value (patch + Json → struct) ────────────────────────────────
  let iters_patch = 20
  println("=== apply_to_value[ChatState] (\{iters_patch} iters each) ===")
  bench_fn("single_msg  patch", iters_patch, fn() {
    let _ : ChatState = @recollect.apply_to_value(base_struct, tdiff_single) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("bulk_status patch", iters_patch, fn() {
    let _ : ChatState = @recollect.apply_to_value(base_struct, tdiff_bulk) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("new_thread  patch", iters_patch, fn() {
    let _ : ChatState = @recollect.apply_to_value(base_struct, tdiff_thread) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("reorder     patch", iters_patch, fn() {
    let _ : ChatState = @recollect.apply_to_value(base_struct, tdiff_reorder) catch {
      _ => panic()
    }
    ()
  })
  print_sep()

  // ── round-trip (diff + patch on struct) ──────────────────────────────────
  let iters_rt = 10
  println(
    "=== round-trip diff_value + apply_to_value (\{iters_rt} iters each) ===",
  )
  bench_fn("single_msg  rt", iters_rt, fn() {
    let d = @recollect.diff_value(base_struct, single_msg_struct)
    let _ : ChatState = @recollect.apply_to_value(base_struct, d) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("bulk_status rt", iters_rt, fn() {
    let d = @recollect.diff_value(base_struct, bulk_status_struct)
    let _ : ChatState = @recollect.apply_to_value(base_struct, d) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("new_thread  rt", iters_rt, fn() {
    let d = @recollect.diff_value(base_struct, new_thread_struct)
    let _ : ChatState = @recollect.apply_to_value(base_struct, d) catch {
      _ => panic()
    }
    ()
  })
  bench_fn("reorder     rt", iters_rt, fn() {
    let d = @recollect.diff_value(base_struct, reorder_struct)
    let _ : ChatState = @recollect.apply_to_value(base_struct, d) catch {
      _ => panic()
    }
    ()
  })
  print_sep()

  println("Heap at end: \{fmt3(memory_used_mb())} MB")
  println("Done.")
}
