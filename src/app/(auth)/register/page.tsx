import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { NotConfigured } from "@/components/ui/not-configured";
import { getSupabaseEnv } from "@/lib/supabase/env";
import { createClient } from "@/lib/supabase/server";
import { RegisterForm } from "./register-form";

export const metadata: Metadata = { title: "Create your account" };

export default async function RegisterPage() {
  if (!getSupabaseEnv()) return <NotConfigured />;
  const supabase = await createClient();
  const { data } = (await supabase?.auth.getUser()) ?? { data: { user: null } };
  if (data.user) redirect("/home");

  return (
    <>
      <h1 className="font-serif text-4xl font-medium tracking-tight">Join One On One.</h1>
      <p className="mt-3 text-grey-600">Create an account to talk with people worth talking to.</p>
      <div className="mt-8">
        <RegisterForm />
      </div>
      <p className="mt-8 text-center text-grey-600">
        Already have an account?{" "}
        <Link href="/login" className="font-semibold text-navy-900 underline underline-offset-4">
          Sign in
        </Link>
      </p>
    </>
  );
}
