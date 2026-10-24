/**
 * Makes free text safe to place inside a PostgREST filter such as
 * `username.ilike.%term%`. Characters that have meaning in filters or in LIKE
 * patterns are removed instead of escaped, which keeps the behaviour obvious.
 */
export function sanitizeSearchTerm(raw: string | null | undefined): string {
  if (!raw) return "";
  return raw
    .replace(/^@/, "")
    .replace(/[,()%_*\\"'`:.;{}[\]<>|&=+!?#$^~/]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 40);
}
