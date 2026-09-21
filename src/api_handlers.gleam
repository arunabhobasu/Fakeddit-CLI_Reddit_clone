import api_types
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{None}
import router_actor
import wisp.{type Request, type Response}

// Shared resources for all endpoints
pub type Context {
  Context(router: process.Subject(router_actor.RouterMessage))
}

// Route HTTP requests to handlers
pub fn handle_request(req: Request, ctx: Context) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes()
  use req <- wisp.handle_head(req)

  case wisp.path_segments(req) {
    // Health check
    ["api", "health"] -> health_check(req)

    // Account endpoints
    ["api", "v1", "accounts"] -> handle_accounts(req, ctx)
    ["api", "v1", "accounts", "lookup"] -> handle_account_lookup(req, ctx)
    ["api", "v1", "accounts", user_id] ->
      handle_account_detail(req, ctx, user_id)
    ["api", "v1", "accounts", user_id, "karma"] ->
      handle_karma(req, ctx, user_id)
    ["api", "v1", "accounts", user_id, "feed"] -> handle_feed(req, ctx, user_id)
    ["api", "v1", "accounts", user_id, "messages"] ->
      handle_messages(req, ctx, user_id)

    // Subfakeddit endpoints
    ["api", "v1", "subreddits"] -> handle_subreddits(req, ctx)
    ["api", "v1", "subreddits", "search"] -> handle_search_subreddits(req, ctx)
    ["api", "v1", "subreddits", subreddit_id] ->
      handle_subreddit_detail(req, ctx, subreddit_id)
    ["api", "v1", "subreddits", subreddit_id, "join"] ->
      handle_join_subreddit(req, ctx, subreddit_id)
    ["api", "v1", "subreddits", subreddit_id, "leave"] ->
      handle_leave_subreddit(req, ctx, subreddit_id)
    ["api", "v1", "subreddits", subreddit_id, "posts"] ->
      handle_create_post(req, ctx, subreddit_id)

    // Post endpoints
    ["api", "v1", "posts", post_id] -> handle_post_detail(req, ctx, post_id)
    ["api", "v1", "posts", post_id, "upvote"] ->
      handle_upvote(req, ctx, post_id)
    ["api", "v1", "posts", post_id, "downvote"] ->
      handle_downvote(req, ctx, post_id)
    ["api", "v1", "posts", post_id, "comments"] ->
      handle_create_comment(req, ctx, post_id)

    // Comment endpoints
    ["api", "v1", "comments", comment_id, "upvote"] ->
      handle_comment_upvote(req, ctx, comment_id)
    ["api", "v1", "comments", comment_id, "downvote"] ->
      handle_comment_downvote(req, ctx, comment_id)

    // Catch-all
    _ -> wisp.not_found()
  }
}

fn json_response(status: Int, body: json.Json) -> Response {
  wisp.json_response(json.to_string(body), status)
}

fn get_user_from_request(req: Request) -> Result(String, Nil) {
  request.get_header(req, "x-user-id")
}

fn health_check(_req: Request) -> Response {
  let body =
    json.object([
      #("status", json.string("healthy")),
      #("service", json.string("reddit_clone_api")),
    ])

  json_response(200, body)
}

// POST /api/v1/accounts - Register new account
fn handle_accounts(req: Request, ctx: Context) -> Response {
  case req.method {
    Post -> {
      use json_body <- wisp.require_json(req)

      case decode.run(json_body, api_types.register_account_decoder()) {
        Ok(req_data) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.RegisterAccount(req_data.username, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(user_id)) -> {
              json_response(
                201,
                api_types.encode_success(api_types.encode_id(user_id)),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(400, api_types.encode_error("Invalid request body"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// GET /api/v1/accounts/lookup?username=... - Lookup account by username
fn handle_account_lookup(req: Request, ctx: Context) -> Response {
  case req.method {
    Get -> {
      let query_params = wisp.get_query(req)
      case list.key_find(query_params, "username") {
        Ok(username) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.GetAccountByUsername(username, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(account)) -> {
              json_response(
                200,
                api_types.encode_success(api_types.encode_account(account)),
              )
            }
            Ok(Error(err)) -> {
              json_response(404, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(
            400,
            api_types.encode_error("Missing username parameter"),
          )
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// GET /api/v1/accounts/:user_id - Get account details
fn handle_account_detail(
  req: Request,
  ctx: Context,
  user_id: String,
) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetAccount(user_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(account)) -> {
          json_response(
            200,
            api_types.encode_success(api_types.encode_account(account)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// GET /api/v1/accounts/:user_id/karma - Get user karma
fn handle_karma(req: Request, ctx: Context, user_id: String) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetUserKarma(user_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(karma)) -> {
          json_response(
            200,
            api_types.encode_success(api_types.encode_karma(karma)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// GET /api/v1/accounts/:user_id/feed - Get user's feed
fn handle_feed(req: Request, ctx: Context, user_id: String) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetFeed(user_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(posts)) -> {
          json_response(
            200,
            api_types.encode_success(api_types.encode_posts(posts)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// GET /api/v1/accounts/:user_id/messages - Get user's messages
// POST /api/v1/accounts/:user_id/messages - Send a message
fn handle_messages(req: Request, ctx: Context, user_id: String) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetDirectMessages(user_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(messages)) -> {
          json_response(
            200,
            api_types.encode_success(api_types.encode_messages(messages)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    Post -> {
      use json_body <- wisp.require_json(req)

      case decode.run(json_body, api_types.send_message_decoder()) {
        Ok(req_data) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.SendDirectMessage(
              user_id,
              req_data.to_user_id,
              req_data.content,
              reply,
            ),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(message_id)) -> {
              json_response(
                201,
                api_types.encode_success(api_types.encode_id(message_id)),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(400, api_types.encode_error("Invalid request body"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

// POST /api/v1/subreddits - Create subfakeddit
fn handle_subreddits(req: Request, ctx: Context) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          use json_body <- wisp.require_json(req)

          case decode.run(json_body, api_types.create_subreddit_decoder()) {
            Ok(req_data) -> {
              let reply = process.new_subject()
              process.send(
                ctx.router,
                router_actor.CreateSubreddit(
                  req_data.name,
                  req_data.description,
                  user_id,
                  reply,
                ),
              )

              case process.receive(reply, 5000) {
                Ok(Ok(subreddit_id)) -> {
                  json_response(
                    201,
                    api_types.encode_success(api_types.encode_id(subreddit_id)),
                  )
                }
                Ok(Error(err)) -> {
                  json_response(400, api_types.encode_error(err))
                }
                Error(_) -> {
                  json_response(500, api_types.encode_error("Request timeout"))
                }
              }
            }
            Error(_) -> {
              json_response(400, api_types.encode_error("Invalid request body"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// GET /api/v1/subreddits/search?q=query - Search subfakeddits
fn handle_search_subreddits(req: Request, ctx: Context) -> Response {
  case req.method {
    Get -> {
      let query_params = wisp.get_query(req)

      case list.key_find(query_params, "q") {
        Ok(search_query) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.SearchSubreddits(search_query, 50, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(subreddits)) -> {
              json_response(
                200,
                api_types.encode_success(api_types.encode_subreddits(subreddits)),
              )
            }
            Ok(Error(err)) -> {
              json_response(404, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(
            400,
            api_types.encode_error("Missing search query parameter 'q'"),
          )
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// GET /api/v1/subreddits/:subreddit_id - Get subfakeddit details
fn handle_subreddit_detail(
  req: Request,
  ctx: Context,
  subreddit_id: String,
) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetSubreddit(subreddit_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(subreddit)) -> {
          json_response(
            200,
            api_types.encode_success(api_types.encode_subreddit(subreddit)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// POST /api/v1/subreddits/:subreddit_id/join - Join subfakeddit
fn handle_join_subreddit(
  req: Request,
  ctx: Context,
  subreddit_id: String,
) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.JoinSubreddit(user_id, subreddit_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("joined"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// POST /api/v1/subreddits/:subreddit_id/leave - Leave subfakeddit
fn handle_leave_subreddit(
  req: Request,
  ctx: Context,
  subreddit_id: String,
) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.LeaveSubreddit(user_id, subreddit_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("left"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// GET /api/v1/subreddits/:subreddit_id/posts - Get posts in subfakeddit
// POST /api/v1/subreddits/:subreddit_id/posts - Create post in subfakeddit
fn handle_create_post(
  req: Request,
  ctx: Context,
  subreddit_id: String,
) -> Response {
  case req.method {
    Get -> {
      // Get subreddit to retrieve posts
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetSubreddit(subreddit_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(subreddit)) -> {
          // Get full post details for each post_id
          let posts =
            list.filter_map(subreddit.posts, fn(post_id) {
              let post_reply = process.new_subject()
              process.send(
                ctx.router,
                router_actor.GetPost(post_id, post_reply),
              )
              case process.receive(post_reply, 5000) {
                Ok(Ok(post)) -> Ok(post)
                _ -> Error(Nil)
              }
            })
          json_response(
            200,
            api_types.encode_success(api_types.encode_posts(posts)),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          use json_body <- wisp.require_json(req)

          case decode.run(json_body, api_types.create_post_decoder()) {
            Ok(req_data) -> {
              let reply = process.new_subject()
              process.send(
                ctx.router,
                router_actor.CreatePost(
                  req_data.title,
                  req_data.content,
                  user_id,
                  subreddit_id,
                  False,
                  None,
                  None,
                  None,
                  reply,
                ),
              )

              case process.receive(reply, 5000) {
                Ok(Ok(post_id)) -> {
                  json_response(
                    201,
                    api_types.encode_success(api_types.encode_id(post_id)),
                  )
                }
                Ok(Error(err)) -> {
                  json_response(400, api_types.encode_error(err))
                }
                Error(_) -> {
                  json_response(500, api_types.encode_error("Request timeout"))
                }
              }
            }
            Error(_) -> {
              json_response(400, api_types.encode_error("Invalid request body"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

// GET /api/v1/posts/:post_id - Get post details
fn handle_post_detail(req: Request, ctx: Context, post_id: String) -> Response {
  case req.method {
    Get -> {
      let reply = process.new_subject()
      process.send(ctx.router, router_actor.GetPost(post_id, reply))

      case process.receive(reply, 5000) {
        Ok(Ok(post)) -> {
          // Fetch full comment details
          let comments = router_actor.get_comments(ctx.router, post.comments)
          json_response(
            200,
            api_types.encode_success(api_types.encode_post_with_comments(
              post,
              comments,
            )),
          )
        }
        Ok(Error(err)) -> {
          json_response(404, api_types.encode_error(err))
        }
        Error(_) -> {
          json_response(500, api_types.encode_error("Request timeout"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Get])
  }
}

// POST /api/v1/posts/:post_id/upvote - Upvote a post
fn handle_upvote(req: Request, ctx: Context, post_id: String) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.UpvotePost(post_id, user_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("upvoted"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// POST /api/v1/posts/:post_id/downvote - Downvote a post
fn handle_downvote(req: Request, ctx: Context, post_id: String) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.DownvotePost(post_id, user_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("downvoted"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// POST /api/v1/comments/:comment_id/upvote - Upvote a comment
fn handle_comment_upvote(
  req: Request,
  ctx: Context,
  comment_id: String,
) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.UpvoteComment(comment_id, user_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("upvoted"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// POST /api/v1/comments/:comment_id/downvote - Downvote a comment
fn handle_comment_downvote(
  req: Request,
  ctx: Context,
  comment_id: String,
) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          let reply = process.new_subject()
          process.send(
            ctx.router,
            router_actor.DownvoteComment(comment_id, user_id, reply),
          )

          case process.receive(reply, 5000) {
            Ok(Ok(_)) -> {
              json_response(
                200,
                api_types.encode_success(
                  json.object([#("status", json.string("downvoted"))]),
                ),
              )
            }
            Ok(Error(err)) -> {
              json_response(400, api_types.encode_error(err))
            }
            Error(_) -> {
              json_response(500, api_types.encode_error("Request timeout"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}

// POST /api/v1/posts/:post_id/comments - Create comment on post
fn handle_create_comment(
  req: Request,
  ctx: Context,
  post_id: String,
) -> Response {
  case req.method {
    Post -> {
      case get_user_from_request(req) {
        Ok(user_id) -> {
          use json_body <- wisp.require_json(req)

          case decode.run(json_body, api_types.create_comment_decoder()) {
            Ok(req_data) -> {
              let reply = process.new_subject()
              process.send(
                ctx.router,
                router_actor.CreateComment(
                  req_data.content,
                  user_id,
                  post_id,
                  req_data.parent_comment_id,
                  reply,
                ),
              )

              case process.receive(reply, 5000) {
                Ok(Ok(comment_id)) -> {
                  json_response(
                    201,
                    api_types.encode_success(api_types.encode_id(comment_id)),
                  )
                }
                Ok(Error(err)) -> {
                  json_response(400, api_types.encode_error(err))
                }
                Error(_) -> {
                  json_response(500, api_types.encode_error("Request timeout"))
                }
              }
            }
            Error(_) -> {
              json_response(400, api_types.encode_error("Invalid request body"))
            }
          }
        }
        Error(_) -> {
          json_response(401, api_types.encode_error("Missing x-user-id header"))
        }
      }
    }
    _ -> wisp.method_not_allowed([Post])
  }
}
