"use client";

import { useState, useTransition } from "react";
import { setFollow } from "@/app/(app)/actions";

type Props = { targetId: string; username: string; following: boolean };

export function FollowButton({ targetId, username, following }: Props) {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <div>
      <button
        type="button"
        disabled={pending}
        aria-pressed={following}
        onClick={() =>
          start(async () => {
            const result = await setFollow(targetId, username, !following);
            setError(result.error ?? null);
          })
        }
        className={`min-h-11 rounded-full px-6 text-sm font-semibold transition-colors disabled:opacity-60 ${
          following ? "border-2 border-ink bg-paper text-ink" : "bg-navy-900 text-white hover:bg-navy-800"
        }`}
      >
        {pending ? "…" : following ? "Following" : "Follow"}
      </button>
      {error ? (
        <p role="alert" className="mt-2 text-sm font-medium">
          {error}
        </p>
      ) : null}
    </div>
  );
}
