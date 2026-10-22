import type { createClient } from "@/lib/supabase/server";
import { sanitizeSearchTerm } from "@/lib/search";
import type { OfferingRow, ProfileRow, ProviderCard } from "@/lib/types";

type Client = NonNullable<Awaited<ReturnType<typeof createClient>>>;

export const PAGE_SIZE = 20;

export type PersonCard = ProfileRow & { provider: ProviderCard | null };

const PERSON_COLUMNS =
  "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, created_at";
const PROVIDER_COLUMNS = "user_id, headline, about, languages, rating_count, rating_sum";

type RawPerson = ProfileRow & { provider_profiles?: ProviderCard | ProviderCard[] | null };

function toCard(row: RawPerson): PersonCard {
  const p = row.provider_profiles;
  const provider = Array.isArray(p) ? (p[0] ?? null) : (p ?? null);
  const { provider_profiles: _ignored, ...rest } = row;
  void _ignored;
  return { ...rest, provider };
}

/**
 * People other than me that I'm allowed to see. Visibility, blocking and
 * suspension are enforced by the database policies, not here.
 */
export async function listPeople(
  supabase: Client,
  me: string,
  opts: { q?: string; providersOnly?: boolean; limit?: number } = {},
): Promise<{ people: PersonCard[]; error: boolean }> {
  const limit = opts.limit ?? PAGE_SIZE;
  const embed = opts.providersOnly
    ? `provider_profiles!inner(${PROVIDER_COLUMNS})`
    : `provider_profiles(${PROVIDER_COLUMNS})`;

  let query = supabase
    .from("profiles")
    .select(`${PERSON_COLUMNS}, ${embed}`)
    .neq("id", me)
    .not("username", "is", null)
    .order("created_at", { ascending: false })
    .limit(limit);

  const term = sanitizeSearchTerm(opts.q);
  if (term) {
    query = query.or(`username.ilike."*${term}*",display_name.ilike."*${term}*"`);
  }

  const { data, error } = await query;
  if (error) return { people: [], error: true };
  return { people: ((data ?? []) as unknown as RawPerson[]).map(toCard), error: false };
}

export async function getPersonByUsername(
  supabase: Client,
  username: string,
): Promise<PersonCard | null> {
  const { data } = await supabase
    .from("profiles")
    .select(`${PERSON_COLUMNS}, provider_profiles(${PROVIDER_COLUMNS})`)
    .eq("username", username.toLowerCase())
    .maybeSingle();
  return data ? toCard(data as unknown as RawPerson) : null;
}

export async function getOfferings(supabase: Client, providerId: string): Promise<OfferingRow[]> {
  const { data } = await supabase
    .from("offerings_with_status")
    .select("id, kind, title, description, duration_minutes, price_minor, currency, accepts_bookings")
    .eq("provider_id", providerId)
    .eq("is_active", true)
    .order("created_at", { ascending: true });
  return (data ?? []) as OfferingRow[];
}
