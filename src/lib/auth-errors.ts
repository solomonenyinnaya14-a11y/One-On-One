/** Turns Supabase auth errors into messages a person can act on. */
export function friendlyAuthError(err: { message?: string; code?: string; status?: number } | null | undefined): string {
  if (!err) return "Something went wrong. Please try again.";
  const code = err.code ?? "";
  const msg = (err.message ?? "").toLowerCase();
  if (code === "invalid_credentials" || msg.includes("invalid login")) {
    return "That email and password don't match.";
  }
  if (code === "email_not_confirmed" || msg.includes("not confirmed")) {
    return "Confirm your email first. We sent you a link when you signed up.";
  }
  if (code === "user_already_exists" || msg.includes("already registered")) {
    return "An account with that email already exists. Try signing in.";
  }
  if (code === "weak_password" || msg.includes("password")) {
    return "That password is too weak. Use at least 8 characters.";
  }
  if (code === "over_request_rate_limit" || code === "over_email_send_rate_limit" || err.status === 429) {
    return "Too many attempts. Please wait a few minutes and try again.";
  }
  return "Something went wrong. Please try again.";
}
