// Populates data via REST API (requires server running on localhost:8000)
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import types.{type PostId, type SubredditId, type UserId}
import utils

const base_url = "http://localhost:8000/api/v1"

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn get_args_raw() -> List(Charlist)

@external(erlang, "erlang", "list_to_binary")
fn charlist_to_string(charlist: Charlist) -> String

fn get_args() -> List(String) {
  get_args_raw()
  |> list.map(charlist_to_string)
}

@external(erlang, "inets", "start")
fn start_inets() -> Result(Nil, Nil)

pub fn main() {
  // Start inets for HTTP client
  let _ = start_inets()

  io.println("==============================================")
  io.println("  Fakeddit - Simulator")
  io.println("==============================================")
  io.println("")
  io.println("This simulator populates data via the REST API")
  io.println("Make sure the API server is running on port 8000")
  io.println("")

  // Parse command-line arguments: users subs posts comments votes messages
  let args = get_args()
  let #(
    num_users,
    num_subreddits,
    num_posts,
    num_comments,
    num_votes,
    num_messages,
  ) = case args {
    [users_str, subs_str, posts_str, comments_str, votes_str, msgs_str] -> {
      let users = int.parse(users_str) |> result.unwrap(5)
      let subs = int.parse(subs_str) |> result.unwrap(5)
      let posts = int.parse(posts_str) |> result.unwrap(8)
      let comments = int.parse(comments_str) |> result.unwrap(20)
      let votes = int.parse(votes_str) |> result.unwrap(30)
      let msgs = int.parse(msgs_str) |> result.unwrap(0)
      #(users, subs, posts, comments, votes, msgs)
    }
    _ -> {
      #(5, 5, 8, 20, 30, 0)
    }
  }

  // Check if server is running
  case check_server_health() {
    Ok(_) -> {
      io.println("✓ Server is running and healthy")
      io.println("")

      io.println("Simulation Parameters:")
      io.println("   Users: " <> int.to_string(num_users))
      io.println("   Subfakeddits: " <> int.to_string(num_subreddits))
      io.println("   Posts: " <> int.to_string(num_posts))
      io.println("   Comments: " <> int.to_string(num_comments))
      io.println("   Votes: " <> int.to_string(num_votes))
      io.println("   Messages: " <> int.to_string(num_messages))
      io.println("")

      run_http_simulation(
        num_users,
        num_subreddits,
        num_posts,
        num_comments,
        num_votes,
        num_messages,
      )

      io.println("")
      io.println("==============================================")
      io.println("  Simulation Complete!")
      io.println("==============================================")
    }
    Error(_) -> {
      io.println("✗ Error: API server is not running!")
      io.println("")
      io.println("Please start the server first:")
      io.println("   gleam run -m api_server")
      io.println("")
    }
  }
}

fn check_server_health() -> Result(Nil, Nil) {
  let url = "http://localhost:8000/api/health"
  case make_get_request(url) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

pub fn run_http_simulation(
  num_users: Int,
  num_subreddits: Int,
  num_posts: Int,
  num_comments: Int,
  num_votes: Int,
  num_messages: Int,
) -> Nil {
  io.println("Starting data population via REST API...")
  io.println(string.repeat("=", 48))
  io.println("")

  // Step 1: Create users
  io.println("STEP 1: Registering users...")
  io.println("---------------------------------------")
  let user_ids = create_users_http(num_users)
  io.println("---------------------------------------")
  case list.length(user_ids) {
    0 -> {
      io.println("✗ FAILED: No users created!")
      io.println("")
      io.println("This means the HTTP requests are failing.")
      io.println("Check the server window for errors.")
    }
    count -> {
      io.println("✓ Registered " <> int.to_string(count) <> " users")
      io.println("")

      // Step 2: Create subfakeddits
      io.println("STEP 2: Creating subfakeddits...")
      io.println("---------------------------------------")
      let subreddit_ids = create_subreddits_http(num_subreddits, user_ids)
      io.println("---------------------------------------")
      io.println(
        "✓ Created "
        <> int.to_string(list.length(subreddit_ids))
        <> " subfakeddits",
      )
      io.println("")

      // Step 2.5: Users join subfakeddits
      io.println("STEP 2.5: Users joining subfakeddits...")
      io.println("---------------------------------------")
      join_subreddits_http(user_ids, subreddit_ids)
      io.println("---------------------------------------")
      io.println("✓ Users joined subfakeddits")
      io.println("")

      // Step 3: Create posts
      io.println("STEP 3: Creating posts...")
      io.println("---------------------------------------")
      let post_ids = create_posts_http(user_ids, subreddit_ids, num_posts)
      io.println("---------------------------------------")
      io.println(
        "✓ Created " <> int.to_string(list.length(post_ids)) <> " posts",
      )
      io.println("")

      // Step 4: Create comments
      io.println("STEP 4: Creating comments...")
      io.println("---------------------------------------")
      let comments_created =
        create_comments_http(user_ids, post_ids, num_comments)
      io.println("---------------------------------------")
      io.println("✓ Created " <> int.to_string(comments_created) <> " comments")
      io.println("")

      // Step 5: Vote on posts
      io.println("STEP 5: Voting on posts...")
      io.println("---------------------------------------")
      let votes_created = vote_on_posts_http(user_ids, post_ids, num_votes)
      io.println("---------------------------------------")
      io.println("✓ Cast " <> int.to_string(votes_created) <> " votes")
      io.println("")

      // Step 6: Send direct messages (optional)
      case num_messages > 0 {
        True -> {
          io.println("STEP 6: Sending direct messages...")
          io.println("---------------------------------------")
          let messages_created =
            send_direct_messages_http(user_ids, num_messages)
          io.println("---------------------------------------")
          io.println(
            "✓ Sent " <> int.to_string(messages_created) <> " messages",
          )
          io.println("")
        }
        False -> {
          io.println("STEP 6: Skipping direct messages (set to 0)")
          io.println("")
        }
      }

      io.println("Full population complete!")
    }
  }

  Nil
}

fn create_users_http(count: Int) -> List(UserId) {
  create_users_http_helper(count, [])
}

fn create_users_http_helper(remaining: Int, acc: List(UserId)) -> List(UserId) {
  case remaining {
    0 -> list.reverse(acc)
    n -> {
      let username = utils.random_name()
      case register_account_http(username) {
        Ok(user_id) -> {
          // Show progress every 20 users
          case n % 20 {
            0 ->
              io.println(
                "   Progress: "
                <> int.to_string(list.length(acc) + 1)
                <> " users registered",
              )
            _ -> Nil
          }
          create_users_http_helper(n - 1, [user_id, ..acc])
        }
        Error(_) -> create_users_http_helper(n - 1, acc)
      }
    }
  }
}

fn create_subreddits_http(
  count: Int,
  user_ids: List(UserId),
) -> List(SubredditId) {
  create_subreddits_http_helper(count, user_ids, [])
}

fn create_subreddits_http_helper(
  remaining: Int,
  user_ids: List(UserId),
  acc: List(SubredditId),
) -> List(SubredditId) {
  case remaining {
    0 -> list.reverse(acc)
    n -> {
      let name = random_subreddit_name()
      let description = "A subfakeddit about " <> name
      let creator_id = case utils.take_random_item(user_ids) {
        Ok(uid) -> uid
        Error(_) -> "user_1"
      }
      case create_subreddit_http(name, description, creator_id) {
        Ok(subreddit_id) -> {
          case n % 10 {
            0 ->
              io.println(
                "   Progress: "
                <> int.to_string(list.length(acc) + 1)
                <> " subreddits created",
              )
            _ -> Nil
          }
          create_subreddits_http_helper(n - 1, user_ids, [subreddit_id, ..acc])
        }
        Error(_) -> create_subreddits_http_helper(n - 1, user_ids, acc)
      }
    }
  }
}

fn join_subreddits_http(
  user_ids: List(UserId),
  subreddit_ids: List(SubredditId),
) -> Nil {
  let total_users = list.length(user_ids)
  let total_subreddits = list.length(subreddit_ids)
  list.index_map(user_ids, fn(user_id, index) {
    // Each user joins 5-15 subreddits (or all available if fewer)
    let max_joins = case total_subreddits {
      n if n < 15 -> n
      _ -> utils.random_int(5, 15)
    }
    let subreddits_to_join = select_subreddits_zipf(subreddit_ids, max_joins)

    list.each(subreddits_to_join, fn(subreddit_id) {
      let _ = join_subreddit_http(user_id, subreddit_id)
      Nil
    })

    // Show progress every 20 users
    case { index + 1 } % 20 {
      0 ->
        io.println(
          "   Progress: "
          <> int.to_string(index + 1)
          <> "/"
          <> int.to_string(total_users)
          <> " users joined subreddits",
        )
      _ -> Nil
    }
  })
  Nil
}

fn create_posts_http(
  user_ids: List(UserId),
  subreddit_ids: List(SubredditId),
  target_count: Int,
) -> List(PostId) {
  create_posts_http_helper(user_ids, subreddit_ids, target_count, [])
}

fn create_posts_http_helper(
  user_ids: List(UserId),
  subreddit_ids: List(SubredditId),
  remaining: Int,
  acc: List(PostId),
) -> List(PostId) {
  case remaining {
    0 -> list.reverse(acc)
    n -> {
      // Select random user and subreddit using Zipf distribution
      let author_id = case select_random_zipf(user_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(user_ids) {
            Ok(id) -> id
            Error(_) -> "user_1"
          }
      }

      let subreddit_id = case select_random_zipf(subreddit_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(subreddit_ids) {
            Ok(id) -> id
            Error(_) -> "subreddit_1"
          }
      }

      let title = generate_post_title()
      let content = generate_post_content()

      case create_post_http(title, content, author_id, subreddit_id) {
        Ok(post_id) -> {
          case n % 100 {
            0 ->
              io.println(
                "   Progress: "
                <> int.to_string(list.length(acc) + 1)
                <> " posts created",
              )
            _ -> Nil
          }
          create_posts_http_helper(user_ids, subreddit_ids, n - 1, [
            post_id,
            ..acc
          ])
        }
        Error(_) ->
          create_posts_http_helper(user_ids, subreddit_ids, n - 1, acc)
      }
    }
  }
}

fn create_comments_http(
  user_ids: List(UserId),
  post_ids: List(PostId),
  target_count: Int,
) -> Int {
  create_comments_http_helper(user_ids, post_ids, target_count, 0)
}

fn create_comments_http_helper(
  user_ids: List(UserId),
  post_ids: List(PostId),
  remaining: Int,
  count: Int,
) -> Int {
  case remaining {
    0 -> count
    n -> {
      let author_id = case select_random_zipf(user_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(user_ids) {
            Ok(id) -> id
            Error(_) -> "user_1"
          }
      }

      let post_id = case select_random_zipf(post_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(post_ids) {
            Ok(id) -> id
            Error(_) -> "post_1"
          }
      }

      let content = generate_comment_content()

      case create_comment_http(content, author_id, post_id) {
        Ok(_) -> {
          case n % 100 {
            0 ->
              io.println(
                "   Progress: "
                <> int.to_string(count + 1)
                <> " comments created",
              )
            _ -> Nil
          }
          create_comments_http_helper(user_ids, post_ids, n - 1, count + 1)
        }
        Error(_) ->
          create_comments_http_helper(user_ids, post_ids, n - 1, count)
      }
    }
  }
}

fn vote_on_posts_http(
  user_ids: List(UserId),
  post_ids: List(PostId),
  target_votes: Int,
) -> Int {
  vote_on_posts_http_helper(user_ids, post_ids, target_votes, 0)
}

fn vote_on_posts_http_helper(
  user_ids: List(UserId),
  post_ids: List(PostId),
  remaining: Int,
  count: Int,
) -> Int {
  case remaining {
    0 -> count
    n -> {
      let user_id = case utils.take_random_item(user_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(user_ids) {
            Ok(id) -> id
            Error(_) -> "user_1"
          }
      }

      let post_id = case select_random_zipf(post_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(post_ids) {
            Ok(id) -> id
            Error(_) -> "post_1"
          }
      }

      // 70% upvote, 30% downvote
      let vote_result = case utils.random_int(1, 100) {
        r if r <= 70 -> upvote_post_http(post_id, user_id)
        _ -> downvote_post_http(post_id, user_id)
      }

      case vote_result {
        Ok(_) -> {
          case n % 200 {
            0 ->
              io.println(
                "   Progress: " <> int.to_string(count + 1) <> " votes added",
              )
            _ -> Nil
          }
          vote_on_posts_http_helper(user_ids, post_ids, n - 1, count + 1)
        }
        Error(_) -> vote_on_posts_http_helper(user_ids, post_ids, n - 1, count)
      }
    }
  }
}

fn send_direct_messages_http(user_ids: List(UserId), target_count: Int) -> Int {
  send_direct_messages_http_helper(user_ids, target_count, 0)
}

fn send_direct_messages_http_helper(
  user_ids: List(UserId),
  remaining: Int,
  count: Int,
) -> Int {
  case remaining {
    0 -> count
    n -> {
      let sender_id = case utils.take_random_item(user_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(user_ids) {
            Ok(id) -> id
            Error(_) -> "user_1"
          }
      }

      let recipient_id = case utils.take_random_item(user_ids) {
        Ok(id) -> id
        Error(_) ->
          case list.first(user_ids) {
            Ok(id) -> id
            Error(_) -> "user_2"
          }
      }

      // Don't send message to self
      case sender_id == recipient_id {
        True -> send_direct_messages_http_helper(user_ids, n, count)
        False -> {
          let content = generate_message_content()
          case send_message_http(sender_id, recipient_id, content) {
            Ok(_) -> {
              case n % 20 {
                0 ->
                  io.println(
                    "   Progress: "
                    <> int.to_string(count + 1)
                    <> " messages sent",
                  )
                _ -> Nil
              }
              send_direct_messages_http_helper(user_ids, n - 1, count + 1)
            }
            Error(_) -> send_direct_messages_http_helper(user_ids, n - 1, count)
          }
        }
      }
    }
  }
}

fn register_account_http(username: String) -> Result(UserId, Nil) {
  let url = base_url <> "/accounts"
  let body = json.object([#("username", json.string(username))])

  case make_post_request(url, json.to_string(body)) {
    Ok(response_body) -> parse_user_id(response_body)
    Error(_) -> Error(Nil)
  }
}

fn create_subreddit_http(
  name: String,
  description: String,
  creator_id: UserId,
) -> Result(SubredditId, Nil) {
  let url = base_url <> "/subreddits"
  let body =
    json.object([
      #("name", json.string(name)),
      #("description", json.string(description)),
      #("creator_id", json.string(creator_id)),
    ])

  case make_post_request_with_user(url, json.to_string(body), creator_id) {
    Ok(response_body) -> parse_subreddit_id(response_body)
    Error(_) -> Error(Nil)
  }
}

fn join_subreddit_http(
  user_id: UserId,
  subreddit_id: SubredditId,
) -> Result(Nil, Nil) {
  let url = base_url <> "/subreddits/" <> subreddit_id <> "/join"
  // Join endpoint only needs x-user-id header, empty body
  let body = json.object([])

  case make_post_request_with_user(url, json.to_string(body), user_id) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn create_post_http(
  title: String,
  content: String,
  author_id: UserId,
  subreddit_id: SubredditId,
) -> Result(PostId, Nil) {
  let url = base_url <> "/subreddits/" <> subreddit_id <> "/posts"
  // Post endpoint uses x-user-id header, not author_id in body
  let body =
    json.object([
      #("title", json.string(title)),
      #("content", json.string(content)),
    ])

  case make_post_request_with_user(url, json.to_string(body), author_id) {
    Ok(response_body) -> parse_post_id(response_body)
    Error(_) -> Error(Nil)
  }
}

fn create_comment_http(
  content: String,
  author_id: UserId,
  post_id: PostId,
) -> Result(String, Nil) {
  let url = base_url <> "/posts/" <> post_id <> "/comments"
  // Comment endpoint uses x-user-id header, not author_id in body
  let body =
    json.object([
      #("content", json.string(content)),
      #("parent_comment_id", json.null()),
    ])

  case make_post_request_with_user(url, json.to_string(body), author_id) {
    Ok(_) -> Ok("comment_created")
    Error(_) -> Error(Nil)
  }
}

fn upvote_post_http(post_id: PostId, user_id: UserId) -> Result(Nil, Nil) {
  let url = base_url <> "/posts/" <> post_id <> "/upvote"
  let body = json.object([#("user_id", json.string(user_id))])

  case make_post_request_with_user(url, json.to_string(body), user_id) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn downvote_post_http(post_id: PostId, user_id: UserId) -> Result(Nil, Nil) {
  let url = base_url <> "/posts/" <> post_id <> "/downvote"
  let body = json.object([#("user_id", json.string(user_id))])

  case make_post_request_with_user(url, json.to_string(body), user_id) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn send_message_http(
  sender_id: UserId,
  recipient_id: UserId,
  content: String,
) -> Result(Nil, Nil) {
  let url = base_url <> "/accounts/" <> sender_id <> "/messages"
  let body =
    json.object([
      #("to_user_id", json.string(recipient_id)),
      #("content", json.string(content)),
    ])

  case make_post_request_with_user(url, json.to_string(body), sender_id) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn make_get_request(url: String) -> Result(String, Nil) {
  case request.to(url) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) -> {
          io.println("  GET " <> url <> " -> " <> int.to_string(resp.status))
          Ok(resp.body)
        }
        Error(err) -> {
          io.println("  GET " <> url <> " -> Error: " <> string.inspect(err))
          Error(Nil)
        }
      }
    }
    Error(_) -> {
      io.println("  Invalid URL: " <> url)
      Error(Nil)
    }
  }
}

fn make_post_request(url: String, body: String) -> Result(String, Nil) {
  case request.to(url) {
    Ok(base_req) -> {
      let req =
        base_req
        |> request.set_body(body)
        |> request.set_method(http.Post)
        |> request.prepend_header("content-type", "application/json")

      case httpc.send(req) {
        Ok(resp) -> {
          io.println("  POST " <> url <> " -> " <> int.to_string(resp.status))
          Ok(resp.body)
        }
        Error(err) -> {
          io.println("  POST " <> url <> " -> Error: " <> string.inspect(err))
          Error(Nil)
        }
      }
    }
    Error(_) -> {
      io.println("  Invalid URL: " <> url)
      Error(Nil)
    }
  }
}

fn make_post_request_with_user(
  url: String,
  body: String,
  user_id: UserId,
) -> Result(String, Nil) {
  case request.to(url) {
    Ok(base_req) -> {
      let req =
        base_req
        |> request.set_body(body)
        |> request.set_method(http.Post)
        |> request.prepend_header("content-type", "application/json")
        |> request.prepend_header("x-user-id", user_id)

      case httpc.send(req) {
        Ok(resp) -> {
          io.println("  POST " <> url <> " -> " <> int.to_string(resp.status))
          Ok(resp.body)
        }
        Error(err) -> {
          io.println("  POST " <> url <> " -> Error: " <> string.inspect(err))
          Error(Nil)
        }
      }
    }
    Error(_) -> {
      io.println("  Invalid URL: " <> url)
      Error(Nil)
    }
  }
}

fn parse_user_id(response: String) -> Result(UserId, Nil) {
  // API returns: {"success":true,"data":{"id":"user_..."}}
  // Look for "id":"..." pattern after "data":
  io.println("  Response body: " <> response)
  case string.split(response, "\"id\":\"") {
    [_, rest] -> {
      case string.split(rest, "\"") {
        [user_id, ..] -> {
          io.println("  ✓ Parsed user_id: " <> user_id)
          Ok(user_id)
        }
        _ -> {
          io.println("  ✗ Failed to extract ID from split")
          Error(Nil)
        }
      }
    }
    _ -> {
      io.println("  ✗ No 'id' field found in response")
      Error(Nil)
    }
  }
}

fn parse_subreddit_id(response: String) -> Result(SubredditId, Nil) {
  // API returns: {"success":true,"data":{"id":"subreddit_..."}}
  io.println("  Response body: " <> response)
  case string.split(response, "\"id\":\"") {
    [_, rest] -> {
      case string.split(rest, "\"") {
        [subreddit_id, ..] -> {
          io.println("  ✓ Parsed subreddit_id: " <> subreddit_id)
          Ok(subreddit_id)
        }
        _ -> {
          io.println("  ✗ Failed to extract ID from split")
          Error(Nil)
        }
      }
    }
    _ -> {
      io.println("  ✗ No 'id' field found in response")
      Error(Nil)
    }
  }
}

fn parse_post_id(response: String) -> Result(PostId, Nil) {
  // API returns: {"success":true,"data":{"id":"post_..."}}
  io.println("  Response body: " <> response)
  case string.split(response, "\"id\":\"") {
    [_, rest] -> {
      case string.split(rest, "\"") {
        [post_id, ..] -> {
          io.println("  ✓ Parsed post_id: " <> post_id)
          Ok(post_id)
        }
        _ -> {
          io.println("  ✗ Failed to extract ID from split")
          Error(Nil)
        }
      }
    }
    _ -> {
      io.println("  ✗ No 'id' field found in response")
      Error(Nil)
    }
  }
}

fn random_subreddit_name() -> String {
  let topics = [
    "technology", "science", "politics", "sports", "gaming", "music", "movies",
    "books", "art", "photography", "cooking", "fitness", "travel", "fashion",
    "news", "funny", "memes", "history", "space", "cars", "pets", "food",
    "programming", "design", "business", "education", "health", "diy",
  ]

  case utils.take_random_item(topics) {
    Ok(name) -> name
    Error(_) -> "general"
  }
}

fn generate_post_title() -> String {
  let prefixes = [
    "Check out this", "TIL about", "Discussion:", "Question about",
    "My thoughts on", "Unpopular opinion:", "Why is", "How to",
    "Just discovered", "Sharing my", "Looking for", "Need help with",
  ]

  let topics = [
    "interesting topic", "amazing discovery", "new development",
    "important issue", "cool project", "helpful tip", "great resource",
    "useful information", "fascinating story", "recent news",
  ]

  let prefix = case utils.take_random_item(prefixes) {
    Ok(p) -> p
    Error(_) -> "Post about"
  }

  let topic = case utils.take_random_item(topics) {
    Ok(t) -> t
    Error(_) -> "something interesting"
  }

  prefix <> " " <> topic
}

fn generate_post_content() -> String {
  let contents = [
    "This is really interesting and I wanted to share it with everyone.",
    "I've been thinking about this for a while and here are my thoughts.",
    "Just wanted to get the community's opinion on this matter.",
    "Found this helpful resource that might benefit others here.",
    "Has anyone else experienced this? Would love to hear your thoughts.",
    "I think this is important to discuss as a community.",
  ]

  case utils.take_random_item(contents) {
    Ok(c) -> c
    Error(_) -> "This is an interesting post."
  }
}

fn generate_comment_content() -> String {
  let comments = [
    "Great point!", "I completely agree with this.", "Thanks for sharing!",
    "Very interesting perspective.", "I have a different opinion on this.",
    "Can you elaborate more?", "This is exactly what I was thinking.",
    "Well said!", "I'm not sure I agree, but good discussion.",
    "Learned something new today!",
  ]

  case utils.take_random_item(comments) {
    Ok(c) -> c
    Error(_) -> "Interesting comment."
  }
}

fn generate_message_content() -> String {
  let messages = [
    "Hey! Just wanted to reach out and say hi.",
    "I saw your post and wanted to discuss it further.",
    "Thanks for your comment on my post!",
    "Do you have any recommendations for good subreddits?",
    "I really enjoyed reading your content.",
    "Would love to collaborate on something.",
  ]

  case utils.take_random_item(messages) {
    Ok(m) -> m
    Error(_) -> "Hello there!"
  }
}

fn select_random_zipf(items: List(a)) -> Result(a, Nil) {
  let total = list.length(items)
  case total {
    0 -> Error(Nil)
    _ -> {
      let index = utils.zipf_sample(total)
      list_at(items, index)
    }
  }
}

fn select_subreddits_zipf(
  subreddits: List(SubredditId),
  count: Int,
) -> List(SubredditId) {
  select_subreddits_zipf_helper(subreddits, count, [])
}

fn select_subreddits_zipf_helper(
  subreddits: List(SubredditId),
  remaining: Int,
  acc: List(SubredditId),
) -> List(SubredditId) {
  case remaining {
    0 -> acc
    n -> {
      case select_random_zipf(subreddits) {
        Ok(subreddit_id) -> {
          // Only add if not already in the list (prevent duplicates)
          case list.contains(acc, subreddit_id) {
            True -> select_subreddits_zipf_helper(subreddits, n - 1, acc)
            False ->
              select_subreddits_zipf_helper(subreddits, n - 1, [
                subreddit_id,
                ..acc
              ])
          }
        }
        Error(_) -> select_subreddits_zipf_helper(subreddits, n - 1, acc)
      }
    }
  }
}

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], n if n > 0 -> list_at(rest, n - 1)
    _, _ -> Error(Nil)
  }
}
