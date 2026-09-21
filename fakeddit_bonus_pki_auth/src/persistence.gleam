import api_types
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option
import gleam/result
import simplifile
import types.{
  type Account, type Comment, type DirectMessage, type EngineState, type Post,
  type Subreddit, Account, Comment, DirectMessage, EngineState, Post, Subreddit,
}

const state_file = "fakeddit_state.json"

// Async save - caller doesn't wait for disk I/O
pub fn save_state(state: EngineState) -> Result(Nil, String) {
  let encoded = encode_engine_state_for_persistence(state)
  let json_string = json.to_string(encoded)

  case simplifile.write(state_file, json_string) {
    Ok(_) -> {
      io.println("✓ State saved to " <> state_file)
      Ok(Nil)
    }
    Error(err) -> Error("Failed to save state: " <> string_inspect_error(err))
  }
}

// Restore state from JSON file
pub fn load_state(shard_name: String) -> Result(EngineState, String) {
  case simplifile.read(state_file) {
    Ok(json_string) -> {
      io.println(
        "✓ Loading saved state from " <> state_file <> " → " <> shard_name,
      )
      case json.parse(json_string, state_decoder()) {
        Ok(state) -> {
          io.println("✓ Successfully loaded state from disk")
          Ok(state)
        }
        Error(_errors) -> {
          io.println("⚠ Failed to decode state")
          io.println("  Starting with empty state")
          // Corrupt file? Start fresh rather than crash
          Ok(empty_state())
        }
      }
    }
    Error(_) -> {
      io.println("No saved state found, starting fresh")
      Ok(empty_state())
    }
  }
}

fn empty_state() -> EngineState {
  EngineState(
    accounts: dict.new(),
    subreddits: dict.new(),
    posts: dict.new(),
    comments: dict.new(),
    direct_messages: dict.new(),
    user_messages: dict.new(),
    user_karma_cache: dict.new(),
  )
}

// Parse JSON into EngineState
fn state_decoder() -> decode.Decoder(EngineState) {
  use accounts <- decode.field("accounts", dict_decoder(account_decoder()))
  use subreddits <- decode.field(
    "subreddits",
    dict_decoder(subreddit_decoder()),
  )
  use posts <- decode.field("posts", dict_decoder(post_decoder()))
  use comments <- decode.field("comments", dict_decoder(comment_decoder()))
  use direct_messages <- decode.field(
    "direct_messages",
    dict_decoder(message_decoder()),
  )
  use user_messages <- decode.field(
    "user_messages",
    dict_decoder(decode.list(decode.string)),
  )
  use user_karma_cache <- decode.field(
    "user_karma_cache",
    dict_decoder(decode.int),
  )

  decode.success(EngineState(
    accounts: accounts,
    subreddits: subreddits,
    posts: posts,
    comments: comments,
    direct_messages: direct_messages,
    user_messages: user_messages,
    user_karma_cache: user_karma_cache,
  ))
}

fn account_decoder() -> decode.Decoder(Account) {
  use id <- decode.field("id", decode.string)
  use username <- decode.field("username", decode.string)
  use karma <- decode.field("karma", decode.int)
  use joined_subreddits <- decode.field(
    "joined_subreddits",
    decode.list(decode.string),
  )
  use created_at <- decode.field("created_at", decode.int)
  use public_key <- decode.field("public_key", decode.string)
  use private_key <- decode.field("private_key", decode.optional(decode.string))

  decode.success(Account(
    id: id,
    username: username,
    karma: karma,
    joined_subreddits: joined_subreddits,
    created_at: created_at,
    public_key: public_key,
    private_key: option.unwrap(private_key, ""),
  ))
}

fn subreddit_decoder() -> decode.Decoder(Subreddit) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  use members <- decode.field("members", decode.list(decode.string))
  use posts <- decode.field("posts", decode.list(decode.string))
  use created_at <- decode.field("created_at", decode.int)

  decode.success(Subreddit(
    id: id,
    name: name,
    description: description,
    members: members,
    posts: posts,
    created_at: created_at,
  ))
}

fn post_decoder() -> decode.Decoder(Post) {
  use id <- decode.field("id", decode.string)
  use author_id <- decode.field("author_id", decode.string)
  use subreddit_id <- decode.field("subreddit_id", decode.string)
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  use upvotes <- decode.field("upvotes", decode.int)
  use downvotes <- decode.field("downvotes", decode.int)
  use comments <- decode.field("comments", decode.list(decode.string))
  use created_at <- decode.field("created_at", decode.int)
  use is_repost <- decode.field("is_repost", decode.bool)
  use original_post_id <- decode.field(
    "original_post_id",
    decode.optional(decode.string),
  )
  use original_author_id <- decode.field(
    "original_author_id",
    decode.optional(decode.string),
  )
  use original_subreddit_id <- decode.field(
    "original_subreddit_id",
    decode.optional(decode.string),
  )
  use signature <- decode.field("signature", decode.string)

  decode.success(Post(
    id: id,
    author_id: author_id,
    subreddit_id: subreddit_id,
    title: title,
    content: content,
    upvotes: upvotes,
    downvotes: downvotes,
    comments: comments,
    created_at: created_at,
    is_repost: is_repost,
    original_post_id: original_post_id,
    original_author_id: original_author_id,
    original_subreddit_id: original_subreddit_id,
    signature: signature,
  ))
}

fn comment_decoder() -> decode.Decoder(Comment) {
  use id <- decode.field("id", decode.string)
  use author_id <- decode.field("author_id", decode.string)
  use post_id <- decode.field("post_id", decode.string)
  use parent_comment_id <- decode.field(
    "parent_comment_id",
    decode.optional(decode.string),
  )
  use content <- decode.field("content", decode.string)
  use upvotes <- decode.field("upvotes", decode.int)
  use downvotes <- decode.field("downvotes", decode.int)
  use replies <- decode.field("replies", decode.list(decode.string))
  use created_at <- decode.field("created_at", decode.int)

  decode.success(Comment(
    id: id,
    author_id: author_id,
    post_id: post_id,
    parent_comment_id: parent_comment_id,
    content: content,
    upvotes: upvotes,
    downvotes: downvotes,
    replies: replies,
    created_at: created_at,
  ))
}

fn message_decoder() -> decode.Decoder(DirectMessage) {
  use id <- decode.field("id", decode.string)
  use from_user_id <- decode.field("from_user_id", decode.string)
  use to_user_id <- decode.field("to_user_id", decode.string)
  use content <- decode.field("content", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use is_read <- decode.field("is_read", decode.bool)

  decode.success(DirectMessage(
    id: id,
    from_user_id: from_user_id,
    to_user_id: to_user_id,
    content: content,
    created_at: created_at,
    is_read: is_read,
  ))
}

fn dict_decoder(
  value_decoder: decode.Decoder(v),
) -> decode.Decoder(Dict(String, v)) {
  use entries <- decode.then(decode.list(decode.dynamic))

  let results =
    entries
    |> list.map(fn(entry) {
      let key_result = {
        use key <- decode.field("key", decode.string)
        decode.success(key)
      }
      let value_result = {
        use value <- decode.field("value", value_decoder)
        decode.success(value)
      }

      case decode.run(entry, key_result), decode.run(entry, value_result) {
        Ok(key), Ok(value) -> Ok(#(key, value))
        _, _ -> Error(Nil)
      }
    })

  let all_ok = list.all(results, result.is_ok)

  case all_ok {
    True -> {
      let pairs =
        results
        |> list.filter_map(fn(r) { r })

      decode.success(dict.from_list(pairs))
    }
    False -> decode.failure(dict.new(), expected: "Dict")
  }
}

// Persistence encoding - includes private_key (unlike API encoding)
fn encode_engine_state_for_persistence(state: EngineState) -> Json {
  json.object([
    #("accounts", encode_accounts_dict(state.accounts)),
    #("subreddits", encode_subreddits_dict(state.subreddits)),
    #("posts", encode_posts_dict(state.posts)),
    #("comments", encode_comments_dict(state.comments)),
    #("direct_messages", encode_messages_dict(state.direct_messages)),
    #("user_messages", encode_user_messages_dict(state.user_messages)),
    #("user_karma_cache", encode_int_dict(state.user_karma_cache)),
  ])
}

fn encode_accounts_dict(accounts: Dict(String, Account)) -> Json {
  accounts
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", encode_account_with_private_key(value)),
    ])
  })
}

fn encode_account_with_private_key(account: Account) -> Json {
  json.object([
    #("id", json.string(account.id)),
    #("username", json.string(account.username)),
    #("karma", json.int(account.karma)),
    #("joined_subreddits", json.array(account.joined_subreddits, json.string)),
    #("created_at", json.int(account.created_at)),
    #("public_key", json.string(account.public_key)),
    #("private_key", json.string(account.private_key)),
  ])
}

fn encode_subreddits_dict(subreddits: Dict(String, Subreddit)) -> Json {
  subreddits
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", api_types.encode_subreddit(value)),
    ])
  })
}

fn encode_posts_dict(posts: Dict(String, Post)) -> Json {
  posts
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", api_types.encode_post(value)),
    ])
  })
}

fn encode_comments_dict(comments: Dict(String, Comment)) -> Json {
  comments
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", api_types.encode_comment(value)),
    ])
  })
}

fn encode_messages_dict(messages: Dict(String, DirectMessage)) -> Json {
  messages
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", api_types.encode_message(value)),
    ])
  })
}

fn encode_user_messages_dict(user_messages: Dict(String, List(String))) -> Json {
  user_messages
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", json.array(value, json.string)),
    ])
  })
}

fn encode_int_dict(dict_data: Dict(String, Int)) -> Json {
  dict_data
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", json.int(value))])
  })
}

fn string_inspect_error(err: simplifile.FileError) -> String {
  case err {
    simplifile.Enoent -> "File not found"
    simplifile.Eacces -> "Permission denied"
    simplifile.Epipe -> "Broken pipe"
    simplifile.Eexist -> "File already exists"
    simplifile.Eisdir -> "Is a directory"
    simplifile.Enotdir -> "Not a directory"
    simplifile.Enametoolong -> "Name too long"
    _ -> "Unknown error"
  }
}
