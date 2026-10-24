"use client";

import { useActionState, useState } from "react";
import { FormMessage } from "@/components/ui/form-message";
import { SubmitButton } from "@/components/ui/submit-button";
import { Field, TextArea } from "@/components/ui/field";
import type { FormState } from "@/lib/form-state";
import { formatNaira } from "@/lib/format";
import type { MyOffering, Topic } from "@/lib/provider-queries";
import { nairaToMinor, OFFERING_DURATIONS } from "@/lib/provider-validation";

const initial: FormState = {};

type Props = {
  action: (prev: FormState, form: FormData) => Promise<FormState>;
  topics: Topic[];
  offering?: MyOffering;
  submitLabel: string;
  /** Format can't be changed once an offering exists. */
  lockKind?: boolean;
};

export function OfferingForm({ action, topics, offering, submitLabel, lockKind }: Props) {
  const [state, formAction] = useActionState(action, initial);
  const e = state.fieldErrors ?? {};
  const [kind, setKind] = useState<string>(offering?.kind ?? "text");
  const [title, setTitle] = useState(offering?.title ?? "");
  const [description, setDescription] = useState(offering?.description ?? "");
  const [duration, setDuration] = useState(String(offering?.duration_minutes ?? 30));
  const [price, setPrice] = useState(offering ? String(offering.price_minor / 100) : "");
  const [topicId, setTopicId] = useState(offering?.topic_id ?? "");

  const minor = nairaToMinor(price);
  const topicName = topics.find((t) => t.id === topicId)?.name;

  return (
    <form action={formAction} className="space-y-5" noValidate>
      <FormMessage error={state.error} message={state.message} />

      <fieldset>
        <legend className="block text-sm font-semibold">Format</legend>
        <div className="mt-1.5 grid grid-cols-2 gap-3">
          {(["text", "voice"] as const).map((k) => (
            <label key={k} className={lockKind && kind !== k ? "pointer-events-none opacity-40" : "cursor-pointer"}>
              <input
                type="radio"
                name="kind"
                value={k}
                checked={kind === k}
                onChange={() => setKind(k)}
                disabled={lockKind && kind !== k}
                className="peer sr-only"
              />
              <span className="card block p-4 text-center peer-checked:border-navy-900 peer-checked:ring-2 peer-checked:ring-navy-900 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-navy-700">
                <span className="block font-semibold">{k === "text" ? "Text chat" : "Voice call"}</span>
                <span className="block text-sm text-grey-600">{k === "text" ? "Written conversation" : "Spoken conversation"}</span>
              </span>
            </label>
          ))}
        </div>
        {lockKind ? <input type="hidden" name="kind" value={kind} /> : null}
        {e.kind ? <p role="alert" className="mt-1.5 text-sm font-medium">{e.kind}</p> : null}
      </fieldset>

      <Field name="title" label="Title" value={title} onChange={(ev) => setTitle(ev.target.value)} maxLength={80} placeholder="Career direction in 30 minutes" error={e.title} />
      <TextArea name="description" label="What people get" value={description} onChange={(ev) => setDescription(ev.target.value)} rows={4} maxLength={500} hint="Optional. What you'll cover and who it's for. Up to 500 characters." error={e.description} />

      <div>
        <label htmlFor="field-topic_id" className="block text-sm font-semibold">Category</label>
        <select id="field-topic_id" name="topic_id" value={topicId} onChange={(ev) => setTopicId(ev.target.value)} className="mt-1.5 block min-h-12 w-full rounded-xl border-2 border-grey-200 bg-white px-4 text-base">
          <option value="">No category</option>
          {topics.map((t) => (
            <option key={t.id} value={t.id}>{t.name}</option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label htmlFor="field-duration" className="block text-sm font-semibold">Length</label>
          <select id="field-duration" name="duration" value={duration} onChange={(ev) => setDuration(ev.target.value)} className="mt-1.5 block min-h-12 w-full rounded-xl border-2 border-grey-200 bg-white px-4 text-base">
            {OFFERING_DURATIONS.map((d) => (
              <option key={d} value={d}>{d} minutes</option>
            ))}
          </select>
          {e.duration ? <p role="alert" className="mt-1.5 text-sm font-medium">{e.duration}</p> : null}
        </div>
        <Field name="price" label="Price (₦)" inputMode="decimal" value={price} onChange={(ev) => setPrice(ev.target.value)} placeholder="5000" error={e.price} />
      </div>

      <section aria-label="Preview" className="rounded-2xl bg-navy-50 p-4">
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-grey-600">Preview: how people will see it</p>
        <div className="card p-4">
          <p className="font-semibold">{title.trim() || "Your title"}</p>
          <p className="text-sm text-grey-600">
            {kind === "voice" ? "Voice" : "Text"} · {duration} min · {minor !== null && minor >= 100 ? formatNaira(minor) : "₦ price"}
            {topicName ? ` · ${topicName}` : ""}
          </p>
          {description.trim() ? <p className="mt-2 text-sm">{description.trim()}</p> : null}
        </div>
      </section>

      <SubmitButton pendingLabel="Saving…">{submitLabel}</SubmitButton>
    </form>
  );
}
