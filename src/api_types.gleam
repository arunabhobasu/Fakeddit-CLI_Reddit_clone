import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import types

pub type RegisterAccountRequest {
  RegisterAccountRequest(username: String)
}

pub type CreateSubredditRequest {
  CreateSubredditRequest(name: String, description: String)
}

pub type CreatePostRequest {
  CreatePostRequest(title: String, content: String)
}

pub type CreateCommentRequest {
  CreateCommentRequest(content: String, parent_comment_id: Option(String))
}

pub type SendMessageRequest {
  SendMessageRequest(to_user_id: String, content: String)
}

pub fn register_account_decoder() -> decode.Decoder(RegisterAccountRequest) {
  use username <- decode.field("username", decode.string)
  decode.success(RegisterAccountRequest(username))
}

pub fn create_subreddit_decoder() -> decode.Decoder(CreateSubredditRequest) {
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(CreateSubredditRequest(name, description))
}

pub fn create_post_decoder() -> decode.Decoder(CreatePostRequest) {
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(CreatePostRequest(title, content))
}

pub fn create_comment_decoder() -> decode.Decoder(CreateCommentRequest) {
  use content <- decode.field("content", decode.string)
  use parent_comment_id <- decode.field(
    "parent_comment_id",
    decode.optional(decode.string),
  )
  decode.success(CreateCommentRequest(content, parent_comment_id))
}

pub fn send_message_decoder() -> decode.Decoder(SendMessageRequest) {
  use to_user_id <- decode.field("to_user_id", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(SendMessageRequest(to_user_id, content))
}

pub fn encode_success(data: Json) -> Json {
  json.object([
    #("success", json.bool(True)),
    #("data", data),
  ])
}

pub fn encode_error(message: String) -> Json {
  json.object([
    #("success", json.bool(False)),
    #("error", json.string(message)),
  ])
}

pub fn encode_id(id: String) -> Json {
  json.object([#("id", json.string(id))])
}

pub fn encode_account(account: types.Account) -> Json {
  json.object([
    #("id", json.string(account.id)),
    #("username", json.string(account.username)),
    #("karma", json.int(account.karma)),
    #("joined_subreddits", json.array(account.joined_subreddits, json.string)),
    #("created_at", json.int(account.created_at)),
  ])
}

pub fn encode_karma(karma: Int) -> Json {
  json.object([#("karma", json.int(karma))])
}

pub fn encode_subreddit(subreddit: types.Subreddit) -> Json {
  let member_count = list.length(subreddit.members)

  json.object([
    #("id", json.string(subreddit.id)),
    #("name", json.string(subreddit.name)),
    #("description", json.string(subreddit.description)),
    #("member_count", json.int(member_count)),
    #("members", json.array(subreddit.members, json.string)),
    #("posts", json.array(subreddit.posts, json.string)),
    #("created_at", json.int(subreddit.created_at)),
  ])
}

pub fn encode_subreddits(subreddits: List(types.Subreddit)) -> Json {
  json.array(subreddits, encode_subreddit)
}

pub fn encode_post(post: types.Post) -> Json {
  let comment_count = list.length(post.comments)
  let original_post_id = case post.original_post_id {
    Some(id) -> json.string(id)
    None -> json.null()
  }
  let original_author_id = case post.original_author_id {
    Some(id) -> json.string(id)
    None -> json.null()
  }
  let original_subreddit_id = case post.original_subreddit_id {
    Some(id) -> json.string(id)
    None -> json.null()
  }

  json.object([
    #("id", json.string(post.id)),
    #("author_id", json.string(post.author_id)),
    #("subreddit_id", json.string(post.subreddit_id)),
    #("title", json.string(post.title)),
    #("content", json.string(post.content)),
    #("upvotes", json.int(post.upvotes)),
    #("downvotes", json.int(post.downvotes)),
    #("comment_count", json.int(comment_count)),
    #("comments", json.array(post.comments, json.string)),
    #("created_at", json.int(post.created_at)),
    #("is_repost", json.bool(post.is_repost)),
    #("original_post_id", original_post_id),
    #("original_author_id", original_author_id),
    #("original_subreddit_id", original_subreddit_id),
  ])
}

pub fn encode_posts(posts: List(types.Post)) -> Json {
  json.array(posts, encode_post)
}

pub fn encode_post_with_comments(
  post: types.Post,
  comments: List(types.Comment),
) -> Json {
  let comment_count = list.length(post.comments)

  json.object([
    #("id", json.string(post.id)),
    #("subreddit_id", json.string(post.subreddit_id)),
    #("author_id", json.string(post.author_id)),
    #("title", json.string(post.title)),
    #("content", json.string(post.content)),
    #("upvotes", json.int(post.upvotes)),
    #("downvotes", json.int(post.downvotes)),
    #("comment_count", json.int(comment_count)),
    #("comments", json.array(comments, encode_comment)),
  ])
}

pub fn encode_comment(comment: types.Comment) -> Json {
  let parent_id = case comment.parent_comment_id {
    Some(id) -> json.string(id)
    None -> json.null()
  }

  json.object([
    #("id", json.string(comment.id)),
    #("author_id", json.string(comment.author_id)),
    #("post_id", json.string(comment.post_id)),
    #("parent_comment_id", parent_id),
    #("content", json.string(comment.content)),
    #("upvotes", json.int(comment.upvotes)),
    #("downvotes", json.int(comment.downvotes)),
    #("replies", json.array(comment.replies, json.string)),
    #("created_at", json.int(comment.created_at)),
  ])
}

pub fn encode_comments(comments: List(types.Comment)) -> Json {
  json.array(comments, encode_comment)
}

pub fn encode_message(message: types.DirectMessage) -> Json {
  json.object([
    #("id", json.string(message.id)),
    #("from_user_id", json.string(message.from_user_id)),
    #("to_user_id", json.string(message.to_user_id)),
    #("content", json.string(message.content)),
    #("created_at", json.int(message.created_at)),
    #("is_read", json.bool(message.is_read)),
  ])
}

pub fn encode_messages(messages: List(types.DirectMessage)) -> Json {
  json.array(messages, encode_message)
}

pub fn encode_engine_state(state: types.EngineState) -> Json {
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

fn encode_accounts_dict(accounts: dict.Dict(String, types.Account)) -> Json {
  accounts
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", encode_account(value))])
  })
}

fn encode_subreddits_dict(
  subreddits: dict.Dict(String, types.Subreddit),
) -> Json {
  subreddits
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([
      #("key", json.string(key)),
      #("value", encode_subreddit(value)),
    ])
  })
}

fn encode_posts_dict(posts: dict.Dict(String, types.Post)) -> Json {
  posts
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", encode_post(value))])
  })
}

fn encode_comments_dict(comments: dict.Dict(String, types.Comment)) -> Json {
  comments
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", encode_comment(value))])
  })
}

fn encode_messages_dict(
  messages: dict.Dict(String, types.DirectMessage),
) -> Json {
  messages
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", encode_message(value))])
  })
}

fn encode_user_messages_dict(
  user_messages: dict.Dict(String, List(String)),
) -> Json {
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

fn encode_int_dict(dict_data: dict.Dict(String, Int)) -> Json {
  dict_data
  |> dict.to_list
  |> json.array(fn(pair) {
    let #(key, value) = pair
    json.object([#("key", json.string(key)), #("value", json.int(value))])
  })
}
