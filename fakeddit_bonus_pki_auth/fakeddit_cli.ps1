
param(
    [string]$TestMode = "",
    [string]$TestInput = "",
    [switch]$AutoTest
)

$global:BaseUrl = "http://localhost:8000"
$global:CurrentUser = $null
$global:CurrentUserId = $null
$global:TestUserId = $null
$global:LastFeed = @()
$global:LastPostCache = @{}
$global:CurrentPage = 1
$global:PostsPerPage = 10
$global:TestMode = $TestMode
$global:TestInput = $TestInput
$global:AutoTest = if ($AutoTest.IsPresent -or $AutoTest -eq $true) { $true } else { $false }
$global:TestInputQueue = @()
$global:TestStepDelay = 2000  # milliseconds - increased to see what's happening

# Debug: Show if auto-test is enabled
if ($global:AutoTest) {
    Write-Host "[DEBUG: AutoTest parameter detected]" -ForegroundColor Yellow
}

function Clear-Screen {
    Clear-Host
}

function Show-Banner {
    if (-not $global:AutoTest) {
        Clear-Screen
    }
    $banner1 = "=" * 60
    Write-Host $banner1 -ForegroundColor Cyan
    Write-Host "                         FAKEDDIT                          " -ForegroundColor Cyan
    Write-Host $banner1 -ForegroundColor Cyan
    Write-Host ""
}

function Show-StatusBar {
    Write-Host ""
    $separator = "=" * 60
    Write-Host $separator -ForegroundColor Gray
    
    if ($global:CurrentUser) {
        # Fetch karma
        try {
            $karmaResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/karma" -Method Get -ErrorAction Stop
            $karma = $karmaResponse.data.karma
        }
        catch {
            $karma = "?"
        }
        
        # Fetch unread DM count
        try {
            $dmResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Get -ErrorAction Stop
            $unreadCount = 0
            foreach ($msg in $dmResponse.messages) {
                if (-not $msg.is_read -and $msg.to_user_id -eq $global:CurrentUserId) {
                    $unreadCount++
                }
            }
        }
        catch {
            $unreadCount = 0
        }
        
        Write-Host "  Logged in as: u/$global:CurrentUser" -NoNewline -ForegroundColor White
        Write-Host " | Karma: $karma" -NoNewline -ForegroundColor Green
        
        if ($unreadCount -gt 0) {
            Write-Host " | DMs: $unreadCount unread" -ForegroundColor Yellow
        }
        else {
            Write-Host " | DMs: 0" -ForegroundColor Gray
        }
        
        Write-Host "  [L] Logout  [D] Messages  [S] Search  [+] Post  [K] My Public Key  [R] Refresh" -ForegroundColor Magenta
    }
    else {
        Write-Host "  Not logged in" -ForegroundColor Yellow
        Write-Host "  [I] Login  [N] Register  [S] Search  [R] Refresh" -ForegroundColor Magenta
    }
    
    Write-Host $separator -ForegroundColor Gray
    Write-Host ""
}

function Show-Feed {
    param(
        [switch]$Silent,
        [int]$Page = 1
    )
    
    $global:CurrentPage = $Page
    
    if (-not $Silent) {
        Show-Banner
    }
    
    Write-Host "  Popular Feed - Your Fakeddit Front Page (Page $Page)" -ForegroundColor Cyan
    Write-Host ""
    
    $allAvailablePosts = @()
    
    if ($global:CurrentUserId) {
        # Logged in: Get personalized feed
        try {
            $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/feed" -Method Get -ErrorAction Stop
            $subscribedPosts = $response.data
            
            if ($subscribedPosts.Count -eq 0) {
                Write-Host "  No posts in your feed. Try joining some subfakeddits!" -ForegroundColor Yellow
                $allAvailablePosts = Get-TopPosts -Limit 100
            }
            else {
                # Get posts from subscribed subreddits
                $allAvailablePosts = $subscribedPosts
                
                # Add top posts from unsubscribed subreddits to fill out the list
                $topPosts = Get-TopPosts -Limit 50
                $extraPosts = $topPosts | Where-Object { 
                    $postId = $_.id
                    -not ($allAvailablePosts | Where-Object { $_.id -eq $postId })
                }
                
                $allAvailablePosts += $extraPosts
            }
        }
        catch {
            Write-Host "  Error loading feed. Showing top posts instead." -ForegroundColor Red
            $allAvailablePosts = Get-TopPosts -Limit 100
        }
    }
    else {
        # Not logged in: Show top posts from all subreddits
        Write-Host "  Showing popular posts (Login to see your personalized feed!)" -ForegroundColor Gray
        Write-Host ""
        $allAvailablePosts = Get-TopPosts -Limit 100
    }
    
    # Calculate pagination
    $totalPosts = $allAvailablePosts.Count
    $totalPages = [Math]::Ceiling($totalPosts / $global:PostsPerPage)
    $startIndex = ($Page - 1) * $global:PostsPerPage
    $endIndex = $startIndex + $global:PostsPerPage - 1
    $posts = $allAvailablePosts | Select-Object -Skip $startIndex -First $global:PostsPerPage
    
    $global:LastFeed = $allAvailablePosts
    $global:LastPostCache = @{}
    
    if ($posts.Count -eq 0 -and $global:CurrentUserId) {
        Write-Host "  No posts in your feed. Try joining some subfakeddits!" -ForegroundColor Yellow
    }
    else {
        $startNumber = $startIndex + 1
        Display-PostList -Posts $posts -StartNumber $startNumber
    }
    
    Write-Host ""
    
    # Show pagination info
    if ($totalPages -gt 1) {
        Write-Host "  Page $Page of $totalPages" -ForegroundColor Gray
        if ($Page -gt 1 -and $Page -lt $totalPages) {
            Write-Host "  [<] Previous Page  [>] Next Page" -ForegroundColor Magenta
        }
        elseif ($Page -gt 1) {
            Write-Host "  [<] Previous Page" -ForegroundColor Magenta
        }
        elseif ($Page -lt $totalPages) {
            Write-Host "  [>] Next Page" -ForegroundColor Magenta
        }
        Write-Host ""
    }
    
    Show-StatusBar
    
    # Show prompt
    Write-Host "  Enter post number to view, or command letter: " -NoNewline -ForegroundColor Magenta
    
    # Handle input based on test mode
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $choice = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $choice -ForegroundColor Yellow
        Write-Host "[AUTO TEST: Simulating input '$choice']" -ForegroundColor DarkGray
        Start-Sleep -Milliseconds $global:TestStepDelay
    }
    elseif ($global:AutoTest -and $global:TestInputQueue.Count -eq 0) {
        Write-Host "Q" -ForegroundColor Yellow
        Write-Host "[AUTO TEST: Complete - Exiting]" -ForegroundColor Green
        Start-Sleep -Seconds 2
        exit 0
    }
    elseif ($global:TestMode -eq "auto" -and $global:TestInput -ne "") {
        $choice = $global:TestInput
        Write-Host $choice -ForegroundColor Yellow
        $global:TestInput = ""  # Clear after use
        Start-Sleep -Milliseconds 500
    }
    else {
        $choice = Read-Host
    }
    
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Show-Feed choice='$choice']" -ForegroundColor DarkGray
    }
    
    if ($null -ne $choice -and $choice.Trim() -ne "") {
        Handle-FeedInput -UserInput $choice
    }
    else {
        # If empty, refresh feed
        Show-Feed
    }
}

function Get-TopPosts {
    param([int]$Limit = 10)
    
    try {
        # Get all subreddits and collect their posts
        $searchUrl = "$global:BaseUrl/api/v1/subreddits/search?q="
        $response = Invoke-RestMethod -Uri $searchUrl -Method Get -ErrorAction Stop
        $allPosts = @()
        
        # Get posts from each subreddit
        foreach ($subreddit in $response.data) {
            try {
                $postsUrl = "$global:BaseUrl/api/v1/subreddits/$($subreddit.id)/posts"
                $postsResponse = Invoke-RestMethod -Uri $postsUrl -Method Get -ErrorAction Stop
                $allPosts += $postsResponse.data
            }
            catch {
                continue
            }
        }
        
        # Sort by vote score (upvotes - downvotes) and take top N
        return $allPosts | Sort-Object -Property { $_.upvotes - $_.downvotes } -Descending | Select-Object -First $Limit
    }
    catch {
        return @()
    }
}

function Display-PostList {
    param(
        [array]$Posts,
        [int]$StartNumber = 1
    )
    
    for ($i = 0; $i -lt $Posts.Count; $i++) {
        $post = $Posts[$i]
        $index = $StartNumber + $i
        
        # Cache post for quick access
        $global:LastPostCache[$index] = $post
        
        # Format vote display
        $votes = $post.upvotes - $post.downvotes
        $commentCount = if ($post.comment_count) { $post.comment_count } else { 0 }
        $subName = Get-SubredditName -SubredditId $post.subreddit_id
        
        # Display post line
        Write-Host "  [$index] " -NoNewline -ForegroundColor Magenta
        Write-Host $post.title -ForegroundColor White
        
        # Meta information line
        Write-Host "      $votes votes" -NoNewline -ForegroundColor $(if ($votes -gt 0) { "Green" } elseif ($votes -lt 0) { "Red" } else { "Gray" })
        Write-Host " - $commentCount comments - f/$subName" -ForegroundColor Gray
        Write-Host ""
    }
}

function Get-SubredditName {
    param([string]$SubredditId)
    
    try {
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$SubredditId" -Method Get -ErrorAction Stop
        return $response.data.name
    }
    catch {
        return $SubredditId.Substring(0, [Math]::Min(8, $SubredditId.Length))
    }
}

function Get-Username {
    param([string]$UserId)
    
    try {
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$UserId" -Method Get -ErrorAction Stop
        return $response.data.username
    }
    catch {
        return $UserId.Substring(0, [Math]::Min(8, $UserId.Length))
    }
}

function Handle-FeedInput {
    param([string]$UserInput)
    
    $UserInput = $UserInput.Trim().ToUpper()
    
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Handle-FeedInput called with '$UserInput']" -ForegroundColor DarkGray
    }
    
    # Check if numeric (post selection)
    if ($UserInput -match '^\d+$') {
        $postIndex = [int]$UserInput
        if ($global:AutoTest) {
            Write-Host "[AUTO TEST: Checking for post $postIndex in cache. Cache has $($global:LastPostCache.Count) entries]" -ForegroundColor DarkGray
            Write-Host "[AUTO TEST: Cache keys: $($global:LastPostCache.Keys -join ', ')]" -ForegroundColor DarkGray
        }
        if ($global:LastPostCache.ContainsKey($postIndex)) {
            # Fetch full post details with comments from API
            try {
                $postId = $global:LastPostCache[$postIndex].id
                $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$postId" -Method Get -ErrorAction Stop
                Show-Post -Post $response.data
            }
            catch {
                Write-Host "Error loading post: $_" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Feed
            }
            return
        }
        else {
            Write-Host "Invalid post number!" -ForegroundColor Red
            Start-Sleep -Seconds 1
            Show-Feed
            return
        }
    }
    
    # Handle commands
    switch ($UserInput) {
        "L" {
            if ($global:CurrentUser) {
                Logout-User
            }
            else {
                Show-Feed
            }
        }
        "I" {
            if (-not $global:CurrentUser) {
                Login-User
            }
            else {
                Show-Feed
            }
        }
        "N" {
            if (-not $global:CurrentUser) {
                Register-User
            }
            else {
                Show-Feed
            }
        }
        "D" {
            if ($global:CurrentUser) {
                Show-DirectMessages
            }
            else {
                Write-Host "You must be logged in to view messages!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Feed
            }
        }
        "S" {
            Search-Subreddits
        }
        "+" {
            if ($global:CurrentUser) {
                Create-Post
            }
            else {
                Write-Host "You must be logged in to create a post!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Feed
            }
        }
        "K" {
            if ($global:CurrentUser) {
                Show-MyPublicKey
            }
            else {
                Write-Host "You must be logged in to view your public key!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Feed
            }
        }
        "R" {
            Show-Feed -Page $global:CurrentPage
        }
        ">" {
            # Next page
            $totalPosts = $global:LastFeed.Count
            $totalPages = [Math]::Ceiling($totalPosts / $global:PostsPerPage)
            if ($global:CurrentPage -lt $totalPages) {
                Show-Feed -Page ($global:CurrentPage + 1)
            }
            else {
                Show-Feed -Page $global:CurrentPage
            }
        }
        "<" {
            # Previous page
            if ($global:CurrentPage -gt 1) {
                Show-Feed -Page ($global:CurrentPage - 1)
            }
            else {
                Show-Feed -Page $global:CurrentPage
            }
        }
        "Q" {
            exit
        }
        default {
            Show-Feed -Page $global:CurrentPage
        }
    }
}

function Show-Post {
    param([object]$Post)
    
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Show-Post called for '$($Post.title)']" -ForegroundColor DarkGray
    }
    
    Show-Banner
    
    # Post header
    $headerLine = "=" * 60
    Write-Host $headerLine -ForegroundColor Cyan
    Write-Host "  $($Post.title)" -ForegroundColor White
    Write-Host $headerLine -ForegroundColor Cyan
    Write-Host ""
    
    # Post metadata
    $author = Get-Username -UserId $Post.author_id
    $subreddit = Get-SubredditName -SubredditId $Post.subreddit_id
    $votes = $Post.upvotes - $Post.downvotes
    
    Write-Host "  Posted by u/$author in f/$subreddit" -ForegroundColor Gray
    Write-Host "  $votes points ($($Post.upvotes) up / $($Post.downvotes) down)" -ForegroundColor $(if ($votes -gt 0) { "Green" } elseif ($votes -lt 0) { "Red" } else { "Gray" })
    
    # Display signature status
    if ($Post.signature) {
        Write-Host "  [Signed] Signature: $($Post.signature)" -ForegroundColor Green
    } else {
        Write-Host "  [Unsigned]" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Post content
    if ($Post.content -and $Post.content.Trim() -ne "") {
        Write-Host "  Content:" -ForegroundColor White
        $contentLines = $Post.content -split "`n"
        foreach ($line in $contentLines) {
            Write-Host "    $line" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    # Comments section
    $commentLine = "-" * 60
    Write-Host $commentLine -ForegroundColor Gray
    Write-Host "  COMMENTS" -ForegroundColor Cyan
    Write-Host $commentLine -ForegroundColor Gray
    Write-Host ""
    
    if (-not $Post.comments -or $Post.comments.Count -eq 0) {
        Write-Host "  No comments yet. Be the first to comment!" -ForegroundColor Yellow
    }
    else {
        # Get top-level comments (no parent - null, empty, or "null" string)
        $topLevelComments = $Post.comments | Where-Object { 
            -not $_.parent_comment_id -or 
            $_.parent_comment_id -eq $null -or 
            $_.parent_comment_id -eq "" -or 
            $_.parent_comment_id -eq "null"
        }
        $idx = [ref]1
        Display-CommentTree -AllComments $Post.comments -Comments $topLevelComments -Indent 0 -CurrentIndex $idx
    }
    
    Write-Host ""
    $separator = "=" * 60
    Write-Host $separator -ForegroundColor Gray
    
    # Actions
    if ($global:CurrentUser) {
        Write-Host "  [U] Upvote  [D] Downvote  [C] Comment  [R] Reply  [V] Vote Comment  [K] Author Key  [P] Users  [B] Back" -ForegroundColor Magenta
    }
    else {
        Write-Host "  [K] Author Public Key  [P] Users  [B] Back  (Login to interact)" -ForegroundColor Magenta
    }
    Write-Host $separator -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $choice = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $choice -ForegroundColor Yellow
    }
    else {
        $choice = Read-Host
    }
    
    Handle-PostInput -Post $Post -UserInput $choice
}

function Display-CommentTree {
    param(
        [array]$AllComments,
        [array]$Comments,
        [int]$Indent = 0,
        [ref]$CurrentIndex
    )
    
    # Sort comments by points (descending)
    $sortedComments = $Comments | Sort-Object { $_.upvotes - $_.downvotes } -Descending
    
    foreach ($comment in $sortedComments) {
        # Create visual nesting with -- markers
        $indentStr = "  " + ("--" * $Indent)
        if ($Indent -gt 0) {
            $indentStr += " "
        }
        
        $author = Get-Username -UserId $comment.author_id
        $points = $comment.upvotes - $comment.downvotes
        
        # Comment header with vote indicator
        $voteColor = if ($points -gt 0) { "Green" } elseif ($points -lt 0) { "Red" } else { "Gray" }
        Write-Host "$indentStr[$($CurrentIndex.Value)] u/$author " -NoNewline -ForegroundColor White
        Write-Host "($points points)" -ForegroundColor $voteColor
        
        # Comment content with proper indentation
        $contentIndent = "  " + ("--" * $Indent)
        if ($Indent -gt 0) {
            $contentIndent += " "
        }
        $contentIndent += "  "
        
        $contentLines = $comment.content -split "`n"
        foreach ($line in $contentLines) {
            Write-Host "$contentIndent$line" -ForegroundColor Gray
        }
        
        $CurrentIndex.Value++
        
        # Find and display replies to this comment
        $replies = @($AllComments | Where-Object { $_.parent_comment_id -eq $comment.id })
        if ($replies -and $replies.Count -gt 0) {
            Display-CommentTree -AllComments $AllComments -Comments $replies -Indent ($Indent + 1) -CurrentIndex $CurrentIndex
        }
        
        Write-Host ""
    }
}

function Handle-PostInput {
    param(
        [object]$Post,
        [string]$UserInput
    )
    
    $UserInput = $UserInput.Trim().ToUpper()
    
    switch ($UserInput) {
        "U" {
            if ($global:CurrentUser) {
                Upvote-Post -PostId $Post.id
                Start-Sleep -Seconds 1
                # Refresh post
                try {
                    $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$($Post.id)" -Method Get -ErrorAction Stop
                    Show-Post -Post $response.data
                }
                catch {
                    Show-Feed
                }
            }
            else {
                Write-Host "You must be logged in to vote!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Post -Post $Post
            }
        }
        "D" {
            if ($global:CurrentUser) {
                Downvote-Post -PostId $Post.id
                Start-Sleep -Seconds 1
                # Refresh post
                try {
                    $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$($Post.id)" -Method Get -ErrorAction Stop
                    Show-Post -Post $response.data
                }
                catch {
                    Show-Feed
                }
            }
            else {
                Write-Host "You must be logged in to vote!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Post -Post $Post
            }
        }
        "C" {
            if ($global:CurrentUser) {
                Add-Comment -PostId $Post.id -ParentCommentId $null
            }
            else {
                Write-Host "You must be logged in to comment!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Post -Post $Post
            }
        }
        "R" {
            if ($global:CurrentUser) {
                Write-Host ""
                Write-Host "  Enter comment number to reply to: " -NoNewline -ForegroundColor Magenta
                if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                    $commentNum = [string]$global:TestInputQueue[0]
                    if ($global:TestInputQueue.Count -gt 1) {
                        $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                    } else {
                        $global:TestInputQueue = @()
                    }
                    Write-Host $commentNum -ForegroundColor Yellow
                }
                else {
                    $commentNum = Read-Host
                }
                
                if ($commentNum -match '^\d+$') {
                    $commentIndex = [int]$commentNum
                    $topLevelComments = $Post.comments | Where-Object { 
                        -not $_.parent_comment_id -or 
                        $_.parent_comment_id -eq $null -or 
                        $_.parent_comment_id -eq "" -or 
                        $_.parent_comment_id -eq "null"
                    }
                    $idx = [ref]1
                    $commentId = Find-CommentByIndex -AllComments $Post.comments -Comments $topLevelComments -TargetIndex $commentIndex -CurrentIndex $idx
                    if ($commentId) {
                        Add-Comment -PostId $Post.id -ParentCommentId $commentId
                    }
                    else {
                        Write-Host "Invalid comment number!" -ForegroundColor Red
                        Start-Sleep -Seconds 1
                        Show-Post -Post $Post
                    }
                }
                else {
                    Show-Post -Post $Post
                }
            }
            else {
                Write-Host "You must be logged in to reply!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Post -Post $Post
            }
        }
        "V" {
            if ($global:CurrentUser) {
                Write-Host ""
                Write-Host "  Enter comment number to vote on: " -NoNewline -ForegroundColor Magenta
                if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                    $commentNum = [string]$global:TestInputQueue[0]
                    if ($global:TestInputQueue.Count -gt 1) {
                        $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                    } else {
                        $global:TestInputQueue = @()
                    }
                    Write-Host $commentNum -ForegroundColor Yellow
                }
                else {
                    $commentNum = Read-Host
                }
                
                if ($commentNum -match '^\d+$') {
                    $commentIndex = [int]$commentNum
                    $topLevelComments = $Post.comments | Where-Object { 
                        -not $_.parent_comment_id -or 
                        $_.parent_comment_id -eq $null -or 
                        $_.parent_comment_id -eq "" -or 
                        $_.parent_comment_id -eq "null"
                    }
                    $idx = [ref]1
                    $commentId = Find-CommentByIndex -AllComments $Post.comments -Comments $topLevelComments -TargetIndex $commentIndex -CurrentIndex $idx
                    if ($commentId) {
                        Write-Host ""
                        Write-Host "  [U] Upvote  [D] Downvote  [C] Cancel: " -NoNewline -ForegroundColor Magenta
                        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                            $voteChoice = [string]$global:TestInputQueue[0]
                            if ($global:TestInputQueue.Count -gt 1) {
                                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                            } else {
                                $global:TestInputQueue = @()
                            }
                            Write-Host $voteChoice -ForegroundColor Yellow
                        }
                        else {
                            $voteChoice = Read-Host
                        }
                        
                        $voteChoice = $voteChoice.Trim().ToUpper()
                        switch ($voteChoice) {
                            "U" {
                                Upvote-Comment -CommentId $commentId
                                Start-Sleep -Seconds 1
                                # Refresh post
                                try {
                                    $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$($Post.id)" -Method Get -ErrorAction Stop
                                    Show-Post -Post $response.data
                                }
                                catch {
                                    Show-Feed
                                }
                            }
                            "D" {
                                Downvote-Comment -CommentId $commentId
                                Start-Sleep -Seconds 1
                                # Refresh post
                                try {
                                    $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$($Post.id)" -Method Get -ErrorAction Stop
                                    Show-Post -Post $response.data
                                }
                                catch {
                                    Show-Feed
                                }
                            }
                            default {
                                Show-Post -Post $Post
                            }
                        }
                    }
                    else {
                        Write-Host "Invalid comment number!" -ForegroundColor Red
                        Start-Sleep -Seconds 1
                        Show-Post -Post $Post
                    }
                }
                else {
                    Show-Post -Post $Post
                }
            }
            else {
                Write-Host "You must be logged in to vote!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Post -Post $Post
            }
        }
        "K" {
            Show-AuthorPublicKey -Post $Post
        }
        "P" {
            Show-PostUsers -Post $Post
        }
        "B" {
            Show-Feed
        }
        default {
            Show-Post -Post $Post
        }
    }
}

function Show-AuthorPublicKey {
    param([object]$Post)
    
    Show-Banner
    Write-Host "  AUTHOR'S PUBLIC KEY" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $author = Get-Username -UserId $Post.author_id
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$($Post.author_id)/public-key" -Method Get -ErrorAction Stop
        
        $separator = "-" * 60
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Post: $($Post.title)" -ForegroundColor White
        Write-Host "  Author: u/$author" -ForegroundColor White
        Write-Host ""
        Write-Host "  Public Key (Base64):\" -ForegroundColor Cyan
        Write-Host "  $($response.data.public_key)\" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  This key verifies the digital signature on this post.\" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [B] Back to Post: \" -NoNewline -ForegroundColor Magenta
        
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $choice = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $choice -ForegroundColor Yellow
        }
        else {
            $choice = Read-Host
        }
        
        Show-Post -Post $Post
    }
    catch {
        Write-Host "  Failed to retrieve public key: $_" -ForegroundColor Red
        Write-Host ""
        Start-Sleep -Seconds 2
        Show-Post -Post $Post
    }
}

function Show-PostUsers {
    param([object]$Post)
    
    Show-Banner
    Write-Host "  USERS IN THIS POST" -ForegroundColor Cyan
    Write-Host ""
    
    # Collect unique user IDs: post author first, then commenters
    $userIds = @()
    $userIds += $Post.author_id
    
    # Add all commenters
    foreach ($comment in $Post.comments) {
        if ($comment.author_id -notin $userIds) {
            $userIds += $comment.author_id
        }
    }
    
    # Display users
    $userLine = "-" * 60
    Write-Host $userLine -ForegroundColor Gray
    
    for ($i = 0; $i -lt $userIds.Count; $i++) {
        $userId = $userIds[$i]
        $username = Get-Username -UserId $userId
        
        if ($i -eq 0) {
            Write-Host "  [$($i + 1)] u/$username" -NoNewline -ForegroundColor Yellow
            Write-Host " (Post Author)" -ForegroundColor Gray
        }
        else {
            Write-Host "  [$($i + 1)] u/$username" -ForegroundColor White
        }
    }
    
    Write-Host ""
    $separator = "=" * 60
    Write-Host $separator -ForegroundColor Gray
    Write-Host "  [#] View User Profile  [B] Back to Post" -ForegroundColor Magenta
    Write-Host $separator -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
    
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $choice = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $choice -ForegroundColor Yellow
    }
    else {
        $choice = Read-Host
    }
    
    $choice = $choice.Trim().ToUpper()
    
    if ($choice -eq "B") {
        Show-Post -Post $Post
    }
    elseif ($choice -match '^\d+$') {
        $userIndex = [int]$choice - 1
        if ($userIndex -ge 0 -and $userIndex -lt $userIds.Count) {
            Show-UserProfile -UserId $userIds[$userIndex] -ReturnPost $Post
        }
        else {
            Show-PostUsers -Post $Post
        }
    }
    else {
        Show-PostUsers -Post $Post
    }
}

function Show-UserProfile {
    param(
        [string]$UserId,
        [object]$ReturnPost
    )
    
    try {
        # Fetch user details
        $username = Get-Username -UserId $UserId
        
        # Fetch karma
        try {
            $karmaResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$UserId/karma" -Method Get -ErrorAction Stop
            $karma = $karmaResponse.data.karma
        }
        catch {
            $karma = "?"
        }
        
        Show-Banner
        Write-Host "  USER PROFILE" -ForegroundColor Cyan
        Write-Host ""
        
        $userLine = "-" * 60
        Write-Host $userLine -ForegroundColor Gray
        Write-Host "  Username: u/$username" -ForegroundColor White
        Write-Host "  Karma: $karma" -ForegroundColor Green
        Write-Host "  User ID: $UserId" -ForegroundColor Gray
        
        # Fetch and display public key
        try {
            $pkResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$UserId/public-key" -Method Get -ErrorAction Stop
            Write-Host ""
            Write-Host "  Public Key:" -ForegroundColor Cyan
            Write-Host "  $($pkResponse.data.public_key)" -ForegroundColor Yellow
        }
        catch {
            # Public key not available
        }
        
        Write-Host $userLine -ForegroundColor Gray
        Write-Host ""
        
        $separator = "=" * 60
        Write-Host $separator -ForegroundColor Gray
        
        if ($global:CurrentUser -and $global:CurrentUserId -ne $UserId) {
            Write-Host "  [M] Send Direct Message  [B] Back  [F] Feed" -ForegroundColor Magenta
        }
        else {
            Write-Host "  [B] Back  [F] Feed" -ForegroundColor Magenta
        }
        
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
        
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $choice = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $choice -ForegroundColor Yellow
        }
        else {
            $choice = Read-Host
        }
        
        $choice = $choice.Trim().ToUpper()
        
        if ($choice -eq "F") {
            Show-Feed
        }
        elseif ($choice -eq "M" -and $global:CurrentUser -and $global:CurrentUserId -ne $UserId) {
            Write-Host ""
            Write-Host "  Enter your message: " -NoNewline -ForegroundColor Magenta
            
            if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                $messageContent = [string]$global:TestInputQueue[0]
                if ($global:TestInputQueue.Count -gt 1) {
                    $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                } else {
                    $global:TestInputQueue = @()
                }
                Write-Host $messageContent -ForegroundColor Yellow
            }
            else {
                $messageContent = Read-Host
            }
            
            if ($messageContent.Trim() -ne "") {
                try {
                    $headers = @{
                        'x-user-id' = $global:CurrentUserId
                        'Content-Type' = 'application/json'
                    }
                    $body = @{
                        to_user_id = $UserId
                        content = $messageContent.Trim()
                    } | ConvertTo-Json
                    
                    $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Post -Headers $headers -Body $body -ErrorAction Stop
                    
                    Write-Host ""
                    Write-Host "  Message sent successfully!" -ForegroundColor Green
                    Start-Sleep -Seconds 2
                }
                catch {
                    Write-Host ""
                    Write-Host "  Failed to send message: $_" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
            
            Show-UserProfile -UserId $UserId -ReturnPost $ReturnPost
        }
        elseif ($choice -eq "B") {
            if ($ReturnPost) {
                Show-PostUsers -Post $ReturnPost
            }
            else {
                Show-Feed
            }
        }
        else {
            Show-UserProfile -UserId $UserId -ReturnPost $ReturnPost
        }
    }
    catch {
        Write-Host ""
        Write-Host "  Error loading user profile: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        if ($ReturnPost) {
            Show-PostUsers -Post $ReturnPost
        }
        else {
            Show-Feed
        }
    }
}

function Find-CommentByIndex {
    param(
        [array]$AllComments,
        [array]$Comments,
        [int]$TargetIndex,
        [ref]$CurrentIndex
    )
    
    # Sort comments by points (descending) - same order as display
    $sortedComments = $Comments | Sort-Object { $_.upvotes - $_.downvotes } -Descending
    
    foreach ($comment in $sortedComments) {
        # Check if THIS is the target comment (before incrementing, to match display logic)
        if ($CurrentIndex.Value -eq $TargetIndex) {
            return $comment.id
        }
        
        # Increment AFTER checking (to match Display-CommentTree which displays then increments)
        $CurrentIndex.Value++
        
        # Find replies to this comment (wrap in @() to force array)
        $replies = @($AllComments | Where-Object { $_.parent_comment_id -eq $comment.id })
        if ($replies -and $replies.Count -gt 0) {
            $result = Find-CommentByIndex -AllComments $AllComments -Comments $replies -TargetIndex $TargetIndex -CurrentIndex $CurrentIndex
            if ($result) {
                return $result
            }
        }
    }
    
    return $null
}

function Upvote-Post {
    param([string]$PostId)
    
    try {
        $body = @{
            user_id = $global:CurrentUserId
            post_id = $PostId
        } | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$PostId/upvote" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Upvoted!" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to upvote: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Downvote-Post {
    param([string]$PostId)
    
    try {
        $body = @{
            user_id = $global:CurrentUserId
            post_id = $PostId
        } | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$PostId/downvote" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Downvoted!" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to downvote: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Upvote-Comment {
    param([string]$CommentId)
    
    try {
        $body = @{
            user_id = $global:CurrentUserId
            comment_id = $CommentId
        } | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/comments/$CommentId/upvote" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Upvoted comment!" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to upvote comment: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Downvote-Comment {
    param([string]$CommentId)
    
    try {
        $body = @{
            user_id = $global:CurrentUserId
            comment_id = $CommentId
        } | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/comments/$CommentId/downvote" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Downvoted comment!" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to downvote comment: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Add-Comment {
    param(
        [string]$PostId,
        [string]$ParentCommentId
    )
    
    Write-Host ""
    Write-Host "  Enter your comment (or 'cancel' to abort): " -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $content = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $content -ForegroundColor Yellow
    }
    else {
        $content = Read-Host
    }
    
    if ($content.Trim().ToLower() -eq "cancel" -or $content.Trim() -eq "") {
        # Reload post
        try {
            $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$PostId" -Method Get -ErrorAction Stop
            Show-Post -Post $response.data
        }
        catch {
            Show-Feed
        }
        return
    }
    
    try {
        $body = @{
            content = $content
            parent_comment_id = if ($ParentCommentId) { $ParentCommentId } else { $null }
        }
        
        $bodyJson = $body | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$PostId/comments" -Method Post -Body $bodyJson -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Comment posted!" -ForegroundColor Green
        Start-Sleep -Seconds 1
        
        # Reload post
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$PostId" -Method Get -ErrorAction Stop
        Show-Post -Post $response.data
    }
    catch {
        Write-Host "Failed to post comment: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-Feed
    }
}

function Create-Post {
    Show-Banner
    Write-Host "  CREATE NEW POST" -ForegroundColor Cyan
    Write-Host ""
    
    # Get user's subscribed subreddits
    try {
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId" -Method Get -ErrorAction Stop
        $subreddits = $response.data.joined_subreddits
        
        if ($subreddits.Count -eq 0) {
            Write-Host "  You are not subscribed to any subfakeddits!" -ForegroundColor Yellow
            Write-Host "  Join some subfakeddits first to create posts." -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Press any key to return to feed..." -ForegroundColor Magenta
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Show-Feed
            return
        }
        
        Write-Host "  Select a subreddit:" -ForegroundColor White
        for ($i = 0; $i -lt $subreddits.Count; $i++) {
            $subName = Get-SubredditName -SubredditId $subreddits[$i]
            Write-Host "    [$($i + 1)] f/$subName" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  Enter number (or 'cancel'): " -NoNewline -ForegroundColor Magenta
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $subChoice = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $subChoice -ForegroundColor Yellow
        }
        else {
            $subChoice = Read-Host
        }
        
        if ($subChoice.Trim().ToLower() -eq "cancel") {
            Show-Feed
            return
        }
        
        if ($subChoice -match '^\d+$') {
            $subIndex = [int]$subChoice - 1
            if ($subIndex -ge 0 -and $subIndex -lt $subreddits.Count) {
                $selectedSub = $subreddits[$subIndex]
                
                Write-Host ""
                Write-Host "  Post title: " -NoNewline -ForegroundColor Magenta
                if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                    $title = [string]$global:TestInputQueue[0]
                    if ($global:TestInputQueue.Count -gt 1) {
                        $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                    } else {
                        $global:TestInputQueue = @()
                    }
                    Write-Host $title -ForegroundColor Yellow
                }
                else {
                    $title = Read-Host
                }
                
                if ($title.Trim() -eq "") {
                    Write-Host "  Title cannot be empty!" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    Show-Feed
                    return
                }
                
                Write-Host "  Post content: " -NoNewline -ForegroundColor Magenta
                if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                    $content = [string]$global:TestInputQueue[0]
                    if ($global:TestInputQueue.Count -gt 1) {
                        $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                    } else {
                        $global:TestInputQueue = @()
                    }
                    Write-Host $content -ForegroundColor Yellow
                }
                else {
                    $content = Read-Host
                }
                
                # Create post
                try {
                    $body = @{
                        title = $title
                        content = $content
                    } | ConvertTo-Json
                    
                    $headers = @{"x-user-id" = $global:CurrentUserId}
                    Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$selectedSub/posts" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
                    Write-Host ""
                    Write-Host "  Post created successfully!" -ForegroundColor Green
                    Start-Sleep -Seconds 2
                    Show-Feed
                }
                catch {
                    Write-Host ""
                    Write-Host "  Failed to create post: $_" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    Show-Feed
                }
            }
            else {
                Write-Host "  Invalid choice!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Feed
            }
        }
        else {
            Show-Feed
        }
    }
    catch {
        Write-Host "  Error loading subscriptions: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-Feed
    }
}

function Show-DirectMessages {
    Show-Banner
    Write-Host "  DIRECT MESSAGES" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Get -ErrorAction Stop
        $allMessages = $response.data
        
        if ($allMessages.Count -eq 0) {
            Write-Host "  No messages yet." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [N] New Message  [B] Back to Feed" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
            if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                $choice = [string]$global:TestInputQueue[0]
                if ($global:TestInputQueue.Count -gt 1) {
                    $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                } else {
                    $global:TestInputQueue = @()
                }
                Write-Host $choice -ForegroundColor Yellow
            }
            else {
                $choice = Read-Host
            }
            
            if ($choice.Trim().ToUpper() -eq "N") {
                Send-NewMessage
            }
            else {
                Show-Feed
            }
            return
        }
        
        # Group messages by conversation partner
        $conversations = @{}
        foreach ($msg in $allMessages) {
            $partnerId = if ($msg.from_user_id -eq $global:CurrentUserId) { $msg.to_user_id } else { $msg.from_user_id }
            
            if (-not $conversations.ContainsKey($partnerId)) {
                $conversations[$partnerId] = @()
            }
            $conversations[$partnerId] += $msg
        }
        
        # Display conversation list
        Write-Host "  Conversations:" -ForegroundColor White
        Write-Host ""
        
        $conversationList = @()
        $index = 1
        foreach ($partnerId in $conversations.Keys) {
            $partnerName = Get-Username -UserId $partnerId
            $messages = $conversations[$partnerId] | Sort-Object -Property created_at
            $lastMessage = $messages[-1]
            
            # Count unread
            $unread = ($messages | Where-Object { -not $_.is_read -and $_.to_user_id -eq $global:CurrentUserId }).Count
            
            Write-Host "  [$index] u/$partnerName" -NoNewline -ForegroundColor White
            
            if ($unread -gt 0) {
                Write-Host " ($unread unread)" -ForegroundColor Yellow
            }
            else {
                Write-Host ""
            }
            
            # Show preview of last message
            $preview = if ($lastMessage.content.Length -gt 50) { 
                $lastMessage.content.Substring(0, 47) + "..." 
            } else { 
                $lastMessage.content 
            }
            Write-Host "      $preview" -ForegroundColor Gray
            Write-Host ""
            
            $conversationList += @{ Index = $index; PartnerId = $partnerId; Messages = $messages }
            $index++
        }
        
        $separator = "=" * 60
        Write-Host $separator -ForegroundColor Gray
        Write-Host "  [#] View Conversation  [N] New Message  [B] Back to Feed" -ForegroundColor Magenta
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
        $choice = Read-Host
        
        $choice = $choice.Trim().ToUpper()
        
        if ($choice -eq "N") {
            Send-NewMessage
        }
        elseif ($choice -eq "B") {
            Show-Feed
        }
        elseif ($choice -match '^\d+$') {
            $convIndex = [int]$choice
            $conversation = $conversationList | Where-Object { $_.Index -eq $convIndex } | Select-Object -First 1
            if ($conversation) {
                Show-Conversation -PartnerId $conversation.PartnerId -Messages $conversation.Messages
            }
            else {
                Write-Host "Invalid conversation number!" -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-DirectMessages
            }
        }
        else {
            Show-DirectMessages
        }
    }
    catch {
        Write-Host "  Error loading messages: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-Feed
    }
}

function Show-Conversation {
    param(
        [string]$PartnerId,
        [array]$Messages
    )
    
    Show-Banner
    $partnerName = Get-Username -UserId $PartnerId
    Write-Host "  CONVERSATION WITH u/$partnerName" -ForegroundColor Cyan
    Write-Host ""
    
    # Sort messages chronologically
    $sortedMessages = $Messages | Sort-Object -Property created_at
    
    foreach ($msg in $sortedMessages) {
        $isFromMe = $msg.from_user_id -eq $global:CurrentUserId
        
        if ($isFromMe) {
            Write-Host "  >> You:" -ForegroundColor Green
            Write-Host "     $($msg.content)" -ForegroundColor Gray
        }
        else {
            Write-Host "  << $partnerName`:" -ForegroundColor Cyan
            Write-Host "     $($msg.content)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    $separator = "=" * 60
    Write-Host $separator -ForegroundColor Gray
    Write-Host "  [R] Reply  [B] Back to Messages  [F] Feed" -ForegroundColor Magenta
    Write-Host $separator -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
    $choice = Read-Host
    
    $choice = $choice.Trim().ToUpper()
    
    if ($choice -eq "F") {
        Show-Feed
    }
    elseif ($choice -eq "R") {
        Write-Host ""
        Write-Host "  Your message: " -NoNewline -ForegroundColor Magenta
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $content = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $content -ForegroundColor Yellow
        }
        else {
            $content = Read-Host
        }
        
        if ($content.Trim() -ne "") {
            try {
                $body = @{
                    from_user_id = $global:CurrentUserId
                    to_user_id = $PartnerId
                    content = $content
                } | ConvertTo-Json
                
                $headers = @{"x-user-id" = $global:CurrentUserId}
                Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
                Write-Host "  Message sent!" -ForegroundColor Green
                Start-Sleep -Seconds 1
                
                # Reload conversation
                $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Get -ErrorAction Stop
                $updatedMessages = $response.data | Where-Object { 
                    ($_.from_user_id -eq $global:CurrentUserId -and $_.to_user_id -eq $PartnerId) -or
                    ($_.from_user_id -eq $PartnerId -and $_.to_user_id -eq $global:CurrentUserId)
                }
                Show-Conversation -PartnerId $PartnerId -Messages $updatedMessages
            }
            catch {
                Write-Host "  Failed to send message: $_" -ForegroundColor Red
                Start-Sleep -Seconds 2
                Show-DirectMessages
            }
        }
        else {
            Show-Conversation -PartnerId $PartnerId -Messages $Messages
        }
    }
    elseif ($choice -eq "B") {
        Show-DirectMessages
    }
    else {
        Show-Conversation -PartnerId $PartnerId -Messages $Messages
    }
}

function Send-NewMessage {
    Show-Banner
    Write-Host "  NEW MESSAGE" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  Enter recipient user ID: " -NoNewline -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $recipientId = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $recipientId -ForegroundColor Yellow
    }
    else {
        $recipientId = Read-Host
    }
    
    if ($recipientId.Trim() -eq "") {
        Show-DirectMessages
        return
    }
    
    Write-Host "  Message content: " -NoNewline -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $content = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $content -ForegroundColor Yellow
    }
    else {
        $content = Read-Host
    }
    
    if ($content.Trim() -eq "") {
        Show-DirectMessages
        return
    }
    
    try {
        $body = @{
            to_user_id = $recipientId
            content = $content
        } | ConvertTo-Json
        
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/messages" -Method Post -Body $body -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host ""
        Write-Host "  Message sent!" -ForegroundColor Green
        Start-Sleep -Seconds 2
        Show-DirectMessages
    }
    catch {
        Write-Host ""
        Write-Host "  Failed to send message: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-DirectMessages
    }
}

function Search-Subreddits {
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Search-Subreddits called]" -ForegroundColor DarkGray
    }
    
    Show-Banner
    Write-Host "  SEARCH SUBFAKEDDITS" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  Enter search query (or press Enter for all): " -NoNewline -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $query = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $query -ForegroundColor Yellow
    }
    else {
        $query = Read-Host
    }
    
    try {
        $searchUrl = "$global:BaseUrl/api/v1/subreddits/search?q=$query"
        $response = Invoke-RestMethod -Uri $searchUrl -Method Get -ErrorAction Stop
        
        if ($response.data.Count -eq 0) {
            Write-Host ""
            Write-Host "  No subfakeddits found." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Press any key to return..." -ForegroundColor Magenta
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Show-Feed
            return
        }
        
        Write-Host ""
        Write-Host "  Results:" -ForegroundColor White
        Write-Host ""
        
        for ($i = 0; $i -lt $response.data.Count; $i++) {
            $sub = $response.data[$i]
            $memberCount = $sub.member_count
            
            Write-Host "  [$($i + 1)] f/$($sub.name) ($memberCount members)" -ForegroundColor White
            
            if ($sub.description -and $sub.description.Trim() -ne "") {
                Write-Host "      $($sub.description)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        $separator = "=" * 60
        Write-Host $separator -ForegroundColor Gray
        if ($global:CurrentUser) {
            Write-Host "  [#] View Subfakeddit  [J] Join  [B] Back to Feed" -ForegroundColor Magenta
        }
        else {
            Write-Host "  [#] View Subfakeddit  [B] Back to Feed  (Login to join)" -ForegroundColor Magenta
        }
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $choice = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $choice -ForegroundColor Yellow
        }
        else {
            $choice = Read-Host
        }
        
        $choice = $choice.Trim().ToUpper()
        
        if ($choice -eq "B") {
            Show-Feed
        }
        elseif ($choice -eq "J" -and $global:CurrentUser) {
            Write-Host ""
            Write-Host "  Enter subfakeddit number to join: " -NoNewline -ForegroundColor Magenta
            if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
                $subNum = [string]$global:TestInputQueue[0]
                if ($global:TestInputQueue.Count -gt 1) {
                    $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
                } else {
                    $global:TestInputQueue = @()
                }
                Write-Host $subNum -ForegroundColor Yellow
            }
            else {
                $subNum = Read-Host
            }
            
            if ($subNum -match '^\d+$') {
                $subIndex = [int]$subNum - 1
                if ($subIndex -ge 0 -and $subIndex -lt $response.data.Count) {
                    $selectedSub = $response.data[$subIndex]
                    Join-Subreddit -SubredditId $selectedSub.id -SubredditName $selectedSub.name
                }
            }
            Search-Subreddits
        }
        elseif ($choice -match '^\d+$') {
            $subIndex = [int]$choice - 1
            if ($subIndex -ge 0 -and $subIndex -lt $response.data.Count) {
                View-Subreddit -Subreddit $response.data[$subIndex]
            }
            else {
                Search-Subreddits
            }
        }
        else {
            Search-Subreddits
        }
    }
    catch {
        Write-Host ""
        Write-Host "  Error searching subfakeddits: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-Feed
    }
}

function View-Subreddit {
    param([object]$Subreddit)
    
    Show-Banner
    Write-Host "  f/$($Subreddit.name)" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Subreddit.description -and $Subreddit.description.Trim() -ne "") {
        Write-Host "  $($Subreddit.description)" -ForegroundColor Gray
        Write-Host ""
    }
    
    Write-Host "  Members: $($Subreddit.member_count)" -ForegroundColor Gray
    Write-Host ""
    
    # Check if user is subscribed
    $isSubscribed = $false
    if ($global:CurrentUser) {
        try {
            $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId" -Method Get -ErrorAction Stop
            $isSubscribed = $response.data.joined_subreddits -contains $Subreddit.id
        }
        catch {
            $isSubscribed = $false
        }
    }
    
    # Fetch posts from the subfakeddit
    try {
        $postsResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$($Subreddit.id)/posts" -Method Get -ErrorAction Stop
        $posts = $postsResponse.data
    }
    catch {
        $posts = @()
    }
    
    # Show posts
    $postLine = "-" * 60
    Write-Host $postLine -ForegroundColor Gray
    Write-Host "  RECENT POSTS" -ForegroundColor White
    Write-Host $postLine -ForegroundColor Gray
    Write-Host ""
    
    if ($posts.Count -eq 0) {
        Write-Host "  No posts yet." -ForegroundColor Yellow
    }
    else {
        Display-PostList -Posts ($posts | Select-Object -First 10)
    }
    
    Write-Host ""
    $separator = "=" * 60
    Write-Host $separator -ForegroundColor Gray
    
    if ($global:CurrentUser) {
        if ($isSubscribed) {
            Write-Host "  [#] View Post  [L] Leave Subfakeddit  [B] Back  [F] Feed" -ForegroundColor Magenta
        }
        else {
            Write-Host "  [#] View Post  [J] Join Subfakeddit  [B] Back  [F] Feed" -ForegroundColor Magenta
        }
    }
    else {
        Write-Host "  [#] View Post  [B] Back  [F] Feed  (Login to join)" -ForegroundColor Magenta
    }
    
    Write-Host $separator -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Your choice: " -NoNewline -ForegroundColor Magenta
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $choice = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $choice -ForegroundColor Yellow
    }
    else {
        $choice = Read-Host
    }
    
    $choice = $choice.Trim().ToUpper()
    
    if ($choice -eq "F") {
        Show-Feed
    }
    elseif ($choice -eq "B") {
        Search-Subreddits
    }
    elseif ($choice -eq "J" -and $global:CurrentUser -and -not $isSubscribed) {
        Join-Subreddit -SubredditId $Subreddit.id -SubredditName $Subreddit.name
        # Reload subreddit
        try {
            $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$($Subreddit.id)" -Method Get -ErrorAction Stop
            View-Subreddit -Subreddit $response.data
        }
        catch {
            Search-Subreddits
        }
    }
    elseif ($choice -eq "L" -and $global:CurrentUser -and $isSubscribed) {
        Leave-Subreddit -SubredditId $Subreddit.id -SubredditName $Subreddit.name
        # Reload subreddit
        try {
            $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$($Subreddit.id)\" -Method Get -ErrorAction Stop
            View-Subreddit -Subreddit $response.data
        }
        catch {
            Search-Subreddits
        }
    }
    elseif ($choice -match '^\d+$') {
        $postIndex = [int]$choice
        if ($global:LastPostCache.ContainsKey($postIndex)) {
            # Fetch full post details with comments from API
            try {
                $postId = $global:LastPostCache[$postIndex].id
                $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/posts/$postId" -Method Get -ErrorAction Stop
                Show-Post -Post $response.data
            }
            catch {
                Write-Host "Error loading post: $_" -ForegroundColor Red
                Start-Sleep -Seconds 1
                View-Subreddit -Subreddit $Subreddit
            }
        }
        else {
            Write-Host "Invalid post number!" -ForegroundColor Red
            Start-Sleep -Seconds 1
            View-Subreddit -Subreddit $Subreddit
        }
    }
    else {
        View-Subreddit -Subreddit $Subreddit
    }
}

function Join-Subreddit {
    param(
        [string]$SubredditId,
        [string]$SubredditName
    )
    
    try {
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$SubredditId/join" -Method Post -Body "" -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host ""
        Write-Host "  Joined f/$SubredditName!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Host ""
        Write-Host "  Failed to join subfakeddit: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Leave-Subreddit {
    param(
        [string]$SubredditId,
        [string]$SubredditName
    )
    
    try {
        $headers = @{"x-user-id" = $global:CurrentUserId}
        Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/subreddits/$SubredditId/leave" -Method Post -Body "" -Headers $headers -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host ""
        Write-Host "  Left f/$SubredditName!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Host ""
        Write-Host "  Failed to leave subfakeddit: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

function Register-User {
    param(
        [string]$TestUsername = "",
        [switch]$NoReturn
    )
    
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Register-User called]" -ForegroundColor DarkGray
    }
    
    Show-Banner
    Write-Host "  CREATE ACCOUNT" -ForegroundColor Cyan
    Write-Host ""
    
    if ($TestUsername -ne "") {
        $username = $TestUsername
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        Write-Host $username -ForegroundColor Yellow
    }
    elseif ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $username = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        Write-Host $username -ForegroundColor Yellow
    }
    else {
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        $username = Read-Host
    }
    
    if ($username.Trim() -eq "") {
        Write-Host "  Username cannot be empty!" -ForegroundColor Red
        Start-Sleep -Seconds 1
        if (-not $NoReturn) { Show-Feed }
        return
    }
    
    # Ask if user wants to provide their own public key
    Write-Host ""
    Write-Host "  Do you want to provide your own public key? [y/N]: " -NoNewline -ForegroundColor Magenta
    
    $providePubKey = ""
    if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $providePubKey = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        Write-Host $providePubKey -ForegroundColor Yellow
    }
    else {
        $providePubKey = Read-Host
    }
    
    $publicKey = ""
    if ($providePubKey.Trim().ToUpper() -eq "Y") {
        Write-Host "  Enter your Base64-encoded public key: " -NoNewline -ForegroundColor Magenta
        
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $publicKey = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $publicKey -ForegroundColor Yellow
        }
        else {
            $publicKey = Read-Host
        }
    }
    
    try {
        $body = @{ username = $username; public_key = $publicKey } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        
        $global:CurrentUserId = $response.data.id
        $global:CurrentUser = $username
        
        # Store for auto-test login later
        if ($global:AutoTest) {
            $global:TestCreatedUserId = $response.data.id
            Write-Host "[AUTO TEST: Stored created user ID for later: $($global:TestCreatedUserId)]" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        Write-Host "  Account created successfully! Welcome, u/$username!" -ForegroundColor Green
        Write-Host "  Your user ID is: $($global:CurrentUserId)" -ForegroundColor Gray
        
        # Display public key
        if ($response.data.public_key) {
            Write-Host ""
            Write-Host "  Your Public Key (for signature verification):" -ForegroundColor Cyan
            Write-Host "  $($response.data.public_key)" -ForegroundColor Yellow
        }
        
        Start-Sleep -Seconds 3
        if (-not $NoReturn) { Show-Feed }
    }
    catch {
        Write-Host ""
        Write-Host "  Failed to create account: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        if (-not $NoReturn) { Show-Feed }
    }
}

function Login-User {
    param(
        [string]$TestUserId = "",
        [switch]$NoReturn
    )
    
    if ($global:AutoTest) {
        Write-Host "[AUTO TEST: Login-User called]" -ForegroundColor DarkGray
    }
    
    Show-Banner
    Write-Host "  LOGIN" -ForegroundColor Cyan
    Write-Host ""
    
    if ($TestUserId -ne "") {
        $username = $TestUserId
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        Write-Host $username -ForegroundColor Yellow
    }
    elseif ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
        $username = [string]$global:TestInputQueue[0]
        if ($global:TestInputQueue.Count -gt 1) {
            $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
        } else {
            $global:TestInputQueue = @()
        }
        
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        Write-Host $username -ForegroundColor Yellow
        if ($global:AutoTest) {
            Write-Host "[AUTO TEST: Login with username: '$username']" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  Enter username: " -NoNewline -ForegroundColor Magenta
        $username = Read-Host
    }
    
    if ($username.Trim() -eq "") {
        if (-not $NoReturn) { Show-Feed }
        return
    }
    
    try {
        # Lookup user by username
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/lookup?username=$username" -Method Get -ErrorAction Stop
        
        $global:CurrentUserId = $response.data.id
        $global:CurrentUser = $response.data.username
        
        Write-Host ""
        Write-Host "  Logged in as u/$($global:CurrentUser)!" -ForegroundColor Green
        
        # Display public key
        try {
            $pkResponse = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/public-key" -Method Get -ErrorAction Stop
            Write-Host ""
            Write-Host "  Your Public Key:" -ForegroundColor Cyan
            Write-Host "  $($pkResponse.data.public_key)" -ForegroundColor Yellow
        }
        catch {
            # Public key not available
        }
        
        Start-Sleep -Seconds 3
        if (-not $NoReturn) { Show-Feed }
    }
    catch {
        Write-Host ""
        Write-Host "  Username not found!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        if (-not $NoReturn) { Show-Feed }
    }
}

function Logout-User {
    $global:CurrentUser = $null
    $global:CurrentUserId = $null
    # Keep $global:TestUserId for auto-test
    Write-Host ""
    Write-Host "  Logged out successfully!" -ForegroundColor Green
    Start-Sleep -Seconds 1
    Show-Feed
}

function Show-MyPublicKey {
    Show-Banner
    Write-Host "  MY PUBLIC KEY" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $response = Invoke-RestMethod -Uri "$global:BaseUrl/api/v1/accounts/$global:CurrentUserId/public-key" -Method Get -ErrorAction Stop
        
        $separator = "-" * 60
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Username: u/$global:CurrentUser" -ForegroundColor White
        Write-Host ""
        Write-Host "  Your Public Key (Base64):\" -ForegroundColor Cyan
        Write-Host "  $($response.data.public_key)\" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Share this key for others to verify your post signatures.\" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host $separator -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [B] Back to Feed: \" -NoNewline -ForegroundColor Magenta
        
        if ($global:AutoTest -and $global:TestInputQueue.Count -gt 0) {
            $choice = [string]$global:TestInputQueue[0]
            if ($global:TestInputQueue.Count -gt 1) {
                $global:TestInputQueue = $global:TestInputQueue[1..($global:TestInputQueue.Count - 1)]
            } else {
                $global:TestInputQueue = @()
            }
            Write-Host $choice -ForegroundColor Yellow
        }
        else {
            $choice = Read-Host
        }
        
        Show-Feed
    }
    catch {
        Write-Host "  Failed to retrieve your public key: $_\" -ForegroundColor Red
        Write-Host ""
        Start-Sleep -Seconds 2
        Show-Feed
    }
}

# Main entry point - only run if not being dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Setup auto-test sequence if enabled
        Write-Host "[DEBUG: Checking AutoTest - IsPresent=$($AutoTest.IsPresent), Value=$AutoTest]" -ForegroundColor Magenta
        if ($AutoTest.IsPresent -or $AutoTest -eq $true) {
            $global:AutoTest = $true
            Write-Host "`n[AUTO TEST MODE ENABLED]" -ForegroundColor Cyan
            Write-Host "Testing CLI functionality...`n" -ForegroundColor Cyan
            
            # Test sequence: Test all 4 buttons (I, N, S, R) and 2 post numbers (1, 2)
            $global:TestInputQueue = @(
                "1",                           # Test post number 1 (view post)
                "B",                           # Go back from post
                "2",                           # Test post number 2 (view post)
                "B",                           # Go back from post
                "N",                           # Test N: Register button
                "TestUser" + (Get-Random),     # Enter username for registration
                "L",                           # Logout after registration
                "S",                           # Test S: Search button
                "",                            # Empty search query (show all subreddits)
                "B",                           # Go back to feed from search
                "R",                           # Test R: Refresh button
                "I",                           # Test I: Login button
                "",                            # Empty = will use stored TestCreatedUserId
                "R"                            # Final refresh to see logged-in view
            )
            
            Write-Host "[AUTO TEST: Queue loaded with $($global:TestInputQueue.Count) commands]" -ForegroundColor DarkGray
            Write-Host "[AUTO TEST: Testing - Post view (1,2), Register (N), Search (S), Refresh (R), Logout (L), Login (I)]" -ForegroundColor DarkGray
            Write-Host ""
        }
        
        Show-Feed
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        Start-Sleep -Seconds 5
    }
}
