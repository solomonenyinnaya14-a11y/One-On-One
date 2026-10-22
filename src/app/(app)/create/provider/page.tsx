import type { Metadata } from "next";
import Link from "next/link";
import { PageTitle } from "@/components/app/states";
import { ProviderForm } from "@/components/app/provider-form";
import { getMyProvider, getMyTopicIds, getTopics } from "@/lib/provider-queries";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Provider profile" };

export default async function ProviderProfilePage() {
  const session = await requireSession();
  const [provider, topics, selected] = await Promise.all([
    getMyProvider(session.supabase, session.userId),
    getTopics(session.supabase),
    getMyTopicIds(session.supabase, session.userId),
  ]);
  return (
    <>
      <p className="mb-2">
        <Link href="/create" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Create</Link>
      </p>
      <PageTitle sub={provider ? undefined : "Tell people who you are and how you can help."}>
        {provider ? "Provider profile" : "Become a provider"}
      </PageTitle>
      <ProviderForm provider={provider} topics={topics} selected={selected} />
      {!provider ? (
        <p className="mt-4 text-sm text-grey-600">Saving creates a draft. You submit it for review from the Create tab.</p>
      ) : null}
    </>
  );
}
