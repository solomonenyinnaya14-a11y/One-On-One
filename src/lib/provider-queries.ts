import type { createClient } from "@/lib/supabase/server";

type Client = NonNullable<Awaited<ReturnType<typeof createClient>>>;

export type MyProvider = {
  status: "draft" | "pending_review" | "approved" | "rejected" | "suspended";
  headline: string | null;
  about: string | null;
  languages: string[];
  rejection_reason: string | null;
  rating_count: number;
  rating_sum: number;
};

export type Topic = { id: string; name: string; slug: string };

export type MyOffering = {
  id: string;
  kind: "text" | "voice";
  title: string;
  description: string | null;
  duration_minutes: number;
  price_minor: number;
  topic_id: string | null;
  is_active: boolean;
  requires_subscription: boolean;
  accepts_bookings: boolean;
  created_at: string;
};

export async function getMyProvider(supabase: Client, userId: string): Promise<MyProvider | null> {
  const { data } = await supabase
    .from("provider_profiles")
    .select("status, headline, about, languages, rejection_reason, rating_count, rating_sum")
    .eq("user_id", userId)
    .maybeSingle();
  return (data as MyProvider | null) ?? null;
}

export async function getTopics(supabase: Client): Promise<Topic[]> {
  const { data } = await supabase.from("topics").select("id, name, slug").eq("is_active", true).order("name");
  return (data ?? []) as Topic[];
}

export async function getMyTopicIds(supabase: Client, userId: string): Promise<string[]> {
  const { data } = await supabase.from("provider_topics").select("topic_id").eq("provider_id", userId);
  return (data ?? []).map((r) => r.topic_id as string);
}

export async function getMyOfferings(supabase: Client, userId: string): Promise<{ offerings: MyOffering[]; error: boolean }> {
  const { data, error } = await supabase
    .from("offerings_with_status")
    .select("id, kind, title, description, duration_minutes, price_minor, topic_id, is_active, requires_subscription, accepts_bookings, created_at")
    .eq("provider_id", userId)
    .order("created_at", { ascending: true });
  if (error) {
    console.error("getMyOfferings failed", { code: error.code, message: error.message });
    return { offerings: [], error: true };
  }
  return { offerings: (data ?? []) as MyOffering[], error: false };
}

export async function getMyOffering(supabase: Client, userId: string, id: string): Promise<MyOffering | null> {
  const { data } = await supabase
    .from("offerings_with_status")
    .select("id, kind, title, description, duration_minutes, price_minor, topic_id, is_active, requires_subscription, accepts_bookings, created_at")
    .eq("id", id)
    .eq("provider_id", userId)
    .maybeSingle();
  return (data as MyOffering | null) ?? null;
}
