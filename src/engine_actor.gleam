import engine
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import persistence
import types.{
  type CommentId, type DirectMessage, type MessageId, type Post, type PostId,
  type Subreddit, type SubredditId, type UserId,
}
import utils

// All operations the engine can perform
pub type Message {
  RegisterAccount(
    username: String,
    reply: process.Subject(Result(UserId, String)),
  )

  CreateSubreddit(
    name: String,
    description: String,
    creator_id: UserId,
    reply: process.Subject(Result(SubredditId, String)),
  )
  JoinSubreddit(
    user_id: UserId,
    subreddit_id: SubredditId,
    reply: process.Subject(Result(Nil, String)),
  )
  LeaveSubreddit(
    user_id: UserId,
    subreddit_id: SubredditId,
    reply: process.Subject(Result(Nil, String)),
  )

  CreatePost(
    title: String,
    content: String,
    author_id: UserId,
    subreddit_id: SubredditId,
    is_repost: Bool,
    original_post_id: option.Option(PostId),
    original_author_id: option.Option(UserId),
    original_subreddit_id: option.Option(SubredditId),
    reply: process.Subject(Result(PostId, String)),
  )
  CreateComment(
    content: String,
    author_id: UserId,
    post_id: PostId,
    parent_comment_id: option.Option(CommentId),
    reply: process.Subject(Result(CommentId, String)),
  )

  UpvotePost(
    post_id: PostId,
    user_id: UserId,
    reply: process.Subject(Result(Nil, String)),
  )
  DownvotePost(
    post_id: PostId,
    user_id: UserId,
    reply: process.Subject(Result(Nil, String)),
  )
  UpvoteComment(
    comment_id: CommentId,
    user_id: UserId,
    reply: process.Subject(Result(Nil, String)),
  )
  DownvoteComment(
    comment_id: CommentId,
    user_id: UserId,
    reply: process.Subject(Result(Nil, String)),
  )

  GetFeed(user_id: UserId, reply: process.Subject(Result(List(Post), String)))
  GetPost(post_id: PostId, reply: process.Subject(Result(Post, String)))
  GetComments(
    comment_ids: List(CommentId),
    reply: process.Subject(List(types.Comment)),
  )
  GetAccount(
    user_id: UserId,
    reply: process.Subject(Result(types.Account, String)),
  )
  GetAccountByUsername(
    username: String,
    reply: process.Subject(Result(types.Account, String)),
  )
  GetSubreddit(
    subreddit_id: SubredditId,
    reply: process.Subject(Result(types.Subreddit, String)),
  )
  GetUserKarma(user_id: UserId, reply: process.Subject(Result(Int, String)))

  // Direct messaging
  SendDirectMessage(
    sender_id: UserId,
    recipient_id: UserId,
    content: String,
    reply: process.Subject(Result(MessageId, String)),
  )
  GetDirectMessages(
    user_id: UserId,
    reply: process.Subject(Result(List(DirectMessage), String)),
  )
  SearchSubreddits(
    query: String,
    limit: Int,
    reply: process.Subject(Result(List(Subreddit), String)),
  )

  GetStats(reply: process.Subject(engine.EngineStats))
  ReloadFromDisk(reply: process.Subject(Result(Nil, String)))
  Shutdown
}

// Strip runtime data before saving to disk
fn to_engine_state(state: engine.State) -> types.EngineState {
  types.EngineState(
    accounts: state.accounts,
    subreddits: state.subreddits,
    posts: state.posts,
    comments: state.comments,
    direct_messages: state.direct_messages,
    user_messages: state.user_messages,
    user_karma_cache: state.user_karma_cache,
  )
}

// Write operations always save to disk (source of truth)
fn save_and_continue(state: engine.State) -> actor.Next(engine.State, Message) {
  let engine_state = to_engine_state(state)
  let _ = persistence.save_state(engine_state)
  actor.continue(state)
}

// Route incoming requests to engine functions
fn handle_message(
  state: engine.State,
  message: Message,
) -> actor.Next(engine.State, Message) {
  case message {
    RegisterAccount(username, client) -> {
      let #(new_state, result) = engine.register_account(state, username)
      process.send(client, result)
      save_and_continue(new_state)
    }

    CreateSubreddit(name, description, creator_id, client) -> {
      let #(new_state, result) =
        engine.create_subreddit(state, name, description, creator_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    JoinSubreddit(user_id, subreddit_id, client) -> {
      let #(new_state, result) =
        engine.join_subreddit(state, user_id, subreddit_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    LeaveSubreddit(user_id, subreddit_id, client) -> {
      let #(new_state, result) =
        engine.leave_subreddit(state, user_id, subreddit_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    CreatePost(
      title,
      content,
      author_id,
      subreddit_id,
      is_repost,
      original_post_id,
      original_author_id,
      original_subreddit_id,
      client,
    ) -> {
      let #(new_state, result) =
        engine.create_post(
          state,
          author_id,
          subreddit_id,
          title,
          content,
          is_repost,
          original_post_id,
          original_author_id,
          original_subreddit_id,
        )
      process.send(client, result)
      save_and_continue(new_state)
    }

    CreateComment(content, author_id, post_id, parent_comment_id, client) -> {
      let #(new_state, result) =
        engine.create_comment(
          state,
          author_id,
          post_id,
          parent_comment_id,
          content,
        )
      process.send(client, result)
      save_and_continue(new_state)
    }

    UpvotePost(post_id, user_id, client) -> {
      let #(new_state, result) = engine.upvote_post(state, user_id, post_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    DownvotePost(post_id, user_id, client) -> {
      let #(new_state, result) = engine.downvote_post(state, user_id, post_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    UpvoteComment(comment_id, user_id, client) -> {
      let #(new_state, result) =
        engine.upvote_comment(state, user_id, comment_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    DownvoteComment(comment_id, user_id, client) -> {
      let #(new_state, result) =
        engine.downvote_comment(state, user_id, comment_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetFeed(user_id, client) -> {
      let #(new_state, result) = engine.get_feed(state, user_id, 100)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetPost(post_id, client) -> {
      let #(new_state, result) = engine.get_post(state, post_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetAccount(user_id, client) -> {
      let #(new_state, result) = engine.get_account(state, user_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetAccountByUsername(username, client) -> {
      let #(new_state, result) = engine.get_account_by_username(state, username)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetComments(comment_ids, client) -> {
      let comments = engine.get_comments(state, comment_ids)
      process.send(client, comments)
      actor.continue(state)
    }

    GetSubreddit(subreddit_id, client) -> {
      let #(new_state, result) = engine.get_subreddit(state, subreddit_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetUserKarma(user_id, client) -> {
      let result = engine.get_user_karma(state, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    SendDirectMessage(sender_id, recipient_id, content, client) -> {
      let #(new_state, result) =
        engine.send_direct_message(state, sender_id, recipient_id, content)
      process.send(client, result)
      save_and_continue(new_state)
    }

    GetDirectMessages(user_id, client) -> {
      let #(new_state, result) = engine.get_direct_messages(state, user_id)
      process.send(client, result)
      save_and_continue(new_state)
    }

    SearchSubreddits(query, limit, client) -> {
      let result = engine.search_subreddits(state, query, limit)
      process.send(client, result)
      actor.continue(state)
    }

    GetStats(client) -> {
      let stats = engine.get_stats(state)
      process.send(client, stats)
      actor.continue(state)
    }

    ReloadFromDisk(client) -> {
      // TTL cache: only reload from disk if >500ms elapsed
      let current_time = utils.get_timestamp()
      let time_since_reload = current_time - state.last_reload_time

      case time_since_reload > 500 {
        False -> {
          process.send(client, Ok(Nil))
          actor.continue(state)
        }
        True -> {
          case persistence.load_state("") {
            // Empty name - internal reload, not startup
            Ok(persisted_state) -> {
              let username_map = build_username_map(persisted_state.accounts)
              let new_state =
                engine.State(
                  accounts: persisted_state.accounts,
                  username_to_userid: username_map,
                  subreddits: persisted_state.subreddits,
                  posts: persisted_state.posts,
                  comments: persisted_state.comments,
                  direct_messages: persisted_state.direct_messages,
                  user_messages: persisted_state.user_messages,
                  user_karma_cache: persisted_state.user_karma_cache,
                  last_reload_time: current_time,
                )
              process.send(client, Ok(Nil))
              actor.continue(new_state)
              // Fresh data from disk, no save needed
            }
            Error(_) -> {
              process.send(client, Error("Failed to reload from disk"))
              actor.continue(state)
            }
          }
        }
      }
    }

    Shutdown -> {
      actor.stop()
    }
  }
}

// Launch actor, loading saved state if available
pub fn start(
  shard_name: String,
) -> Result(process.Subject(Message), actor.StartError) {
  let initial = case persistence.load_state(shard_name) {
    Ok(persisted_state) -> {
      let username_map = build_username_map(persisted_state.accounts)
      // Rebuild index from saved data
      engine.State(
        accounts: persisted_state.accounts,
        username_to_userid: username_map,
        subreddits: persisted_state.subreddits,
        posts: persisted_state.posts,
        comments: persisted_state.comments,
        direct_messages: persisted_state.direct_messages,
        user_messages: persisted_state.user_messages,
        user_karma_cache: persisted_state.user_karma_cache,
        last_reload_time: utils.get_timestamp(),
      )
    }
    Error(_) -> engine.initial_state()
  }

  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

// Index accounts for O(1) username lookups
fn build_username_map(
  accounts: dict.Dict(types.UserId, types.Account),
) -> dict.Dict(String, types.UserId) {
  accounts
  |> dict.to_list()
  |> list.fold(dict.new(), fn(acc, pair) {
    let #(user_id, account) = pair
    dict.insert(acc, account.username, user_id)
  })
}

pub fn register_account(
  engine: process.Subject(Message),
  username: String,
) -> Result(UserId, String) {
  actor.call(engine, 5000, fn(reply) { RegisterAccount(username, reply) })
}

pub fn create_subreddit(
  engine: process.Subject(Message),
  name: String,
  description: String,
  creator_id: UserId,
) -> Result(SubredditId, String) {
  actor.call(engine, 5000, fn(reply) {
    CreateSubreddit(name, description, creator_id, reply)
  })
}

pub fn join_subreddit(
  engine: process.Subject(Message),
  user_id: UserId,
  subreddit_id: SubredditId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) {
    JoinSubreddit(user_id, subreddit_id, reply)
  })
}

pub fn leave_subreddit(
  engine: process.Subject(Message),
  user_id: UserId,
  subreddit_id: SubredditId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) {
    LeaveSubreddit(user_id, subreddit_id, reply)
  })
}

pub fn create_post(
  engine: process.Subject(Message),
  title: String,
  content: String,
  author_id: UserId,
  subreddit_id: SubredditId,
  is_repost: Bool,
  original_post_id: option.Option(PostId),
  original_author_id: option.Option(UserId),
  original_subreddit_id: option.Option(SubredditId),
) -> Result(PostId, String) {
  actor.call(engine, 5000, fn(reply) {
    CreatePost(
      title,
      content,
      author_id,
      subreddit_id,
      is_repost,
      original_post_id,
      original_author_id,
      original_subreddit_id,
      reply,
    )
  })
}

pub fn create_comment(
  engine: process.Subject(Message),
  content: String,
  author_id: UserId,
  post_id: PostId,
  parent_comment_id: option.Option(CommentId),
) -> Result(CommentId, String) {
  actor.call(engine, 5000, CreateComment(
    content,
    author_id,
    post_id,
    parent_comment_id,
    _,
  ))
}

pub fn upvote_post(
  engine: process.Subject(Message),
  post_id: PostId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) { UpvotePost(post_id, user_id, reply) })
}

pub fn downvote_post(
  engine: process.Subject(Message),
  post_id: PostId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) { DownvotePost(post_id, user_id, reply) })
}

pub fn upvote_comment(
  engine: process.Subject(Message),
  comment_id: CommentId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) {
    UpvoteComment(comment_id, user_id, reply)
  })
}

pub fn downvote_comment(
  engine: process.Subject(Message),
  comment_id: CommentId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(engine, 5000, fn(reply) {
    DownvoteComment(comment_id, user_id, reply)
  })
}

pub fn get_feed(
  engine: process.Subject(Message),
  user_id: UserId,
) -> Result(List(Post), String) {
  actor.call(engine, 5000, fn(reply) { GetFeed(user_id, reply) })
}

pub fn get_post(
  engine: process.Subject(Message),
  post_id: PostId,
) -> Result(Post, String) {
  actor.call(engine, 5000, fn(reply) { GetPost(post_id, reply) })
}

pub fn get_account(
  engine: process.Subject(Message),
  user_id: UserId,
) -> Result(types.Account, String) {
  actor.call(engine, 5000, fn(reply) { GetAccount(user_id, reply) })
}

pub fn get_account_by_username(
  engine: process.Subject(Message),
  username: String,
) -> Result(types.Account, String) {
  actor.call(engine, 5000, fn(reply) { GetAccountByUsername(username, reply) })
}

pub fn get_subreddit(
  engine: process.Subject(Message),
  subreddit_id: SubredditId,
) -> Result(types.Subreddit, String) {
  actor.call(engine, 5000, fn(reply) { GetSubreddit(subreddit_id, reply) })
}

pub fn get_comments(
  engine: process.Subject(Message),
  comment_ids: List(CommentId),
) -> List(types.Comment) {
  actor.call(engine, 5000, fn(reply) { GetComments(comment_ids, reply) })
}

pub fn get_user_karma(
  engine: process.Subject(Message),
  user_id: UserId,
) -> Result(Int, String) {
  actor.call(engine, 5000, fn(reply) { GetUserKarma(user_id, reply) })
}

pub fn send_direct_message(
  engine: process.Subject(Message),
  sender_id: UserId,
  recipient_id: UserId,
  content: String,
) -> Result(MessageId, String) {
  actor.call(engine, 5000, fn(reply) {
    SendDirectMessage(sender_id, recipient_id, content, reply)
  })
}

pub fn get_direct_messages(
  engine: process.Subject(Message),
  user_id: UserId,
) -> Result(List(DirectMessage), String) {
  actor.call(engine, 5000, fn(reply) { GetDirectMessages(user_id, reply) })
}

pub fn search_subreddits(
  engine: process.Subject(Message),
  query: String,
  limit: Int,
) -> Result(List(Subreddit), String) {
  actor.call(engine, 5000, fn(reply) { SearchSubreddits(query, limit, reply) })
}

pub fn get_stats(engine: process.Subject(Message)) -> engine.EngineStats {
  actor.call(engine, 5000, fn(reply) { GetStats(reply) })
}

pub fn reload_from_disk(engine: process.Subject(Message)) -> Nil {
  let _ = actor.call(engine, 5000, fn(reply) { ReloadFromDisk(reply) })
  Nil
}

pub fn shutdown(engine: process.Subject(Message)) -> Nil {
  process.send(engine, Shutdown)
}
