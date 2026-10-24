import type { createClient } from "@/lib/supabase/server";
import { sanitizeSearchTerm } from "@/lib/search";
import type { ProfileRow } from "@/lib/types";
type Client = NonNullable<Awaited<ReturnType<typeof createClient>>>;
export const PAGE_SIZE = 20;
export type PersonCard = ProfileRow;

// Keep the core discovery query compatible with deployments where the optional
// presence migration has not been applied yet. A missing presence column must
// never make every person disappear from Discovery.
const CORE_PROFILE_COLUMNS = "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, is_discoverable, status, created_at";
const PROFILE_COLUMNS = `${CORE_PROFILE_COLUMNS}, last_seen_at, show_online_status`;
function isMissingPresenceColumn(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false;
  const message = error.message ?? "";
  return error.code === "42703" || (message.includes("column") && (message.includes("last_seen_at") || message.includes("show_online_status")));
}
function withPresenceDefaults(rows: unknown): PersonCard[] {
  return ((rows ?? []) as unknown as PersonCard[]).map((person) => ({
    ...person,
    last_seen_at: person.last_seen_at ?? null,
    show_online_status: person.show_online_status ?? true,
  }));
}
/** Messaging-first discovery. RLS remains the final authority for visibility and blocks. */
export async function listPeople(supabase: Client, me: string, opts: { q?: string; limit?: number } = {}): Promise<{ people: PersonCard[]; error: boolean }> {
  const limit = Math.min(Math.max(opts.limit ?? PAGE_SIZE, 1), 500), term = sanitizeSearchTerm(opts.q);
  const run = (columns: string) => {
    let query = supabase.from("profiles").select(columns).eq("is_discoverable", true).eq("status", "active").neq("id", me).not("username", "is", null).order("created_at", { ascending: false }).limit(limit);
    if (term) query = query.or(`username.ilike."*${term}*",display_name.ilike."*${term}*"`);
    return query;
  };
  let result = await run(PROFILE_COLUMNS);
  if (isMissingPresenceColumn(result.error)) result = await run(CORE_PROFILE_COLUMNS);
  if (result.error) { console.error("listPeople failed", { code: result.error.code, message: result.error.message }); return { people: [], error: true }; }
  return { people: withPresenceDefaults(result.data), error: false };
}
/** A chat participant may still open the other person's profile after they hide from Discovery. RLS decides whether that is allowed. */
export async function getPersonByUsername(supabase: Client, username: string): Promise<PersonCard | null> {
  const run = (columns: string) => supabase.from("profiles").select(columns).eq("username", username.toLowerCase()).eq("status", "active").maybeSingle();
  let result = await run(PROFILE_COLUMNS);
  if (isMissingPresenceColumn(result.error)) result = await run(CORE_PROFILE_COLUMNS);
  if (result.error || !result.data) return null;
  return withPresenceDefaults([result.data])[0] ?? null;
}
