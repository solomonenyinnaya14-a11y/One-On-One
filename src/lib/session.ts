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

  const { data: profile } = await supabase
    .from("profiles")
    .select(
      "id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats, is_discoverable, timezone, status, onboarding_completed_at, created_at",
    )
    .eq("id", auth.user.id)
    .maybeSingle();
  if (!profile) return null;

  return {
    supabase,
    userId: auth.user.id,
    email: auth.user.email ?? null,
    profile: profile as SessionContext["profile"],
  };
});
