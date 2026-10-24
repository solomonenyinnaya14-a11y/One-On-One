"use client";

import { useFormStatus } from "react-dom";

type SubmitButtonProps = {
  children: React.ReactNode;
  pendingLabel?: string;
  variant?: "primary" | "secondary";
  className?: string;
};

export function SubmitButton({
  children,
  pendingLabel = "Please wait…",
  variant = "primary",
  className,
}: SubmitButtonProps) {
  const { pending } = useFormStatus();
  const look =
    variant === "primary"
      ? "bg-navy-900 text-white hover:bg-navy-800"
      : "border-2 border-ink bg-paper text-ink hover:bg-grey-100";
  return (
    <button
      type="submit"
      disabled={pending}
      aria-disabled={pending}
      className={`inline-flex min-h-12 w-full items-center justify-center rounded-full px-7 text-base font-semibold transition-colors disabled:opacity-60 ${look} ${className ?? ""}`}
    >
      {pending ? pendingLabel : children}
    </button>
  );
}
