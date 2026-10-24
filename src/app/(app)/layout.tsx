import { redirect } from "next/navigation";
import { BottomNav } from "@/components/app/bottom-nav";
import { PresenceHeartbeat } from "@/components/app/presence";
import { NotConfigured } from "@/components/ui/not-configured";
import { getSession } from "@/lib/session";
import { getSupabaseEnv } from "@/lib/supabase/env";
import { signOut } from "../(auth)/actions";

// Everything here depends on who is signed in, so it is never prerendered.
export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  if (!getSupabaseEnv()) return <NotConfigured />;

  const session = await getSession();
  if (!session) redirect("/login");

  if (session.profile.status !== "active") {
    return (
      <main id="main" className="mx-auto max-w-md px-5 py-20">
        <h1 className="font-serif text-3xl font-medium">Your account is suspended.</h1>
        <p className="mt-4 text-grey-600">
          You can&apos;t use One On One while the suspension is in place. If you think this is a
          mistake, contact support.
        </p>
        <form action={signOut} className="mt-8">
          <button className="min-h-12 rounded-full border-2 border-ink px-7 font-semibold">Sign out</button>
        </form>
      </main>
    );
  }
  if (!session.profile.onboarding_completed_at) redirect("/onboarding");

  const { data: unread } = await session.supabase.rpc("my_unread_count");

  return (
    <>
      <PresenceHeartbeat />
      <main id="main" className="mx-auto min-h-dvh max-w-2xl px-5 pb-28 pt-6">
        {children}
      </main>
      <BottomNav unread={Number(unread ?? 0)} />
    </>
  );
}
