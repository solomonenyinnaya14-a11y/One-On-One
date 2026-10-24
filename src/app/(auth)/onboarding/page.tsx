import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { completeOnboarding } from "@/app/(app)/actions";
import { ProfileForm } from "@/components/app/profile-form";
import { NotConfigured } from "@/components/ui/not-configured";
import { getSession } from "@/lib/session";
import { getSupabaseEnv } from "@/lib/supabase/env";

export const metadata: Metadata = { title: "Set up your profile" };

export default async function OnboardingPage() {
  if (!getSupabaseEnv()) return <NotConfigured />;

  const session = await getSession();
  if (!session) redirect("/login?next=/onboarding");
  if (session.profile.onboarding_completed_at) redirect("/discover");

  return (
    <>
      <p className="mb-3 text-xs font-bold uppercase tracking-[0.18em] text-navy-900">
        One On One
      </p>
      <h1 className="font-serif text-4xl font-medium tracking-tight">
        Let&apos;s make it easy to find you.
      </h1>
      <p className="mt-3 text-grey-600">
        Choose a username and add a little about yourself. You can update your profile anytime.
      </p>
      <div className="mt-8">
        <ProfileForm action={completeOnboarding} profile={session.profile} mode="onboarding" />
      </div>
    </>
  );
}
