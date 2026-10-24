import type { createClient } from "@/lib/supabase/server";
import { sanitizeSearchTerm } from "@/lib/search";
import type { ProfileRow } from "@/lib/types";
type Client = NonNullable<Awaited<ReturnType<typeof createClient>>>;
export const PAGE_SIZE = 20;
export type PersonCard = ProfileRow;
const PROFILE_COLUMNS = "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, is_discoverable, status, created_at, last_seen_at, show_online_status";
/** Messaging-first discovery. RLS remains the final authority for visibility and blocks. */
export async function listPeople(supabase: Client, me: string, opts: { q?: string; limit?: number } = {}): Promise<{ people: PersonCard[]; error: boolean }> {
  const limit = Math.min(Math.max(opts.limit ?? PAGE_SIZE, 1), 500), term = sanitizeSearchTerm(opts.q);
  let query = supabase.from("profiles").select(PROFILE_COLUMNS).eq("is_discoverable", true).eq("status", "active").neq("id", me).not("username", "is", null).order("created_at", { ascending: false }).limit(limit);
  if (term) query = query.or(`username.ilike."*${term}*",display_name.ilike."*${term}*"`);
  const { data, error } = await query;
  if (error) { console.error("listPeople failed", { code: error.code, message: error.message }); return { people: [], error: true }; }
  return { people: (data ?? []) as unknown as PersonCard[], error: false };
}
/** A chat participant may still open the other person's profile after they hide from Discovery. RLS decides whether that is allowed. */
export async function getPersonByUsername(supabase: Client, username: string): Promise<PersonCard | null> {
  const { data } = await supabase.from("profiles").select(PROFILE_COLUMNS).eq("username", username.toLowerCase()).eq("status", "active").maybeSingle();
  return data ? data as unknown as PersonCard : null;
}