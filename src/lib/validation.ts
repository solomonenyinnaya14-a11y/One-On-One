/** Input rules shared by forms. The database enforces the same limits again. */

export const USERNAME_PATTERN = /^[a-z0-9_]{3,30}$/;

const RESERVED_USERNAMES = new Set([
  "admin", "administrator", "support", "help", "official", "oneonone", "staff",
  "moderator", "system", "root", "me", "login", "register", "settings", "api",
]);

export function normalizeUsername(raw: string): string {
  return raw.trim().replace(/^@/, "").toLowerCase();
}

/** Returns an error message, or null when the username is acceptable. */
export function validateUsername(raw: string): string | null {
  const value = normalizeUsername(raw);
  if (!value) return "Choose a username.";
  if (value.length < 3) return "Usernames need at least 3 characters.";
  if (value.length > 30) return "Usernames can be at most 30 characters.";
  if (!USERNAME_PATTERN.test(value)) {
    return "Use only lowercase letters, numbers and underscores.";
  }
  if (RESERVED_USERNAMES.has(value)) return "That username is not available.";
  return null;
}

export function validateDisplayName(raw: string): string | null {
  const value = raw.trim();
  if (!value) return "Enter your name.";
  if (value.length > 80) return "Names can be at most 80 characters.";
  return null;
}

export function validateEmail(raw: string): string | null {
  const value = raw.trim();
  if (!value) return "Enter your email address.";
  if (value.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    return "Enter a valid email address.";
  }
  return null;
}

export function validatePassword(raw: string): string | null {
  if (raw.length < 8) return "Use at least 8 characters.";
  if (raw.length > 72) return "Use at most 72 characters.";
  return null;
}

export function validateBio(raw: string): string | null {
  return raw.length > 500 ? "Keep your bio under 500 characters." : null;
}

/** "a, b ,c" -> ["a","b","c"], trimmed, de-duplicated, at most 10, 30 chars each. */
export function parseInterests(raw: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const part of raw.split(",")) {
    const item = part.trim().slice(0, 30);
    const key = item.toLowerCase();
    if (!item || seen.has(key)) continue;
    seen.add(key);
    out.push(item);
    if (out.length === 10) break;
  }
  return out;
}
