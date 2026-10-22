import type { Metadata } from "next";
import Link from "next/link";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { PauseResumeButton, SubmitApplicationButton, WithdrawApplicationButton } from "@/components/app/provider-buttons";
import { formatNaira } from "@/lib/format";
import { getMyOfferings, getMyProvider, getTopics } from "@/lib/provider-queries";
import { offeringStatus } from "@/lib/provider-validation";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Create" };

const primaryLink = "inline-flex min-h-12 w-full items-center justify-center rounded-full bg-navy-900 px-7 font-semibold text-white hover:bg-navy-800";
const secondaryLink = "inline-flex min-h-12 w-full items-center justify-center rounded-full border-2 border-ink bg-white px-7 font-semibold";

export default async function CreatePage() {
  const session = await requireSession();
  const provider = await getMyProvider(session.supabase, session.userId);

  if (!provider) {
    return (
      <>
        <PageTitle sub="Offer your time and experience.">Create</PageTitle>
        <section className="card p-6">
          <h2 className="font-serif text-2xl font-medium">Become a provider</h2>
          <p className="mt-2 text-grey-600">
            Providers hold paid one-to-one conversations, by text or voice, with people who want
            their advice. You set the topic, length and price.
          </p>
          <ul className="mt-4 space-y-2 text-sm">
            <li>• Your first paid conversation offering is free to list.</li>
            <li>• We review every application before you appear publicly.</li>
            <li>• You choose what you offer and can pause it any time.</li>
          </ul>
          <Link href="/create/provider" className={`${primaryLink} mt-6`}>Start your application</Link>
        </section>
      </>
    );
  }

  const statusBox = (
    <>
      {provider.status === "draft" ? (
        <section className="card mb-6 p-5">
          <p className="font-semibold">Your application is a draft</p>
          <p className="mt-1 text-sm text-grey-600">
            Finish your profile, then submit it for review. You can set up your first offering while you wait.
          </p>
          <div className="mt-4 space-y-3">
            <Link href="/create/provider" className={secondaryLink}>Edit provider profile</Link>
            <SubmitApplicationButton />
          </div>
        </section>
      ) : null}
      {provider.status === "pending_review" ? (
        <section className="card mb-6 p-5">
          <p className="font-semibold">Under review</p>
          <p className="mt-1 text-sm text-grey-600">
            We&apos;re reviewing your application. You&apos;ll appear in Discover once it&apos;s approved. You can still prepare your offering.
          </p>
          <div className="mt-4"><WithdrawApplicationButton /></div>
        </section>
      ) : null}
      {provider.status === "rejected" ? (
        <section role="alert" className="mb-6 rounded-2xl border-2 border-ink bg-white p-5">
          <p className="font-semibold">Your application needs changes</p>
          {provider.rejection_reason ? <p className="mt-1 text-sm">{provider.rejection_reason}</p> : null}
          <div className="mt-4 space-y-3">
            <Link href="/create/provider" className={secondaryLink}>Update profile</Link>
            <SubmitApplicationButton />
          </div>
        </section>
      ) : null}
      {provider.status === "suspended" ? (
        <section role="alert" className="mb-6 rounded-2xl border-2 border-ink bg-white p-5">
          <p className="font-semibold">Your provider profile is suspended</p>
          <p className="mt-1 text-sm text-grey-600">Existing bookings, messages and earnings are kept. Contact support if you think this is a mistake.</p>
        </section>
      ) : null}
    </>
  );

  const { offerings, error } = await getMyOfferings(session.supabase, session.userId);
  const topics = await getTopics(session.supabase);
  const topicName = (id: string | null) => topics.find((t) => t.id === id)?.name;
  const approved = provider.status === "approved";
  const canAdd = provider.status !== "suspended";

  return (
    <>
      <PageTitle sub={approved ? "You're an approved provider." : "Set up your paid conversations."}>Create</PageTitle>
      {statusBox}

      <section aria-labelledby="offerings-h">
        <div className="mb-3 flex items-baseline justify-between">
          <h2 id="offerings-h" className="text-lg font-semibold">Your offerings</h2>
          {approved ? (
            <Link href="/create/bookings" className="text-sm font-semibold text-navy-900 underline underline-offset-4">Bookings</Link>
          ) : null}
        </div>
        {error ? (
          <ErrorState what="your offerings" />
        ) : offerings.length === 0 ? (
          <EmptyState title="No offerings yet" body="Create your first paid conversation. It's free to list." action={canAdd ? { href: "/create/offerings/new", label: "Create an offering" } : undefined} />
        ) : (
          <ul className="space-y-3">
            {offerings.map((o) => {
              const st = offeringStatus(o, approved);
              return (
                <li key={o.id} className="card p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-semibold">{o.title}</p>
                      <p className="text-sm text-grey-600">
                        {o.kind === "voice" ? "Voice" : "Text"} · {o.duration_minutes} min · {formatNaira(o.price_minor)}
                        {topicName(o.topic_id) ? ` · ${topicName(o.topic_id)}` : ""}
                      </p>
                    </div>
                    <span className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold ${st.label === "Live" ? "bg-navy-900 text-white" : "bg-grey-100 text-ink"}`}>{st.label}</span>
                  </div>
                  <p className="mt-2 text-sm text-grey-600">{st.hint}</p>
                  <div className="mt-3 flex items-center gap-3">
                    <Link href={`/create/offerings/${o.id}`} className="inline-flex min-h-11 items-center rounded-full bg-navy-900 px-5 text-sm font-semibold text-white">Edit</Link>
                    <PauseResumeButton id={o.id} active={o.is_active} />
                  </div>
                </li>
              );
            })}
          </ul>
        )}
        {offerings.length > 0 && canAdd ? (
          <p className="mt-4"><Link href="/create/offerings/new" className={secondaryLink}>Add another offering</Link></p>
        ) : null}
        {offerings.length > 0 ? (
          <p className="mt-4 text-sm text-grey-600">
            Offerings can be paused but not deleted, so past bookings and earnings always keep their history. Your first offering is free; extra ones need an active provider subscription.
          </p>
        ) : null}
      </section>
    </>
  );
}
