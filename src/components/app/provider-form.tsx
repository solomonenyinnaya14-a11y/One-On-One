"use client";

import { useActionState } from "react";
import { saveProviderProfile } from "@/app/(app)/create/actions";
import { Field, TextArea } from "@/components/ui/field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import type { MyProvider, Topic } from "@/lib/provider-queries";

const initial: FormState = {};

export function ProviderForm({
  provider,
  topics,
  selected,
}: {
  provider: MyProvider | null;
  topics: Topic[];
  selected: string[];
}) {
  const [state, action] = useActionState(saveProviderProfile, initial);
  const e = state.fieldErrors ?? {};
  return (
    <form action={action} className="space-y-5" noValidate>
      <FormMessage error={state.error} message={state.message} />
      <Field
        name="headline"
        label="Headline"
        defaultValue={provider?.headline ?? ""}
        maxLength={120}
        hint="One line people see first, for example “Career coach for new managers”."
        error={e.headline}
      />
      <TextArea
        name="about"
        label="About you"
        defaultValue={provider?.about ?? ""}
        rows={6}
        maxLength={2000}
        hint="Your experience and how you can help. Be specific and honest."
        error={e.about}
      />
      <Field
        name="languages"
        label="Languages"
        defaultValue={(provider?.languages ?? []).join(", ")}
        hint="Optional. Separate with commas, for example English, Yoruba."
      />
      <fieldset className="card p-4">
        <legend className="px-2 text-sm font-semibold">Topics you talk about</legend>
        <p className="mb-3 text-sm text-grey-600">Choose up to 10 so people can find you.</p>
        <div className="flex flex-wrap gap-2">
          {topics.map((t) => (
            <label key={t.id} className="cursor-pointer">
              <input type="checkbox" name="topics" value={t.id} defaultChecked={selected.includes(t.id)} className="peer sr-only" />
              <span className="inline-flex min-h-10 items-center rounded-full border border-grey-200 bg-white px-4 text-sm font-semibold text-ink peer-checked:border-navy-900 peer-checked:bg-navy-900 peer-checked:text-white peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-navy-700">
                {t.name}
              </span>
            </label>
          ))}
        </div>
      </fieldset>
      <SubmitButton pendingLabel="Saving…">Save profile</SubmitButton>
    </form>
  );
}
