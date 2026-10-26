"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Field } from "@/components/ui/field";
import { PasswordField } from "@/components/ui/password-field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import { signIn } from "../actions";

const initial: FormState = {};

export function LoginForm({ next }: { next: string }) {
  const [state, action] = useActionState(signIn, initial);
  return (
    <form action={action} className="space-y-5" noValidate>
      <input type="hidden" name="next" value={next} />
      <FormMessage error={state.error} message={state.message} />
      <Field name="email" label="Email" type="email" autoComplete="email" inputMode="email" error={state.fieldErrors?.email} />
      <PasswordField name="password" label="Password" autoComplete="current-password" error={state.fieldErrors?.password} />
      <SubmitButton pendingLabel="Signing in…">Sign in</SubmitButton>
      <p className="text-center text-sm">
        <Link href="/forgot-password" className="font-semibold text-navy-900 underline underline-offset-4">
          Forgot your password?
        </Link>
      </p>
    </form>
  );
}
