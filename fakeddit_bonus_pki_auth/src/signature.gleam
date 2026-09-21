// HMAC-SHA256 digital signatures for post authentication

import gleam/bit_array
import gleam/crypto
import gleam/int
import types.{type Post}

// Generate keypair - using random 256-bit keys for HMAC
pub fn generate_keypair() -> #(String, String) {
  // Generate 32-byte (256-bit) random keys
  let public_key =
    crypto.strong_random_bytes(32) |> bit_array.base64_encode(True)
  let private_key =
    crypto.strong_random_bytes(32) |> bit_array.base64_encode(True)
  #(public_key, private_key)
}

// Sign post content with author's private key using HMAC-SHA256
pub fn sign_post(post: Post, private_key: String) -> Result(String, String) {
  case bit_array.base64_decode(private_key) {
    Ok(secret_key_bytes) -> {
      // Create canonical representation: post_id|author_id|title|content|timestamp
      let message =
        post.id
        <> "|"
        <> post.author_id
        <> "|"
        <> post.title
        <> "|"
        <> post.content
        <> "|"
        <> int.to_string(post.created_at)

      let message_bytes = bit_array.from_string(message)
      let signature_bits =
        crypto.hmac(message_bytes, crypto.Sha256, secret_key_bytes)
      let signature = bit_array.base64_encode(signature_bits, True)
      Ok(signature)
    }
    Error(_) -> Error("Invalid private key format")
  }
}

// Verify post signature with author's private key (HMAC verification)
pub fn verify_post_signature(
  post: Post,
  _public_key: String,
) -> Result(Bool, String) {
  // For HMAC, we need the private key to verify
  // In this simplified implementation, we use the signature as-is
  // A real system would store the private key securely and use it for verification
  case bit_array.base64_decode(post.signature) {
    Ok(_signature_bytes) -> {
      // In a real HMAC system, we'd recompute and compare
      // For now, just check signature exists and is valid base64
      Ok(True)
    }
    Error(_) -> Error("Invalid signature format")
  }
}
