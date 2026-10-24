import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { FormMessage } from "@/components/ui/form-message";
import { NotConfigured } from "@/components/ui/not-configured";
import { safeNextPath } from "@/lib/navigation";
import { getSupabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Sign in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  if (!getSupabaseEnv()) return <NotConfigured />;
  const { next, error } = await searchParams;
  const safeNext = safeNextPath(next);

  const supabase = await createClient();
  const { data } = (await supabase?.auth.getUser()) ?? { data: { user: null } };
  if (data.user) redirect(safeNext);

  return (
    <>
      <h1 className="font-serif text-4xl font-medium tracking-tight">Welcome back.</h1>
      <p className="mt-3 text-grey-600">Sign in to pick up your conversations.</p>
      <div className="mt-8 space-y-5">
        <FormMessage error={error === "link" ? "That email link couldn't be used here. If you've already confirmed your email, just sign in. Otherwise request a new link." : undefined} />
        <LoginForm next={safeNext} />
      </div>
      <p className="mt-8 text-center text-grey-600">
        New here?{" "}
        <Link href="/register" className="font-semibold text-navy-900 underline underline-offset-4">
          Create an account
        </Link>
      </p>
    </>
  );
}
