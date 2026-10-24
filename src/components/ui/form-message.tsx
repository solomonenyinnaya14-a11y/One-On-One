type FormMessageProps = { error?: string; message?: string };

/** Announces the result of a form: failures as alerts, successes as status. */
export function FormMessage({ error, message }: FormMessageProps) {
  if (error) {
    return (
      <p role="alert" className="rounded-xl border-2 border-ink bg-grey-50 px-4 py-3 text-sm font-medium text-ink">
        {error}
      </p>
    );
  }
  if (message) {
    return (
      <p role="status" className="rounded-xl bg-navy-50 px-4 py-3 text-sm font-medium text-navy-900">
        {message}
      </p>
    );
  }
  return null;
}
