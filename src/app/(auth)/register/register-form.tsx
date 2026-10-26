"use client";

import { useActionState } from "react";
import { Field } from "@/components/ui/field";
import { PasswordField } from "@/components/ui/password-field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import { signUp } from "../actions";

const initial: FormState = {};

export function RegisterForm() {
  const [state, action] = useActionState(signUp, initial);
  if (state.message) {
    return <FormMessage message={state.message} />;
  }
  return (
    <form action={action} className="space-y-5" noValidate>
      <FormMessage error={state.error} />
      <Field name="display_name" label="Your name" autoComplete="name" maxLength={80} error={state.fieldErrors?.display_name} />
      <Field name="email" label="Email" type="email" autoComplete="email" inputMode="email" error={state.fieldErrors?.email} />
      <PasswordField
        name="password"
        label="Password"
        autoComplete="new-password"
        hint="At least 8 characters."
        error={state.fieldErrors?.password}
      />
      <SubmitButton pendingLabel="Creating your account…">Create account</SubmitButton>
    </form>
  );
}
