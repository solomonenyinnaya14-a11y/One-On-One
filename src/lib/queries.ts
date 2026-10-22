import type { createClient } from "@/lib/supabase/server";
import { sanitizeSearchTerm } from "@/lib/search";
import type { OfferingRow, ProfileRow, ProviderCard } from "@/lib/types";

type Client = NonNullable<Awaited<ReturnType<typeof createClient>>>;

export const PAGE_SIZE = 20;

export type PersonCard = ProfileRow & { provider: ProviderCard | null; offerings: OfferingRow[] };

const PERSON_COLUMNS =
  "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, created_at";
// provider_profiles has TWO foreign keys to profiles (user_id and reviewed_by),
// so an unqualified embed is ambiguous and PostgREST rejects the whole request
// (PGRST201). Always name the relationship.
const PROVIDER_REL = "provider_profiles!provider_profiles_user_id_fkey";
const PROVIDER_COLUMNS = "user_id, headline, about, languages, rating_count, rating_sum";

type RawPerson = ProfileRow & { provider_profiles?: ProviderCard | ProviderCard[] | null };

function toCard(row: RawPerson): PersonCard {
  const p = row.provider_profiles;
  const provider = Array.isArray(p) ? (p[0] ?? null) : (p ?? null);
  const { provider_profiles: _ignored, ...rest } = row;
  void _ignored;
  return { ...rest, provider, offerings: [] };
}

/**
 * People other than me that I'm allowed to see. Visibility, blocking and
 * suspension are enforced by the database policies, not here.
 */
export async function listPeople(
  supabase: Client,
  me: string,
  opts: { q?: string; providersOnly?: boolean; topicId?: string; limit?: number } = {},
): Promise<{ people: PersonCard[]; error: boolean }> {
  const limit = opts.limit ?? PAGE_SIZE;
  const topicId = opts.topicId && /^[0-9a-f-]{36}$/i.test(opts.topicId) ? opts.topicId : undefined;
  const providersOnly = Boolean(opts.providersOnly || topicId);
  const embed = providersOnly
    ? `${PROVIDER_REL}!inner(${PROVIDER_COLUMNS})`
    : `${PROVIDER_REL}(${PROVIDER_COLUMNS})`;
  const term = sanitizeSearchTerm(opts.q);

  // Providers whose bookable offerings match the search words (title), so that
  // searching "career" finds a career coach even if their name doesn't say so.
  let offeringProviderIds: string[] = [];
  if (term) {
    const { data } = await supabase
      .from("offerings_with_status")
      .select("provider_id")
      .eq("accepts_bookings", true)
      .ilike("title", `%${term}%`)
      .limit(50);
    offeringProviderIds = [...new Set((data ?? []).map((r) => r.provider_id as string))];
  }

  let topicProviderIds: string[] | null = null;
  if (topicId) {
    const { data, error } = await supabase.from("provider_topics").select("provider_id").eq("topic_id", topicId).limit(500);
    if (error) {
      console.error("topic filter failed", { code: error.code, message: error.message });
      return { people: [], error: true };
    }
    topicProviderIds = (data ?? []).map((r) => r.provider_id as string);
    if (topicProviderIds.length === 0) return { people: [], error: false };
  }

  let query = supabase
    .from("profiles")
    .select(`${PERSON_COLUMNS}, ${embed}`)
    .neq("id", me)
    .not("username", "is", null)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (topicProviderIds) query = query.in("id", topicProviderIds);
  if (term) {
    const parts = [`username.ilike."*${term}*"`, `display_name.ilike."*${term}*"`];
    if (offeringProviderIds.length) parts.push(`id.in.(${offeringProviderIds.join(",")})`);
    query = query.or(parts.join(","));
  }

  const { data, error } = await query;
  if (error) {
    console.error("listPeople failed", { code: error.code, message: error.message });
    return { people: [], error: true };
  }
  const people = ((data ?? []) as unknown as RawPerson[]).map(toCard);

  // Attach each provider's bookable offerings (best effort: a failure here still shows the people).
  const providerIds = people.filter((p) => p.provider).map((p) => p.id);
  if (providerIds.length) {
    const { data: offs } = await supabase
      .from("offerings_with_status")
      .select("id, provider_id, kind, title, description, duration_minutes, price_minor, currency, accepts_bookings")
      .in("provider_id", providerIds)
      .eq("accepts_bookings", true)
      .order("price_minor", { ascending: true });
    const byProvider = new Map<string, OfferingRow[]>();
    for (const o of (offs ?? []) as (OfferingRow & { provider_id: string })[]) {
      byProvider.set(o.provider_id, [...(byProvider.get(o.provider_id) ?? []), o]);
    }
    for (const p of people) p.offerings = byProvider.get(p.id) ?? [];
  }
  return { people, error: false };
}

export async function getPersonByUsername(
  supabase: Client,
  username: string,
): Promise<PersonCard | null> {
  const { data } = await supabase
    .from("profiles")
    .select(`${PERSON_COLUMNS}, ${PROVIDER_REL}(${PROVIDER_COLUMNS})`)
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
