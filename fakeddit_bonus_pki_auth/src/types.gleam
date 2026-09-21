import gleam/dict.{type Dict}
import gleam/option.{type Option}

pub type UserId =
  String

pub type SubredditId =
  String

pub type PostId =
  String

pub type CommentId =
  String

pub type MessageId =
  String

pub type Account {
  Account(
    id: UserId,
    username: String,
    karma: Int,
    joined_subreddits: List(SubredditId),
    created_at: Int,
    public_key: String,
    private_key: String,
  )
}

pub type Subreddit {
  Subreddit(
    id: SubredditId,
    name: String,
    description: String,
    members: List(UserId),
    posts: List(PostId),
    created_at: Int,
  )
}

pub type Post {
  Post(
    id: PostId,
    author_id: UserId,
    subreddit_id: SubredditId,
    title: String,
    content: String,
    upvotes: Int,
    downvotes: Int,
    comments: List(CommentId),
    created_at: Int,
    is_repost: Bool,
    original_post_id: Option(PostId),
    original_author_id: Option(UserId),
    original_subreddit_id: Option(SubredditId),
    signature: String,
  )
}

pub type Comment {
  Comment(
    id: CommentId,
    author_id: UserId,
    post_id: PostId,
    parent_comment_id: Option(CommentId),
    content: String,
    upvotes: Int,
    downvotes: Int,
    replies: List(CommentId),
    created_at: Int,
  )
}

pub type DirectMessage {
  DirectMessage(
    id: MessageId,
    from_user_id: UserId,
    to_user_id: UserId,
    content: String,
    created_at: Int,
    is_read: Bool,
  )
}

pub type EngineState {
  EngineState(
    accounts: Dict(UserId, Account),
    subreddits: Dict(SubredditId, Subreddit),
    posts: Dict(PostId, Post),
    comments: Dict(CommentId, Comment),
    direct_messages: Dict(MessageId, DirectMessage),
    user_messages: Dict(UserId, List(MessageId)),
    user_karma_cache: Dict(UserId, Int),
  )
}
