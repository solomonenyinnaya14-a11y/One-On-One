"use client";

import { useActionState } from "react";
import { Field, TextArea } from "@/components/ui/field";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import type { FormState } from "@/lib/form-state";
import type { ProfileRow } from "@/lib/types";

type Props = {
  action: (prev: FormState, form: FormData) => Promise<FormState>;
  profile: Pick<ProfileRow, "username" | "display_name" | "bio" | "interests" | "expertise"> &
    Partial<Pick<ProfileRow, "accepts_free_chats" | "is_discoverable">>;
  mode: "onboarding" | "edit";
};

const initial: FormState = {};

export function ProfileForm({ action, profile, mode }: Props) {
  const [state, formAction] = useActionState(action, initial);
  const e = state.fieldErrors ?? {};
  return (
    <form action={formAction} className="space-y-5" noValidate>
      <FormMessage error={state.error} message={state.message} />
      <Field name="display_name" label="Name" defaultValue={profile.display_name} maxLength={80} autoComplete="name" error={e.display_name} />
      <Field
        name="username"
        label="Username"
        defaultValue={profile.username ?? ""}
        maxLength={31}
        autoCapitalize="none"
        autoCorrect="off"
        spellCheck={false}
        hint="3–30 characters: lowercase letters, numbers and underscores. People find you with this."
        error={e.username}
      />
      <TextArea name="bio" label="About you" defaultValue={profile.bio ?? ""} rows={4} maxLength={500} hint="Optional. Up to 500 characters." error={e.bio} />
      <Field name="expertise" label="What you know about" defaultValue={profile.expertise ?? ""} maxLength={80} hint="Optional, for example “Career changes”." error={e.expertise} />
      <Field name="interests" label="Interests" defaultValue={(profile.interests ?? []).join(", ")} hint="Optional. Separate with commas, up to 10." />

      {mode === "edit" ? (
        <fieldset className="space-y-4 card p-4">
          <legend className="px-2 text-sm font-semibold">Privacy</legend>
          <label className="flex items-start gap-3">
            <input type="checkbox" name="is_discoverable" defaultChecked={profile.is_discoverable ?? true} className="mt-1 h-5 w-5 accent-navy-900" />
            <span>
              <span className="block font-semibold">Show me in Discover and search</span>
              <span className="block text-sm text-grey-600">Turn this off and people can&apos;t find you. Approved providers stay listed only while this is on.</span>
            </span>
          </label>
          <label className="flex items-start gap-3">
            <input type="checkbox" name="accepts_free_chats" defaultChecked={profile.accepts_free_chats ?? true} className="mt-1 h-5 w-5 accent-navy-900" />
            <span>
              <span className="block font-semibold">Allow message requests</span>
              <span className="block text-sm text-grey-600">Let people you haven&apos;t talked to send you a first message.</span>
            </span>
          </label>
        </fieldset>
      ) : null}

      <SubmitButton pendingLabel="Saving…">{mode === "onboarding" ? "Continue" : "Save changes"}</SubmitButton>
    </form>
  );
}
