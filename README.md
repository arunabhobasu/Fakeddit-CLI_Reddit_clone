# Project 4 : A full stack app that uses Actor model and REST API

**Fakeddit** - A CLI style Reddit clone built in distributed fashion using Gleam actor model that interacts with REST API.

## Fakeddit Features
- User registration and authentication
- Username-based login
- Create and join subfakeddits
- Subfakeddit search
- Personalized feed
- Create posts and nested comments
- Upvote/downvote system
- Karma tracking
- Direct messaging

## At a Glance
- **Processes for individual functionality are distributed to individual actors of Gleam OTP**
- **Upstream is singular engine but downstream data is distributed across 3 engines**
  - Upstream mutation and write to disk is instantaneous using a single engine shard
  - Downstream refresh has a TTL cache of 500ms to achieve eventual consistency between 3 engine shards
  - Router routes traffic appropriately through engines
- **CLI based frontend app**
- **HTTP based simulator app to populate the social media**
  - A lot of user activity follows Zipf distribution and other interesting patterns to emulate actual user activity
- **Back end works with REST API**
  - Implements a WISP/MIST HTTP server with REST endpoints
  - Persistent data storage in JSON format
- **Demo**
[Part 1](demo.mp4)
[Part 2 (PKI Auth)](demo_2.mp4)

---

## Dependencies

- Port 8000 available for use through firewall
- `gleam_stdlib` $>= 0.34.0$
- `gleam_otp` $>= 0.10.0$
- `gleam_erlang` $>= 0.25.0$
- `gleam_json` $>= 3.1.0 \text{ and } < 4.0.0$
- `gleam_http` $>= 3.0.0$
- `wisp` $>= 0.14.0$
- `mist` $>= 1.0.0$
- `gleam_crypto` $>= 1.0.0$
- `gleam_httpc` $>= 2.0.0$
- `simplifile` $>= 2.3.1 \text{ and } < 3.0.0$
- `gleeunit` $>= 1.0.0$

---

## Operation

### 1. Start the Server
```bash
gleam run
```
- Server runs on `http://localhost:8000`

### 2. Populate Data (Optional)
- In a new terminal with custom parameters:
```bash
gleam run -m http_simulator <users> <subfakeddits> <posts> <comments> <votes> <messages>
```
- Default (no params): `55 8 20 30 0`

### 3. Use the CLI FrontEnd App
```powershell
.\fakeddit_cli.ps1
```

---

## Architecture

1. **HTTP Client Layer (Front End CLI App/Simulator/Direct HTTP)**  
   |\
   |  REST API Calls\
   V
2. **Wisp HTTP Server (Port 8000) (`api_handlers.gleam`)**\
   |\
   |  Router Requests\
   V
3. **Router Actor (`router_actor.gleam`)**  
   a. **Mutations** - Write Engine Shard - Saves to `fakeddit_state.json`  
   b. **Feed Queries** - Client wide feed Engine Shard - Reads from TTL Cache  
   c. **User Queries** - User specific Engine Shard - Reads from TTL Cache  
   d. **Misc Queries** - Karma/Voting/DMing Engine Shard - Reads from TTL Cache  
4. **TTL Cache** - updated from `fakeddit_state.json` every 500ms  

---

## Data Flow

- **Write Operation:**  
  $$\text{Client} \rightarrow \text{API} \rightarrow \text{Router} \rightarrow \text{Write Shard} \rightarrow \text{Disk} \rightarrow \text{Response}$$

- **Read Operation (Cache Fresh):**  
  $$\text{Client} \rightarrow \text{API} \rightarrow \text{Router} \rightarrow \text{Read Shard (cached)} \rightarrow \text{Response}$$

- **Read Operation (Cache Stale):**  
  $$\text{Client} \rightarrow \text{API} \rightarrow \text{Router} \rightarrow \text{Read Shard} \rightarrow \text{Reload from Disk} \rightarrow \text{Response}$$

---

## Engine Shard specific Actors

### WRITE SHARD (Handles all mutations)
- `RegisterAccount` / `Create new user`
- `CreateSubreddit` - Create community
- `JoinSubreddit` / `LeaveSubreddit` - Membership changes
- `CreatePost` / `CreateComment` - Content creation
- `UpvotePost` / `DownvotePost` - Post voting
- `UpvoteComment` / `DownvoteComment` - Comment voting
- `SendDirectMessage` - Direct messages
- *Always saves to disk after mutation*

### FEED SHARD (Read-only, TTL-cached)
- `GetFeed` - User's personalized feed
- `GetPost` - Single post details
- `GetSubreddit` - Community details
- *Reloads from disk only if >500ms elapsed*

### USER SHARD (Read-only, TTL-cached)
- `GetAccount` - User profile by ID
- `GetAccountByUsername` - User lookup by name
- `GetUserKarma` - User reputation score
- *Reloads from disk only if >500ms elapsed*

### MISC SHARD (Read-only, TTL-cached)
- `GetComments` - Fetch comment threads
- `GetDirectMessages` - User inbox
- `SearchSubreddits` - Community search
- `GetStats` - System statistics
- *Reloads from disk only if >500ms elapsed*

---

## REST API (`api_handlers.gleam`)

REST API endpoints:

### Users
- `POST /api/v1/users/register` - Register new user
- `GET /api/v1/users/:id` - Get user profile
- `GET /api/v1/users/by-username/:username` - Get user by username
- `GET /api/v1/users/:id/karma` - Get user karma

### Subfakeddits
- `POST /api/v1/subreddits` - Create subfakeddit
- `GET /api/v1/subreddits/:id` - Get subfakeddit details
- `POST /api/v1/subreddits/:id/join` - Join subfakeddit
- `POST /api/v1/subreddits/:id/leave` - Leave subfakeddit
- `GET /api/v1/subreddits/search` - Search subfakeddits

### Posts
- `POST /api/v1/posts` - Create post
- `GET /api/v1/posts/:id` - Get post with comments
- `POST /api/v1/posts/:id/upvote` - Upvote post
- `POST /api/v1/posts/:id/downvote` - Downvote post
- `GET /api/v1/feed/:user_id` - Get user's feed

### Comments
- `POST /api/v1/comments` - Create comment/reply
- `POST /api/v1/comments/:id/upvote` - Upvote comment
- `POST /api/v1/comments/:id/downvote` - Downvote comment

### Messages
- `POST /api/v1/messages` - Send direct message
- `GET /api/v1/messages/:user_id` - Get user's messages

### Stats
- `GET /api/v1/stats` - Get platform statistics

---

## Using REST API Directly

```bash
# Register a user
curl -X POST http://localhost:8000/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"alice\"}"

# Create a subfakeddit
curl -X POST http://localhost:8000/api/v1/subreddits \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"gleam\",\"description\":\"All about Gleam\",\"creator_id\":\"user_123\"}"

# Create a post
curl -X POST http://localhost:8000/api/v1/posts \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"Hello\",\"content\":\"First post\",\"author_id\":\"user_123\",\"subreddit_id\":\"sub_456\"}"

# Check server health
curl http://localhost:8000/api/v1/stats

# View a post
curl http://localhost:8000/api/v1/posts/post_123
```
---

## Security Features Added ([in bonus part](/fakeddit_bonus_pki_auth/)):

### Digital Signatures
Every post is digitally signed using HMAC-SHA256 with the author's private key at the time of creation. The signature is a 256-bit hash, also stored as Base64 (44 characters). The canonical message format signed is:
```text
post_id|author_id|title|content timestamp-
```

### Public Key Infrastructure
Each user has a unique keypair (public key + private key). Key pair is generated at registration; the user has the option to provide their own public key (in base64 encoding, 32-bytes format) or use the auto-generated one. Keys are automatically generated during registration using `crypto:strong_rand_bytes(32)`. Private keys are stored in server-side persistent storage. Signatures are verified on every post retrieval (invalid signature returns error). Public keys are retrievable via API: `GET /api/v1/accounts/:user_id/public-key`.
