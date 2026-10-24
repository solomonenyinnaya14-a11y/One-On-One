"use client";

import { useActionState } from "react";
import { Field } from "@/components/ui/field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import { requestPasswordReset } from "../actions";

const initial: FormState = {};

export function ForgotForm() {
  const [state, action] = useActionState(requestPasswordReset, initial);
  if (state.message) return <FormMessage message={state.message} />;
  return (
    <form action={action} className="space-y-5" noValidate>
      <FormMessage error={state.error} />
      <Field name="email" label="Email" type="email" autoComplete="email" inputMode="email" error={state.fieldErrors?.email} />
      <SubmitButton pendingLabel="Sending…">Send reset link</SubmitButton>
    </form>
  );
}
