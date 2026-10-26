"use client";

import { useState } from "react";

type PasswordFieldProps = {
  name: string;
  label: string;
  autoComplete: "current-password" | "new-password";
  error?: string;
  hint?: string;
};

export function PasswordField({ name, label, autoComplete, error, hint }: PasswordFieldProps) {
  const [visible, setVisible] = useState(false);
  const id = `field-${name}`;
  const describedBy = [hint ? `${id}-hint` : null, error ? `${id}-error` : null]
    .filter(Boolean)
    .join(" ");

  return (
    <div>
      <label htmlFor={id} className="block text-sm font-semibold text-ink">{label}</label>
      <div className="relative mt-1.5">
        <input
          id={id}
          name={name}
          type={visible ? "text" : "password"}
          autoComplete={autoComplete}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy || undefined}
          className={`block min-h-12 w-full rounded-xl border-2 bg-paper py-3 pl-4 pr-20 text-base text-ink placeholder:text-grey-300 ${error ? "border-ink" : "border-grey-200"}`}
        />
        <button
          type="button"
          onClick={() => setVisible((value) => !value)}
          aria-controls={id}
          aria-pressed={visible}
          className="absolute inset-y-0 right-3 my-auto min-h-10 rounded-lg px-2 text-sm font-semibold text-navy-900 underline underline-offset-4"
        >
          {visible ? "Hide" : "See password"}
        </button>
      </div>
      {hint ? <p id={`${id}-hint`} className="mt-1.5 text-sm text-grey-600">{hint}</p> : null}
      {error ? <p id={`${id}-error`} role="alert" className="mt-1.5 text-sm font-medium text-ink">{error}</p> : null}
    </div>
  );
}
