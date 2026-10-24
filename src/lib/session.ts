import { redirect } from "next/navigation";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { ProfileRow } from "@/lib/types";

export type SessionContext = {
  supabase: NonNullable<Awaited<ReturnType<typeof createClient>>>;
  userId: string;
  email: string | null;
  profile: ProfileRow & { status: string };
};

/** The signed-in person and their profile, loaded once per request. */
export const getSession = cache(async (): Promise<SessionContext | null> => {
  const supabase = await createClient();
  if (!supabase) return null;
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return null;

  // Presence columns were added after the original identity migration. During
  // rollout, a database that has not applied that additive migration must still
  // allow existing users to sign in instead of silently treating their profile
  // as missing and bouncing them back to /login.
  const extended = await supabase
    .from("profiles")
    .select(
      "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, is_discoverable, timezone, status, onboarding_completed_at, created_at, last_seen_at, show_online_status",
    )
    .eq("id", auth.user.id)
    .maybeSingle();

  let profile = extended.data;
  if (extended.error) {
    const fallback = await supabase
      .from("profiles")
      .select(
        "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, is_discoverable, timezone, status, onboarding_completed_at, created_at",
      )
      .eq("id", auth.user.id)
      .maybeSingle();
    profile = fallback.data
      ? { ...fallback.data, last_seen_at: null, show_online_status: true }
      : null;
    if (fallback.error) return null;
  }
  if (!profile) return null;

  return {
    supabase,
    userId: auth.user.id,
    email: auth.user.email ?? null,
    profile: profile as SessionContext["profile"],
  };
});

/** For signed-in pages: a missing session (expired, or profile unreadable) goes to sign-in instead of crashing. */
export async function requireSession(): Promise<SessionContext> {
  const session = await getSession();
  if (!session) redirect("/login");
  return session;
}
