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
  if (session.profile.onboarding_completed_at) redirect("/home");

  return (
    <>
      <h1 className="font-serif text-4xl font-medium tracking-tight">Welcome. Let&apos;s set you up.</h1>
      <p className="mt-3 text-grey-600">Choose a username so people can find you. You can change everything later.</p>
      <div className="mt-8">
        <ProfileForm action={completeOnboarding} profile={session.profile} mode="onboarding" />
      </div>
    </>
  );
}
