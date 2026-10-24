"use client";

import { useState } from "react";
import { avatarUrl, initials } from "@/lib/avatar";

type AvatarProps = {
  name: string;
  path?: string | null;
  /** A local preview (blob: URL) shown instantly while/after uploading. */
  previewUrl?: string | null;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
};

const sizes = {
  xs: "h-7 w-7 text-[11px]",
  sm: "h-10 w-10 text-sm",
  md: "h-14 w-14 text-lg",
  lg: "h-24 w-24 text-3xl",
  xl: "h-32 w-32 text-4xl",
} as const;

/** Photo when there is one (and it loads); otherwise a soft initials badge. */
export function Avatar({ name, path, previewUrl, size = "md" }: AvatarProps) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const src = previewUrl ?? avatarUrl(path);
  const box = `${sizes[size]} shrink-0 rounded-full`;

  if (src && failedSrc !== src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt=""
        loading="lazy"
        decoding="async"
        onError={() => setFailedSrc(src)}
        className={`${box} bg-navy-50 object-cover ring-1 ring-black/5`}
      />
    );
  }
  return (
    <span
      aria-hidden="true"
      className={`${box} inline-flex items-center justify-center bg-gradient-to-br from-navy-100 to-navy-50 font-semibold text-navy-800 ring-1 ring-navy-900/10`}
    >
      {initials(name)}
    </span>
  );
}
