// Write coordinator + read shards architecture

import engine
import engine_actor
import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/result
import types.{type CommentId, type PostId, type SubredditId, type UserId}

// Controls number of parallel read shards
pub type RouterConfig {
  RouterConfig(num_read_actors: Int)
}

// References to all active shards
pub type RouterState {
  RouterState(
    write_actor: process.Subject(engine_actor.Message),
    feed_actor: process.Subject(engine_actor.Message),
    user_actor: process.Subject(engine_actor.Message),
    misc_actor: process.Subject(engine_actor.Message),
  )
}

// Client requests that get routed to shards
pub type RouterMessage {
  RegisterAccount(
    username: String,
    public_key: String,
    private_key: String,
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

  GetFeed(
    user_id: UserId,
    reply: process.Subject(Result(List(types.Post), String)),
  )

  GetPost(post_id: PostId, reply: process.Subject(Result(types.Post, String)))

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
  GetPublicKey(user_id: UserId, reply: process.Subject(Result(String, String)))

  SendDirectMessage(
    sender_id: UserId,
    recipient_id: UserId,
    content: String,
    reply: process.Subject(Result(types.MessageId, String)),
  )

  GetDirectMessages(
    user_id: UserId,
    reply: process.Subject(Result(List(types.DirectMessage), String)),
  )

  SearchSubreddits(
    query: String,
    limit: Int,
    reply: process.Subject(Result(List(types.Subreddit), String)),
  )

  GetStats(reply: process.Subject(engine.EngineStats))

  Shutdown
}

// Get feed/post actor for heavy read operations
fn get_feed_actor(state: RouterState) -> process.Subject(engine_actor.Message) {
  // Reload from disk with TTL check
  let _ = engine_actor.reload_from_disk(state.feed_actor)
  state.feed_actor
}

fn get_user_actor(state: RouterState) -> process.Subject(engine_actor.Message) {
  // Reload from disk with TTL check
  let _ = engine_actor.reload_from_disk(state.user_actor)
  state.user_actor
}

fn get_misc_actor(state: RouterState) -> process.Subject(engine_actor.Message) {
  // Reload from disk with TTL check
  let _ = engine_actor.reload_from_disk(state.misc_actor)
  state.misc_actor
}

fn handle_message(
  state: RouterState,
  message: RouterMessage,
) -> actor.Next(RouterState, RouterMessage) {
  case message {
    RegisterAccount(username, public_key, private_key, client) -> {
      // Write operation: write actor saves to disk, reads will refresh from disk
      let result =
        engine_actor.register_account(
          state.write_actor,
          username,
          public_key,
          private_key,
        )
      process.send(client, result)
      actor.continue(state)
    }

    CreateSubreddit(name, description, creator_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.create_subreddit(
          state.write_actor,
          name,
          description,
          creator_id,
        )
      process.send(client, result)
      actor.continue(state)
    }

    JoinSubreddit(user_id, subreddit_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.join_subreddit(state.write_actor, user_id, subreddit_id)
      process.send(client, result)
      actor.continue(state)
    }

    LeaveSubreddit(user_id, subreddit_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.leave_subreddit(state.write_actor, user_id, subreddit_id)
      process.send(client, result)
      actor.continue(state)
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
      // Write operation: write actor saves to disk
      let result =
        engine_actor.create_post(
          state.write_actor,
          title,
          content,
          author_id,
          subreddit_id,
          is_repost,
          original_post_id,
          original_author_id,
          original_subreddit_id,
        )
      process.send(client, result)
      actor.continue(state)
    }

    CreateComment(content, author_id, post_id, parent_comment_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.create_comment(
          state.write_actor,
          content,
          author_id,
          post_id,
          parent_comment_id,
        )
      process.send(client, result)
      actor.continue(state)
    }

    UpvotePost(post_id, user_id, client) -> {
      // Write operation: write actor saves to disk
      let result = engine_actor.upvote_post(state.write_actor, post_id, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    DownvotePost(post_id, user_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.downvote_post(state.write_actor, post_id, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    UpvoteComment(comment_id, user_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.upvote_comment(state.write_actor, comment_id, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    DownvoteComment(comment_id, user_id, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.downvote_comment(state.write_actor, comment_id, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetFeed(user_id, client) -> {
      // Read operation: use feed actor (heavy load)
      let read_actor = get_feed_actor(state)
      let result = engine_actor.get_feed(read_actor, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetPost(post_id, client) -> {
      // Read operation: use feed actor (heavy load)
      let read_actor = get_feed_actor(state)
      let result = engine_actor.get_post(read_actor, post_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetAccount(user_id, client) -> {
      // Read operation: use user actor (medium load)
      let read_actor = get_user_actor(state)
      let result = engine_actor.get_account(read_actor, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetAccountByUsername(username, client) -> {
      // Read operation: use user actor (medium load)
      let read_actor = get_user_actor(state)
      let result = engine_actor.get_account_by_username(read_actor, username)
      process.send(client, result)
      actor.continue(state)
    }

    GetComments(comment_ids, client) -> {
      // Read operation: use misc actor (light load)
      let read_actor = get_misc_actor(state)
      let comments = engine_actor.get_comments(read_actor, comment_ids)
      process.send(client, comments)
      actor.continue(state)
    }

    GetSubreddit(subreddit_id, client) -> {
      // Read operation: use feed actor (often viewed with posts)
      let read_actor = get_feed_actor(state)
      let result = engine_actor.get_subreddit(read_actor, subreddit_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetUserKarma(user_id, client) -> {
      // Read operation: use user actor
      let read_actor = get_user_actor(state)
      let result = engine_actor.get_user_karma(read_actor, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    GetPublicKey(user_id, client) -> {
      // Read operation: use user actor
      let read_actor = get_user_actor(state)
      let result = engine_actor.get_public_key(read_actor, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    SendDirectMessage(sender_id, recipient_id, content, client) -> {
      // Write operation: write actor saves to disk
      let result =
        engine_actor.send_direct_message(
          state.write_actor,
          sender_id,
          recipient_id,
          content,
        )
      process.send(client, result)
      actor.continue(state)
    }

    GetDirectMessages(user_id, client) -> {
      // Read operation: use misc actor (light load)
      let read_actor = get_misc_actor(state)
      let result = engine_actor.get_direct_messages(read_actor, user_id)
      process.send(client, result)
      actor.continue(state)
    }

    SearchSubreddits(query, limit, client) -> {
      // Read operation: use misc actor (light load)
      let read_actor = get_misc_actor(state)
      let result = engine_actor.search_subreddits(read_actor, query, limit)
      process.send(client, result)
      actor.continue(state)
    }

    GetStats(client) -> {
      // Read from write actor for consistency
      let stats = engine_actor.get_stats(state.write_actor)
      process.send(client, stats)
      actor.continue(state)
    }

    Shutdown -> {
      // Shutdown write actor and all specialized read actors
      engine_actor.shutdown(state.write_actor)
      engine_actor.shutdown(state.feed_actor)
      engine_actor.shutdown(state.user_actor)
      engine_actor.shutdown(state.misc_actor)
      actor.stop()
    }
  }
}

// Start the router with write actor and specialized read actors
pub fn start(
  _config: RouterConfig,
) -> Result(process.Subject(RouterMessage), actor.StartError) {
  let assert Ok(write_actor) = engine_actor.start("Write shard")
  let assert Ok(feed_actor) = engine_actor.start("Feed shard")
  let assert Ok(user_actor) = engine_actor.start("User shard")
  let assert Ok(misc_actor) = engine_actor.start("Misc shard")

  let initial_state =
    RouterState(
      write_actor: write_actor,
      feed_actor: feed_actor,
      user_actor: user_actor,
      misc_actor: misc_actor,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

pub fn register_account(
  router: process.Subject(RouterMessage),
  username: String,
  public_key: String,
  private_key: String,
) -> Result(UserId, String) {
  actor.call(router, 5000, fn(reply) {
    RegisterAccount(username, public_key, private_key, reply)
  })
}

pub fn create_subreddit(
  router: process.Subject(RouterMessage),
  name: String,
  description: String,
  creator_id: UserId,
) -> Result(SubredditId, String) {
  actor.call(router, 5000, fn(reply) {
    CreateSubreddit(name, description, creator_id, reply)
  })
}

pub fn join_subreddit(
  router: process.Subject(RouterMessage),
  user_id: UserId,
  subreddit_id: SubredditId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) {
    JoinSubreddit(user_id, subreddit_id, reply)
  })
}

pub fn leave_subreddit(
  router: process.Subject(RouterMessage),
  user_id: UserId,
  subreddit_id: SubredditId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) {
    LeaveSubreddit(user_id, subreddit_id, reply)
  })
}

pub fn create_post(
  router: process.Subject(RouterMessage),
  title: String,
  content: String,
  author_id: UserId,
  subreddit_id: SubredditId,
  is_repost: Bool,
  original_post_id: option.Option(PostId),
  original_author_id: option.Option(UserId),
  original_subreddit_id: option.Option(SubredditId),
) -> Result(PostId, String) {
  actor.call(router, 5000, fn(reply) {
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
  router: process.Subject(RouterMessage),
  content: String,
  author_id: UserId,
  post_id: PostId,
  parent_comment_id: option.Option(CommentId),
) -> Result(CommentId, String) {
  actor.call(router, 5000, fn(reply) {
    CreateComment(content, author_id, post_id, parent_comment_id, reply)
  })
}

pub fn upvote_post(
  router: process.Subject(RouterMessage),
  post_id: PostId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) { UpvotePost(post_id, user_id, reply) })
}

pub fn downvote_post(
  router: process.Subject(RouterMessage),
  post_id: PostId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) { DownvotePost(post_id, user_id, reply) })
}

pub fn upvote_comment(
  router: process.Subject(RouterMessage),
  comment_id: CommentId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) {
    UpvoteComment(comment_id, user_id, reply)
  })
}

pub fn downvote_comment(
  router: process.Subject(RouterMessage),
  comment_id: CommentId,
  user_id: UserId,
) -> Result(Nil, String) {
  actor.call(router, 5000, fn(reply) {
    DownvoteComment(comment_id, user_id, reply)
  })
}

pub fn get_feed(
  router: process.Subject(RouterMessage),
  user_id: UserId,
) -> Result(List(types.Post), String) {
  actor.call(router, 5000, fn(reply) { GetFeed(user_id, reply) })
}

pub fn get_post(
  router: process.Subject(RouterMessage),
  post_id: PostId,
) -> Result(types.Post, String) {
  actor.call(router, 5000, fn(reply) { GetPost(post_id, reply) })
}

pub fn get_comments(
  router: process.Subject(RouterMessage),
  comment_ids: List(CommentId),
) -> List(types.Comment) {
  actor.call(router, 5000, fn(reply) { GetComments(comment_ids, reply) })
}

pub fn get_account(
  router: process.Subject(RouterMessage),
  user_id: UserId,
) -> Result(types.Account, String) {
  actor.call(router, 5000, fn(reply) { GetAccount(user_id, reply) })
}

pub fn get_account_by_username(
  router: process.Subject(RouterMessage),
  username: String,
) -> Result(types.Account, String) {
  actor.call(router, 5000, fn(reply) { GetAccountByUsername(username, reply) })
}

pub fn get_subreddit(
  router: process.Subject(RouterMessage),
  subreddit_id: SubredditId,
) -> Result(types.Subreddit, String) {
  actor.call(router, 5000, fn(reply) { GetSubreddit(subreddit_id, reply) })
}

pub fn get_user_karma(
  router: process.Subject(RouterMessage),
  user_id: UserId,
) -> Result(Int, String) {
  actor.call(router, 5000, fn(reply) { GetUserKarma(user_id, reply) })
}

pub fn get_public_key(
  router: process.Subject(RouterMessage),
  user_id: UserId,
) -> Result(String, String) {
  actor.call(router, 5000, fn(reply) { GetPublicKey(user_id, reply) })
}

pub fn send_direct_message(
  router: process.Subject(RouterMessage),
  sender_id: UserId,
  recipient_id: UserId,
  content: String,
) -> Result(types.MessageId, String) {
  actor.call(router, 5000, fn(reply) {
    SendDirectMessage(sender_id, recipient_id, content, reply)
  })
}

pub fn get_direct_messages(
  router: process.Subject(RouterMessage),
  user_id: UserId,
) -> Result(List(types.DirectMessage), String) {
  actor.call(router, 5000, fn(reply) { GetDirectMessages(user_id, reply) })
}

pub fn search_subreddits(
  router: process.Subject(RouterMessage),
  query: String,
  limit: Int,
) -> Result(List(types.Subreddit), String) {
  actor.call(router, 5000, fn(reply) { SearchSubreddits(query, limit, reply) })
}

pub fn get_stats(router: process.Subject(RouterMessage)) -> engine.EngineStats {
  actor.call(router, 5000, fn(reply) { GetStats(reply) })
}

pub fn shutdown(router: process.Subject(RouterMessage)) -> Nil {
  process.send(router, Shutdown)
}
