"use client";

import { useActionState } from "react";
import { Field } from "@/components/ui/field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import { updatePassword } from "../actions";

const initial: FormState = {};

export function ResetForm() {
  const [state, action] = useActionState(updatePassword, initial);
  return (
    <form action={action} className="space-y-5" noValidate>
      <FormMessage error={state.error} />
      <Field name="password" label="New password" type="password" autoComplete="new-password" hint="At least 8 characters." error={state.fieldErrors?.password} />
      <Field name="confirm" label="Confirm new password" type="password" autoComplete="new-password" error={state.fieldErrors?.confirm} />
      <SubmitButton pendingLabel="Saving…">Save new password</SubmitButton>
    </form>
  );
}
