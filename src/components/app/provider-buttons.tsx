"use client";

import { useState, useTransition } from "react";
import { reviewProvider } from "@/app/(app)/admin/actions";
import { setOfferingActive, submitApplication, withdrawApplication } from "@/app/(app)/create/actions";

function useAction() {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return { pending, error, setError, start };
}

const primary = "min-h-12 w-full rounded-full bg-navy-900 px-7 font-semibold text-white hover:bg-navy-800 disabled:opacity-60";
const secondary = "min-h-12 w-full rounded-full border-2 border-ink bg-white px-7 font-semibold disabled:opacity-60";

export function SubmitApplicationButton() {
  const { pending, error, setError, start } = useAction();
  return (
    <div>
      <button type="button" disabled={pending} className={primary} onClick={() => start(async () => setError((await submitApplication()).error ?? null))}>
        {pending ? "Submitting…" : "Submit for review"}
      </button>
      {error ? <p role="alert" className="mt-2 text-sm font-medium">{error}</p> : null}
    </div>
  );
}

export function WithdrawApplicationButton() {
  const { pending, error, setError, start } = useAction();
  return (
    <div>
      <button type="button" disabled={pending} className={secondary} onClick={() => start(async () => setError((await withdrawApplication()).error ?? null))}>
        {pending ? "Working…" : "Withdraw and keep editing"}
      </button>
      {error ? <p role="alert" className="mt-2 text-sm font-medium">{error}</p> : null}
    </div>
  );
}

export function PauseResumeButton({ id, active }: { id: string; active: boolean }) {
  const { pending, error, setError, start } = useAction();
  return (
    <div>
      <button
        type="button"
        disabled={pending}
        className="min-h-11 rounded-full border border-grey-300 bg-white px-5 text-sm font-semibold disabled:opacity-60"
        onClick={() => start(async () => setError((await setOfferingActive(id, !active)).error ?? null))}
      >
        {pending ? "…" : active ? "Pause" : "Resume"}
      </button>
      {error ? <p role="alert" className="mt-1 text-sm font-medium">{error}</p> : null}
    </div>
  );
}

export function ReviewButtons({ userId }: { userId: string }) {
  const { pending, error, setError, start } = useAction();
  const [reason, setReason] = useState("");
  return (
    <div className="mt-4 space-y-3">
      <label className="block text-sm font-semibold" htmlFor={`reason-${userId}`}>Reason (required to reject)</label>
      <input id={`reason-${userId}`} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} className="block min-h-12 w-full rounded-xl border-2 border-grey-200 bg-white px-4" />
      <div className="grid grid-cols-2 gap-3">
        <button type="button" disabled={pending} className={primary} onClick={() => start(async () => setError((await reviewProvider(userId, true, "")).error ?? null))}>Approve</button>
        <button type="button" disabled={pending} className={secondary} onClick={() => start(async () => setError((await reviewProvider(userId, false, reason)).error ?? null))}>Reject</button>
      </div>
      {error ? <p role="alert" className="text-sm font-medium">{error}</p> : null}
    </div>
  );
}
