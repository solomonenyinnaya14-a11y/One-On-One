"use client";
import { useState, useTransition } from "react";
import { startConversation } from "@/app/(app)/actions";
export function MessageButton({ targetId }: { targetId: string }) {
  const [pending, start] = useTransition(), [error, setError] = useState<string | null>(null);
  return <div><button type="button" disabled={pending} onClick={() => start(async () => { const result = await startConversation(targetId); setError(result?.error ?? null); })} className="inline-flex min-h-12 w-full items-center justify-center rounded-full bg-navy-900 px-8 font-semibold text-white transition-colors hover:bg-navy-800 disabled:opacity-60">{pending ? "Opening chat…" : "Send message request"}</button>{error ? <p role="alert" className="mt-2 text-sm font-medium text-red-700">{error}</p> : null}</div>;
}