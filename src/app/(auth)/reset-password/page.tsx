import type { Metadata } from "next";
import Link from "next/link";
import { NotConfigured } from "@/components/ui/not-configured";
import { getSupabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";
import { ResetForm } from "./reset-form";

export const metadata: Metadata = { title: "Choose a new password" };

export default async function ResetPasswordPage() {
  if (!getSupabaseEnv()) return <NotConfigured />;
  const supabase = await createClient();
  const { data } = (await supabase?.auth.getUser()) ?? { data: { user: null } };

  if (!data.user) {
    return (
      <>
        <h1 className="font-serif text-4xl font-medium tracking-tight">This link has expired.</h1>
        <p className="mt-3 text-grey-600">Reset links work once and for a short time. Request a new one.</p>
        <p className="mt-8">
          <Link href="/forgot-password" className="font-semibold text-navy-900 underline underline-offset-4">
            Request a new link
          </Link>
        </p>
      </>
    );
  }
  return (
    <>
      <h1 className="font-serif text-4xl font-medium tracking-tight">Choose a new password.</h1>
      <div className="mt-8">
        <ResetForm />
      </div>
    </>
  );
}
