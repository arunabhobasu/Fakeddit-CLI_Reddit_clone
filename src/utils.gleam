import gleam/int

pub fn generate_id(prefix: String) -> String {
  let timestamp = get_timestamp()
  let random = random_int(1000, 999_999)
  prefix <> "_" <> int.to_string(timestamp) <> "_" <> int.to_string(random)
}

@external(erlang, "rand", "uniform")
fn erlang_uniform(n: Int) -> Int

pub fn random_int(min: Int, max: Int) -> Int {
  let range = max - min + 1
  min + { erlang_uniform(range) - 1 }
}

@external(erlang, "erlang", "system_time")
pub fn system_time(unit: Int) -> Int

pub fn get_timestamp() -> Int {
  system_time(1_000_000)
}

pub fn random_name() -> String {
  let first = random_first_name()
  let last = random_last_name()
  let number = random_int(1, 999)
  first <> last <> int.to_string(number)
}

fn random_first_name() -> String {
  let index = random_int(0, 49)
  case index {
    0 -> "Alice"
    1 -> "Bob"
    2 -> "Charlie"
    3 -> "Diana"
    4 -> "Eve"
    5 -> "Frank"
    6 -> "Grace"
    7 -> "Henry"
    8 -> "Ivy"
    9 -> "Jack"
    10 -> "Kate"
    11 -> "Leo"
    12 -> "Maya"
    13 -> "Noah"
    14 -> "Olive"
    15 -> "Peter"
    16 -> "Quinn"
    17 -> "Rose"
    18 -> "Sam"
    19 -> "Tina"
    20 -> "Uma"
    21 -> "Victor"
    22 -> "Wendy"
    23 -> "Xander"
    24 -> "Yara"
    25 -> "Zoe"
    26 -> "Alex"
    27 -> "Blake"
    28 -> "Casey"
    29 -> "Drew"
    30 -> "Ellis"
    31 -> "Finn"
    32 -> "Gray"
    33 -> "Harper"
    34 -> "Iris"
    35 -> "Jesse"
    36 -> "Kai"
    37 -> "Luna"
    38 -> "Max"
    39 -> "Nova"
    40 -> "Oscar"
    41 -> "Piper"
    42 -> "River"
    43 -> "Sage"
    44 -> "Taylor"
    45 -> "Ash"
    46 -> "Jordan"
    47 -> "Morgan"
    48 -> "Riley"
    _ -> "Sky"
  }
}

fn random_last_name() -> String {
  let index = random_int(0, 49)
  case index {
    0 -> "Smith"
    1 -> "Johnson"
    2 -> "Williams"
    3 -> "Brown"
    4 -> "Jones"
    5 -> "Garcia"
    6 -> "Miller"
    7 -> "Davis"
    8 -> "Rodriguez"
    9 -> "Martinez"
    10 -> "Hernandez"
    11 -> "Lopez"
    12 -> "Gonzalez"
    13 -> "Wilson"
    14 -> "Anderson"
    15 -> "Thomas"
    16 -> "Taylor"
    17 -> "Moore"
    18 -> "Jackson"
    19 -> "Martin"
    20 -> "Lee"
    21 -> "Perez"
    22 -> "Thompson"
    23 -> "White"
    24 -> "Harris"
    25 -> "Sanchez"
    26 -> "Clark"
    27 -> "Ramirez"
    28 -> "Lewis"
    29 -> "Robinson"
    30 -> "Walker"
    31 -> "Young"
    32 -> "Allen"
    33 -> "King"
    34 -> "Wright"
    35 -> "Scott"
    36 -> "Torres"
    37 -> "Nguyen"
    38 -> "Hill"
    39 -> "Flores"
    40 -> "Green"
    41 -> "Adams"
    42 -> "Nelson"
    43 -> "Baker"
    44 -> "Hall"
    45 -> "Rivera"
    46 -> "Campbell"
    47 -> "Mitchell"
    48 -> "Carter"
    _ -> "Roberts"
  }
}

// Returns random word from common English vocabulary
pub fn random_word() -> String {
  let index = random_int(0, 99)
  case index {
    0 -> "the"
    1 -> "be"
    2 -> "to"
    3 -> "of"
    4 -> "and"
    5 -> "a"
    6 -> "in"
    7 -> "that"
    8 -> "have"
    9 -> "it"
    10 -> "for"
    11 -> "not"
    12 -> "on"
    13 -> "with"
    14 -> "he"
    15 -> "as"
    16 -> "you"
    17 -> "do"
    18 -> "at"
    19 -> "this"
    20 -> "but"
    21 -> "his"
    22 -> "by"
    23 -> "from"
    24 -> "they"
    25 -> "we"
    26 -> "say"
    27 -> "her"
    28 -> "she"
    29 -> "or"
    30 -> "an"
    31 -> "will"
    32 -> "my"
    33 -> "one"
    34 -> "all"
    35 -> "would"
    36 -> "there"
    37 -> "their"
    38 -> "what"
    39 -> "so"
    40 -> "up"
    41 -> "out"
    42 -> "if"
    43 -> "about"
    44 -> "who"
    45 -> "get"
    46 -> "which"
    47 -> "go"
    48 -> "me"
    49 -> "when"
    50 -> "make"
    51 -> "can"
    52 -> "like"
    53 -> "time"
    54 -> "no"
    55 -> "just"
    56 -> "him"
    57 -> "know"
    58 -> "take"
    59 -> "people"
    60 -> "into"
    61 -> "year"
    62 -> "your"
    63 -> "good"
    64 -> "some"
    65 -> "could"
    66 -> "them"
    67 -> "see"
    68 -> "other"
    69 -> "than"
    70 -> "then"
    71 -> "now"
    72 -> "look"
    73 -> "only"
    74 -> "come"
    75 -> "its"
    76 -> "over"
    77 -> "think"
    78 -> "also"
    79 -> "back"
    80 -> "after"
    81 -> "use"
    82 -> "two"
    83 -> "how"
    84 -> "our"
    85 -> "work"
    86 -> "first"
    87 -> "well"
    88 -> "way"
    89 -> "even"
    90 -> "new"
    91 -> "want"
    92 -> "because"
    93 -> "any"
    94 -> "these"
    95 -> "give"
    96 -> "day"
    97 -> "most"
    98 -> "us"
    _ -> "fakeddit"
  }
}

pub fn generate_text(word_count: Int) -> String {
  generate_text_helper(word_count, [])
}

fn generate_text_helper(remaining: Int, acc: List(String)) -> String {
  case remaining {
    0 -> join_words(acc, "")
    n -> {
      let word = random_word()
      generate_text_helper(n - 1, [word, ..acc])
    }
  }
}

fn join_words(words: List(String), acc: String) -> String {
  case words {
    [] -> acc
    [first, ..rest] ->
      case acc {
        "" -> join_words(rest, first)
        _ -> join_words(rest, acc <> " " <> first)
      }
  }
}

// Zipf distribution makes a few items very popular (power-law behavior)
pub fn zipf_value(rank: Int, n: Int, s: Float) -> Float {
  let rank_float = int.to_float(rank)
  let numerator = 1.0 /. power(rank_float, s)
  let denominator = zipf_normalizer(n, s)
  numerator /. denominator
}

fn zipf_normalizer(n: Int, s: Float) -> Float {
  zipf_normalizer_helper(1, n, s, 0.0)
}

fn zipf_normalizer_helper(current: Int, n: Int, s: Float, acc: Float) -> Float {
  case current > n {
    True -> acc
    False -> {
      let current_float = int.to_float(current)
      let new_acc = acc +. 1.0 /. power(current_float, s)
      zipf_normalizer_helper(current + 1, n, s, new_acc)
    }
  }
}

@external(erlang, "math", "pow")
fn power(base: Float, exponent: Float) -> Float

// Converts random value to Zipf rank (popular items selected more often)
pub fn calculate_zipf_rank(total_items: Int, random_val: Float) -> Int {
  let s = 1.5
  calculate_zipf_rank_helper(1, total_items, random_val, 0.0, s)
}

fn calculate_zipf_rank_helper(
  rank: Int,
  total: Int,
  target: Float,
  cumulative: Float,
  s: Float,
) -> Int {
  case rank > total {
    True -> total
    False -> {
      let prob = zipf_value(rank, total, s)
      let new_cumulative = cumulative +. prob
      case new_cumulative >=. target {
        True -> rank
        False ->
          calculate_zipf_rank_helper(rank + 1, total, target, new_cumulative, s)
      }
    }
  }
}

// Sample from Zipf distribution - lower indices are more popular
pub fn zipf_sample(total_items: Int) -> Int {
  case total_items {
    0 -> 0
    _ -> {
      let random_val = int.to_float(random_int(1, 1000)) /. 1000.0
      let rank = calculate_zipf_rank(total_items, random_val)
      rank - 1
    }
  }
}

pub fn take_random_item(items: List(a)) -> Result(a, Nil) {
  case items {
    [] -> Error(Nil)
    list -> {
      let index = random_int(0, list_length(items) - 1)
      list_at(list, index)
    }
  }
}

fn list_length(items: List(a)) -> Int {
  list_length_helper(items, 0)
}

fn list_length_helper(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> list_length_helper(rest, acc + 1)
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
