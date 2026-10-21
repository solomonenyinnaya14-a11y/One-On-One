"use client";

import { useRef, useState, useTransition } from "react";
import { removeAvatar, setAvatar } from "@/app/(app)/actions";
import { Avatar } from "@/components/ui/avatar";
import { AVATAR_MAX_BYTES, AVATAR_TYPES } from "@/lib/avatar";
import { createBrowserSupabase } from "@/lib/supabase/browser";

type Props = { userId: string; name: string; path: string | null };

export function AvatarUploader({ userId, name, path }: Props) {
  const input = useRef<HTMLInputElement>(null);
  const [pending, start] = useTransition();
  const [status, setStatus] = useState<{ error?: string; message?: string }>({});

  function onPick(file: File | undefined) {
    if (!file) return;
    const ext = AVATAR_TYPES[file.type];
    if (!ext) return setStatus({ error: "Use a JPG, PNG or WebP image." });
    if (file.size > AVATAR_MAX_BYTES) return setStatus({ error: "Photos can be at most 2 MB." });

    start(async () => {
      const supabase = createBrowserSupabase();
      if (!supabase) return setStatus({ error: "Uploads aren't available right now." });
      const newPath = `${userId}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabase.storage.from("avatars").upload(newPath, file, {
        contentType: file.type,
        cacheControl: "31536000",
      });
      if (error) return setStatus({ error: "The upload failed. Please try again." });
      setStatus(await setAvatar(newPath));
    });
  }

  return (
    <div className="flex items-center gap-4">
      <Avatar name={name} path={path} size="lg" />
      <div className="space-y-2">
        <input
          ref={input}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="sr-only"
          id="avatar-file"
          onChange={(e) => onPick(e.target.files?.[0])}
        />
        <label
          htmlFor="avatar-file"
          className={`inline-flex min-h-11 cursor-pointer items-center rounded-full border-2 border-ink px-5 text-sm font-semibold ${pending ? "opacity-60" : ""}`}
        >
          {pending ? "Uploading…" : path ? "Change photo" : "Add a photo"}
        </label>
        {path ? (
          <button
            type="button"
            disabled={pending}
            onClick={() => start(async () => setStatus(await removeAvatar()))}
            className="ml-3 text-sm font-semibold text-grey-600 underline underline-offset-4"
          >
            Remove
          </button>
        ) : null}
        <p role={status.error ? "alert" : "status"} className="text-sm text-grey-600">
          {status.error ?? status.message ?? "JPG, PNG or WebP, up to 2 MB."}
        </p>
      </div>
    </div>
  );
}
