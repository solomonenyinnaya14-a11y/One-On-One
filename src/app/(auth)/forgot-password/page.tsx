import type { Metadata } from "next";
import Link from "next/link";
import { NotConfigured } from "@/components/ui/not-configured";
import { getSupabaseEnv } from "@/lib/supabase/env";
import { ForgotForm } from "./forgot-form";

export const metadata: Metadata = { title: "Reset your password" };

export default function ForgotPasswordPage() {
  if (!getSupabaseEnv()) return <NotConfigured />;
  return (
    <>
      <h1 className="font-serif text-4xl font-medium tracking-tight">Reset your password.</h1>
      <p className="mt-3 text-grey-600">Enter your email and we&apos;ll send you a link to choose a new one.</p>
      <div className="mt-8">
        <ForgotForm />
      </div>
      <p className="mt-8 text-center">
        <Link href="/login" className="font-semibold text-navy-900 underline underline-offset-4">
          Back to sign in
        </Link>
      </p>
    </>
  );
}
