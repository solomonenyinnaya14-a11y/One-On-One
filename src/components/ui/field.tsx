import type { ComponentProps } from "react";

type FieldProps = Omit<ComponentProps<"input">, "id"> & {
  name: string;
  label: string;
  error?: string;
  hint?: string;
};

export function Field({ name, label, error, hint, className, ...props }: FieldProps) {
  const id = `field-${name}`;
  const describedBy = [hint ? `${id}-hint` : null, error ? `${id}-error` : null]
    .filter(Boolean)
    .join(" ");
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-semibold text-ink">
        {label}
      </label>
      <input
        id={id}
        name={name}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy || undefined}
        className={`mt-1.5 block min-h-12 w-full rounded-xl border-2 bg-paper px-4 text-base text-ink placeholder:text-grey-300 ${
          error ? "border-ink" : "border-grey-200"
        } ${className ?? ""}`}
        {...props}
      />
      {hint ? (
        <p id={`${id}-hint`} className="mt-1.5 text-sm text-grey-600">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={`${id}-error`} role="alert" className="mt-1.5 text-sm font-medium text-ink">
          {error}
        </p>
      ) : null}
    </div>
  );
}

type TextAreaProps = Omit<ComponentProps<"textarea">, "id"> & {
  name: string;
  label: string;
  error?: string;
  hint?: string;
};

export function TextArea({ name, label, error, hint, className, ...props }: TextAreaProps) {
  const id = `field-${name}`;
  const describedBy = [hint ? `${id}-hint` : null, error ? `${id}-error` : null]
    .filter(Boolean)
    .join(" ");
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-semibold text-ink">
        {label}
      </label>
      <textarea
        id={id}
        name={name}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy || undefined}
        className={`mt-1.5 block w-full rounded-xl border-2 bg-paper px-4 py-3 text-base text-ink placeholder:text-grey-300 ${
          error ? "border-ink" : "border-grey-200"
        } ${className ?? ""}`}
        {...props}
      />
      {hint ? (
        <p id={`${id}-hint`} className="mt-1.5 text-sm text-grey-600">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={`${id}-error`} role="alert" className="mt-1.5 text-sm font-medium text-ink">
          {error}
        </p>
      ) : null}
    </div>
  );
}
