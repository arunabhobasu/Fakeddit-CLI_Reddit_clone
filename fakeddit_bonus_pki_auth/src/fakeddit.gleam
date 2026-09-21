import api_handlers
import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import router_actor
import wisp
import wisp/wisp_mist

pub fn main() {
  io.println("========================================")
  io.println("  Fakeddit Server")
  io.println("========================================")
  io.println("")

  // STEP 1: Start hybrid router (1 write + 3 specialized read shards)
  io.println("STEP 1: Initializing operation-type routing with TTL caching...")
  io.println("  - Write shard: handles mutations, saves to disk")
  io.println("  - Read shards:")
  io.println("  --- Feed shard: GetFeed, GetPost, GetSubreddit")
  io.println("  --- User shard: GetAccount, GetUserKarma")
  io.println("  --- Misc shard: GetComments, GetDMs, Search")
  io.println("  --- Read TTL cache refresh: 500ms")
  let config = router_actor.RouterConfig(num_read_actors: 3)
  let assert Ok(router) = router_actor.start(config)
  io.println("✓ Router ready\n")

  // STEP 2: Start HTTP server
  io.println("STEP 2: Starting HTTP server on port 8000...")
  wisp.configure_logger()

  let ctx = api_handlers.Context(router: router)
  let handler = fn(req) { api_handlers.handle_request(req, ctx) }

  let port = 8000
  let assert Ok(_) =
    wisp_mist.handler(handler, "fakeddit_secret_key")
    |> mist.new
    |> mist.port(port)
    |> mist.start

  io.println("✓ HTTP server running on port " <> int.to_string(port))
  io.println(
    "   API Base: http://localhost:" <> int.to_string(port) <> "/api/v1\n",
  )

  io.println("========================================")
  io.println("  Server Ready!")
  io.println("========================================")
  io.println("")
  io.println("Server will continue running. Press Ctrl+C to stop.")
  io.println("========================================\n")

  // Keep server running
  process.sleep_forever()
}
