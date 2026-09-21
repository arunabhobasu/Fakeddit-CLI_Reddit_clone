import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import types.{
  type Account, type Comment, type CommentId, type DirectMessage, type MessageId,
  type Post, type PostId, type Subreddit, type SubredditId, type UserId, Account,
  Comment, DirectMessage, Post, Subreddit,
}
import utils

// Snapshot of system activity
pub type EngineStats {
  EngineStats(
    total_accounts: Int,
    total_subreddits: Int,
    total_posts: Int,
    total_comments: Int,
    total_messages: Int,
  )
}

pub type State {
  State(
    accounts: dict.Dict(UserId, Account),
    username_to_userid: dict.Dict(String, UserId),
    // Fast username lookups without scanning all accounts
    subreddits: dict.Dict(SubredditId, Subreddit),
    posts: dict.Dict(PostId, Post),
    comments: dict.Dict(CommentId, Comment),
    direct_messages: dict.Dict(MessageId, DirectMessage),
    user_messages: dict.Dict(UserId, List(MessageId)),
    user_karma_cache: dict.Dict(UserId, Int),
    // Avoid recalculating karma on every request
    last_reload_time: Int,
    // Track when state was last loaded for TTL
  )
}

// Fresh state with no users or content
pub fn initial_state() -> State {
  State(
    accounts: dict.new(),
    username_to_userid: dict.new(),
    subreddits: dict.new(),
    posts: dict.new(),
    comments: dict.new(),
    direct_messages: dict.new(),
    user_messages: dict.new(),
    user_karma_cache: dict.new(),
    last_reload_time: 0,
  )
}

// Create new user, checking username isn't taken
pub fn register_account(
  state: State,
  username: String,
) -> #(State, Result(UserId, String)) {
  case dict.get(state.username_to_userid, username) {
    Ok(_) -> #(state, Error("Username already taken"))
    Error(_) -> {
      let user_id = utils.generate_id("user")
      let account =
        Account(
          id: user_id,
          username: username,
          karma: 0,
          joined_subreddits: [],
          created_at: utils.get_timestamp(),
        )
      let new_state =
        State(
          ..state,
          accounts: dict.insert(state.accounts, user_id, account),
          username_to_userid: dict.insert(
            state.username_to_userid,
            username,
            user_id,
          ),
          user_karma_cache: dict.insert(state.user_karma_cache, user_id, 0),
        )
      #(new_state, Ok(user_id))
    }
  }
}

// Create community with founder as first member
pub fn create_subreddit(
  state: State,
  name: String,
  description: String,
  creator_id: UserId,
) -> #(State, Result(SubredditId, String)) {
  case dict.get(state.accounts, creator_id) {
    Error(_) -> #(state, Error("User not found"))
    Ok(account) -> {
      let subreddit_id = utils.generate_id("sub")
      let subreddit =
        Subreddit(
          id: subreddit_id,
          name: name,
          description: description,
          members: [creator_id],
          posts: [],
          created_at: utils.get_timestamp(),
        )
      let updated_account =
        Account(..account, joined_subreddits: [
          subreddit_id,
          ..account.joined_subreddits
        ])
      let new_state =
        State(
          ..state,
          subreddits: dict.insert(state.subreddits, subreddit_id, subreddit),
          accounts: dict.insert(state.accounts, creator_id, updated_account),
        )
      #(new_state, Ok(subreddit_id))
    }
  }
}

// Add user to community membership
pub fn join_subreddit(
  state: State,
  user_id: UserId,
  subreddit_id: SubredditId,
) -> #(State, Result(Nil, String)) {
  case
    dict.get(state.accounts, user_id),
    dict.get(state.subreddits, subreddit_id)
  {
    Ok(account), Ok(subreddit) -> {
      case list.contains(subreddit.members, user_id) {
        True -> #(state, Ok(Nil))
        // Already joined - safe to call multiple times
        False -> {
          let updated_subreddit =
            Subreddit(..subreddit, members: [user_id, ..subreddit.members])
          let updated_account =
            Account(..account, joined_subreddits: [
              subreddit_id,
              ..account.joined_subreddits
            ])
          let new_state =
            State(
              ..state,
              subreddits: dict.insert(
                state.subreddits,
                subreddit_id,
                updated_subreddit,
              ),
              accounts: dict.insert(state.accounts, user_id, updated_account),
            )
          #(new_state, Ok(Nil))
        }
      }
    }
    _, _ -> #(state, Error("User or subreddit not found"))
  }
}

// Remove user from community
pub fn leave_subreddit(
  state: State,
  user_id: UserId,
  subreddit_id: SubredditId,
) -> #(State, Result(Nil, String)) {
  case
    dict.get(state.accounts, user_id),
    dict.get(state.subreddits, subreddit_id)
  {
    Ok(account), Ok(subreddit) -> {
      case list.contains(subreddit.members, user_id) {
        False -> #(state, Error("Not a member"))
        True -> {
          let updated_subreddit =
            Subreddit(
              ..subreddit,
              members: list.filter(subreddit.members, fn(id) { id != user_id }),
            )
          let updated_account =
            Account(
              ..account,
              joined_subreddits: list.filter(account.joined_subreddits, fn(id) {
                id != subreddit_id
              }),
            )
          let new_state =
            State(
              ..state,
              subreddits: dict.insert(
                state.subreddits,
                subreddit_id,
                updated_subreddit,
              ),
              accounts: dict.insert(state.accounts, user_id, updated_account),
            )
          #(new_state, Ok(Nil))
        }
      }
    }
    _, _ -> #(state, Error("User or subreddit not found"))
  }
}

// Publish content to a community
pub fn create_post(
  state: State,
  author_id: UserId,
  subreddit_id: SubredditId,
  title: String,
  content: String,
  is_repost: Bool,
  original_post_id: option.Option(PostId),
  original_author_id: option.Option(UserId),
  original_subreddit_id: option.Option(SubredditId),
) -> #(State, Result(PostId, String)) {
  case
    dict.get(state.accounts, author_id),
    dict.get(state.subreddits, subreddit_id)
  {
    Ok(_), Ok(subreddit) -> {
      let post_id = utils.generate_id("post")
      let post =
        Post(
          id: post_id,
          author_id: author_id,
          subreddit_id: subreddit_id,
          title: title,
          content: content,
          upvotes: 0,
          downvotes: 0,
          comments: [],
          created_at: utils.get_timestamp(),
          is_repost: is_repost,
          original_post_id: original_post_id,
          original_author_id: original_author_id,
          original_subreddit_id: original_subreddit_id,
        )
      let updated_subreddit =
        Subreddit(..subreddit, posts: [post_id, ..subreddit.posts])
      let new_state =
        State(
          ..state,
          posts: dict.insert(state.posts, post_id, post),
          subreddits: dict.insert(
            state.subreddits,
            subreddit_id,
            updated_subreddit,
          ),
        )
      #(new_state, Ok(post_id))
    }
    _, _ -> #(state, Error("User or subreddit not found"))
  }
}

// Reply to post or another comment
pub fn create_comment(
  state: State,
  author_id: UserId,
  post_id: PostId,
  parent_comment_id: option.Option(CommentId),
  content: String,
) -> #(State, Result(CommentId, String)) {
  case dict.get(state.accounts, author_id), dict.get(state.posts, post_id) {
    Ok(_), Ok(post) -> {
      let comment_id = utils.generate_id("comment")
      let comment =
        Comment(
          id: comment_id,
          author_id: author_id,
          post_id: post_id,
          parent_comment_id: parent_comment_id,
          content: content,
          upvotes: 0,
          downvotes: 0,
          replies: [],
          created_at: utils.get_timestamp(),
        )

      let updated_post = Post(..post, comments: [comment_id, ..post.comments])
      let new_comments = dict.insert(state.comments, comment_id, comment)

      // Update parent comment if this is a reply
      let new_comments = case parent_comment_id {
        Some(parent_id) ->
          case dict.get(new_comments, parent_id) {
            Ok(parent_comment) -> {
              let updated_parent =
                Comment(..parent_comment, replies: [
                  comment_id,
                  ..parent_comment.replies
                ])
              dict.insert(new_comments, parent_id, updated_parent)
            }
            Error(_) -> new_comments
          }
        None -> new_comments
      }

      let new_state =
        State(
          ..state,
          comments: new_comments,
          posts: dict.insert(state.posts, post_id, updated_post),
        )
      #(new_state, Ok(comment_id))
    }
    _, _ -> #(state, Error("User or post not found"))
  }
}

// Increase post score and author's karma
pub fn upvote_post(
  state: State,
  user_id: UserId,
  post_id: PostId,
) -> #(State, Result(Nil, String)) {
  case dict.get(state.accounts, user_id), dict.get(state.posts, post_id) {
    Ok(_), Ok(post) -> {
      let updated_post = Post(..post, upvotes: post.upvotes + 1)
      let new_state =
        State(..state, posts: dict.insert(state.posts, post_id, updated_post))
      let new_state = update_karma_cache(new_state, post.author_id, 1)
      #(new_state, Ok(Nil))
    }
    _, _ -> #(state, Error("User or post not found"))
  }
}

// Decrease post score and author's karma
pub fn downvote_post(
  state: State,
  user_id: UserId,
  post_id: PostId,
) -> #(State, Result(Nil, String)) {
  case dict.get(state.accounts, user_id), dict.get(state.posts, post_id) {
    Ok(_), Ok(post) -> {
      let updated_post = Post(..post, downvotes: post.downvotes + 1)
      let new_state =
        State(..state, posts: dict.insert(state.posts, post_id, updated_post))
      let new_state = update_karma_cache(new_state, post.author_id, -1)
      #(new_state, Ok(Nil))
    }
    _, _ -> #(state, Error("User or post not found"))
  }
}

// Increase comment score and author's karma
pub fn upvote_comment(
  state: State,
  user_id: UserId,
  comment_id: CommentId,
) -> #(State, Result(Nil, String)) {
  case dict.get(state.accounts, user_id), dict.get(state.comments, comment_id) {
    Ok(_), Ok(comment) -> {
      let updated_comment = Comment(..comment, upvotes: comment.upvotes + 1)
      let new_state =
        State(
          ..state,
          comments: dict.insert(state.comments, comment_id, updated_comment),
        )
      let new_state = update_karma_cache(new_state, comment.author_id, 1)
      #(new_state, Ok(Nil))
    }
    _, _ -> #(state, Error("User or comment not found"))
  }
}

// Decrease comment score and author's karma
pub fn downvote_comment(
  state: State,
  user_id: UserId,
  comment_id: CommentId,
) -> #(State, Result(Nil, String)) {
  case dict.get(state.accounts, user_id), dict.get(state.comments, comment_id) {
    Ok(_), Ok(comment) -> {
      let updated_comment = Comment(..comment, downvotes: comment.downvotes + 1)
      let new_state =
        State(
          ..state,
          comments: dict.insert(state.comments, comment_id, updated_comment),
        )
      let new_state = update_karma_cache(new_state, comment.author_id, -1)
      #(new_state, Ok(Nil))
    }
    _, _ -> #(state, Error("User or comment not found"))
  }
}

// Returns posts from joined subreddits, sorted by score
pub fn get_feed(
  state: State,
  user_id: UserId,
  limit: Int,
) -> #(State, Result(List(Post), String)) {
  case dict.get(state.accounts, user_id) {
    Error(_) -> #(state, Error("User not found"))
    Ok(account) -> {
      let posts =
        account.joined_subreddits
        |> list.flat_map(fn(subreddit_id) {
          case dict.get(state.subreddits, subreddit_id) {
            Ok(subreddit) ->
              subreddit.posts
              |> list.filter_map(fn(post_id) { dict.get(state.posts, post_id) })
            Error(_) -> []
          }
        })
        |> list.sort(fn(a, b) {
          // Sort by net score, highest first
          let score_a = a.upvotes - a.downvotes
          let score_b = b.upvotes - b.downvotes
          int.compare(score_b, score_a)
        })
        |> list.take(limit)

      #(state, Ok(posts))
    }
  }
}

// Fetch single post by ID
pub fn get_post(state: State, post_id: PostId) -> #(State, Result(Post, String)) {
  case dict.get(state.posts, post_id) {
    Ok(post) -> #(state, Ok(post))
    Error(_) -> #(state, Error("Post not found"))
  }
}

// Fetch multiple comments at once
pub fn get_comments(state: State, comment_ids: List(CommentId)) -> List(Comment) {
  comment_ids
  |> list.filter_map(fn(comment_id) { dict.get(state.comments, comment_id) })
}

// Fetch user profile by ID
pub fn get_account(
  state: State,
  user_id: UserId,
) -> #(State, Result(Account, String)) {
  case dict.get(state.accounts, user_id) {
    Ok(account) -> #(state, Ok(account))
    Error(_) -> #(state, Error("Account not found"))
  }
}

// Lookup user by display name
pub fn get_account_by_username(
  state: State,
  username: String,
) -> #(State, Result(Account, String)) {
  case dict.get(state.username_to_userid, username) {
    Ok(user_id) -> get_account(state, user_id)
    Error(_) -> #(state, Error("Username not found"))
  }
}

// Fetch community details
pub fn get_subreddit(
  state: State,
  subreddit_id: SubredditId,
) -> #(State, Result(Subreddit, String)) {
  case dict.get(state.subreddits, subreddit_id) {
    Ok(subreddit) -> #(state, Ok(subreddit))
    Error(_) -> #(state, Error("Subreddit not found"))
  }
}

// Private message between users
pub fn send_direct_message(
  state: State,
  from_user_id: UserId,
  to_user_id: UserId,
  content: String,
) -> #(State, Result(MessageId, String)) {
  case
    dict.get(state.accounts, from_user_id),
    dict.get(state.accounts, to_user_id)
  {
    Ok(_), Ok(_) -> {
      let message_id = utils.generate_id("msg")
      let message =
        DirectMessage(
          id: message_id,
          from_user_id: from_user_id,
          to_user_id: to_user_id,
          content: content,
          created_at: utils.get_timestamp(),
          is_read: False,
        )

      // Add message to recipient's message list
      let recipient_msg_list =
        dict.get(state.user_messages, to_user_id)
        |> result.unwrap([])

      // Add message to sender's message list
      let sender_msg_list =
        dict.get(state.user_messages, from_user_id)
        |> result.unwrap([])

      let new_state =
        State(
          ..state,
          direct_messages: dict.insert(
            state.direct_messages,
            message_id,
            message,
          ),
          user_messages: state.user_messages
            |> dict.insert(to_user_id, [message_id, ..recipient_msg_list])
            |> dict.insert(from_user_id, [message_id, ..sender_msg_list]),
        )
      #(new_state, Ok(message_id))
    }
    _, _ -> #(state, Error("User not found"))
  }
}

// Fetch user's inbox (most recent first)
pub fn get_direct_messages(
  state: State,
  user_id: UserId,
) -> #(State, Result(List(DirectMessage), String)) {
  case dict.get(state.accounts, user_id) {
    Error(_) -> #(state, Error("User not found"))
    Ok(_) -> {
      let message_ids =
        dict.get(state.user_messages, user_id) |> result.unwrap([])
      let messages =
        message_ids
        |> list.filter_map(fn(msg_id) {
          dict.get(state.direct_messages, msg_id)
        })
        |> list.sort(fn(a, b) { int.compare(b.created_at, a.created_at) })

      #(state, Ok(messages))
    }
  }
}

// System-wide activity metrics
pub fn get_stats(state: State) -> EngineStats {
  EngineStats(
    total_accounts: dict.size(state.accounts),
    total_subreddits: dict.size(state.subreddits),
    total_posts: dict.size(state.posts),
    total_comments: dict.size(state.comments),
    total_messages: dict.size(state.direct_messages),
  )
}

// Total upvotes minus downvotes
pub fn get_user_karma(state: State, user_id: UserId) -> Result(Int, String) {
  case dict.get(state.user_karma_cache, user_id) {
    Ok(karma) -> Ok(karma)
    Error(_) -> Error("User not found")
  }
}

// Find communities by name match
pub fn search_subreddits(
  state: State,
  query: String,
  limit: Int,
) -> Result(List(Subreddit), String) {
  let lowercase_query = string.lowercase(query)

  let matching_subreddits =
    dict.values(state.subreddits)
    |> list.filter(fn(subreddit) {
      string.contains(string.lowercase(subreddit.name), lowercase_query)
      || string.contains(
        string.lowercase(subreddit.description),
        lowercase_query,
      )
    })
    |> list.take(limit)

  Ok(matching_subreddits)
}

// Updates user karma cache with delta value
fn update_karma_cache(state: State, user_id: UserId, delta: Int) -> State {
  let current_karma =
    dict.get(state.user_karma_cache, user_id) |> result.unwrap(0)
  let new_karma = current_karma + delta
  State(
    ..state,
    user_karma_cache: dict.insert(state.user_karma_cache, user_id, new_karma),
  )
}
