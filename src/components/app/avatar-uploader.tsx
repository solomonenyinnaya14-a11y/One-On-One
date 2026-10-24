"use client";

import { useEffect, useState, useTransition } from "react";
import { removeAvatar, setAvatar } from "@/app/(app)/actions";
import { Avatar } from "@/components/ui/avatar";
import { resizeToJpeg } from "@/lib/image-resize";
import { createBrowserSupabase } from "@/lib/supabase/browser";

type Props = { userId: string; name: string; path: string | null };

export function AvatarUploader({ userId, name, path: initialPath }: Props) {
  const [path, setPath] = useState(initialPath);
  const [preview, setPreview] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [status, setStatus] = useState<{ error?: string; message?: string }>({});

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);

  function onPick(file: File | undefined, reset: () => void) {
    if (!file) return;
    if (file.type && !file.type.startsWith("image/")) {
      reset();
      return setStatus({ error: "Choose a photo (JPG, PNG, WebP or iPhone HEIC)." });
    }
    setStatus({});

    start(async () => {
      let blob: Blob;
      try {
        blob = await resizeToJpeg(file);
      } catch {
        reset();
        return setStatus({ error: "We couldn't read that photo. Try a JPG or PNG instead." });
      }
      const local = URL.createObjectURL(blob);
      setPreview(local); // the new picture shows immediately

      const supabase = createBrowserSupabase();
      if (!supabase) {
        setPreview(null);
        return setStatus({ error: "Uploads aren't available right now." });
      }
      const newPath = `${userId}/${crypto.randomUUID()}.jpg`;
      const { error } = await supabase.storage.from("avatars").upload(newPath, blob, {
        contentType: "image/jpeg",
        cacheControl: "31536000",
      });
      if (error) {
        setPreview(null);
        reset();
        return setStatus({ error: "The upload failed. Check your connection and try again." });
      }
      const result = await setAvatar(newPath);
      if (result.error) {
        setPreview(null);
        await supabase.storage.from("avatars").remove([newPath]);
        return setStatus(result);
      }
      const old = path;
      setPath(newPath);
      setStatus(result);
      if (old && old.startsWith(`${userId}/`)) void supabase.storage.from("avatars").remove([old]);
      reset();
    });
  }

  function onRemove() {
    start(async () => {
      const result = await removeAvatar();
      if (result.error) return setStatus(result);
      const old = path;
      setPath(null);
      setPreview(null);
      setStatus(result);
      const supabase = createBrowserSupabase();
      if (old && old.startsWith(`${userId}/`)) void supabase?.storage.from("avatars").remove([old]);
    });
  }

  const hasPhoto = Boolean(path || preview);
  return (
    <div className="flex items-center gap-5">
      <div className="relative">
        <Avatar name={name} path={path} previewUrl={preview} size="xl" />
        {pending ? (
          <span className="absolute inset-0 flex items-center justify-center rounded-full bg-white/70 text-xs font-semibold text-navy-900">
            Saving…
          </span>
        ) : null}
      </div>
      <div className="min-w-0 space-y-2">
        <input
          type="file"
          accept="image/*"
          className="sr-only"
          id="avatar-file"
          disabled={pending}
          onChange={(e) => {
            const input = e.currentTarget;
            onPick(input.files?.[0], () => { input.value = ""; });
          }}
        />
        <div className="flex flex-wrap items-center gap-3">
          <label
            htmlFor="avatar-file"
            className={`inline-flex min-h-11 cursor-pointer items-center rounded-full bg-navy-900 px-5 text-sm font-semibold text-white ${pending ? "pointer-events-none opacity-60" : ""}`}
          >
            {hasPhoto ? "Change photo" : "Add a photo"}
          </label>
          {hasPhoto ? (
            <button
              type="button"
              disabled={pending}
              onClick={onRemove}
              className="min-h-11 text-sm font-semibold text-grey-600 underline underline-offset-4 disabled:opacity-60"
            >
              Remove
            </button>
          ) : null}
        </div>
        <p role={status.error ? "alert" : "status"} className={`text-sm ${status.error ? "font-medium text-ink" : "text-grey-600"}`}>
          {status.error ?? status.message ?? "Choose any photo. We'll resize it for you."}
        </p>
      </div>
    </div>
  );
}
