import Link from "next/link";

export function EmptyState({
  title,
  body,
  action,
}: {
  title: string;
  body: string;
  action?: { href: string; label: string };
}) {
  return (
    <div className="rounded-2xl border border-dashed border-grey-300 px-6 py-10 text-center">
      <p className="font-serif text-xl font-medium">{title}</p>
      <p className="mx-auto mt-2 max-w-sm text-sm text-grey-600">{body}</p>
      {action ? (
        <Link
          href={action.href}
          className="mt-5 inline-flex min-h-11 items-center rounded-full bg-navy-900 px-6 text-sm font-semibold text-white"
        >
          {action.label}
        </Link>
      ) : null}
    </div>
  );
}

export function ErrorState({ what }: { what: string }) {
  return (
    <div role="alert" className="rounded-2xl border-2 border-ink bg-grey-50 px-6 py-6">
      <p className="font-semibold">We couldn&apos;t load {what}.</p>
      <p className="mt-1 text-sm text-grey-600">Check your connection and refresh the page.</p>
    </div>
  );
}

export function PageTitle({ children, sub }: { children: React.ReactNode; sub?: string }) {
  return (
    <header className="mb-6">
      <h1 className="font-serif text-3xl font-medium tracking-tight">{children}</h1>
      {sub ? <p className="mt-1 text-grey-600">{sub}</p> : null}
    </header>
  );
}
