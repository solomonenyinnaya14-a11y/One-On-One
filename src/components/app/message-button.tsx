"use client";

import { useState, useTransition } from "react";
import { startConversation } from "@/app/(app)/actions";

export function MessageButton({ targetId }: { targetId: string }) {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <div>
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          start(async () => {
            const result = await startConversation(targetId);
            // On success the action redirects; we only get here with an error.
            setError(result?.error ?? null);
          })
        }
        className="min-h-12 rounded-full bg-navy-900 px-8 font-semibold text-white hover:bg-navy-800 disabled:opacity-60"
      >
        {pending ? "Opening…" : "Message"}
      </button>
      {error ? (
        <p role="alert" className="mt-2 text-sm font-medium">
          {error}
        </p>
      ) : null}
    </div>
  );
}
