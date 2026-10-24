import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createOffering } from "@/app/(app)/create/actions";
import { OfferingForm } from "@/components/app/offering-form";
import { PageTitle } from "@/components/app/states";
import { getMyProvider, getTopics } from "@/lib/provider-queries";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "New offering" };

export default async function NewOfferingPage() {
  const session = await requireSession();
  const provider = await getMyProvider(session.supabase, session.userId);
  if (!provider) redirect("/create/provider");
  const topics = await getTopics(session.supabase);
  return (
    <>
      <p className="mb-2">
        <Link href="/create" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Create</Link>
      </p>
      <PageTitle sub="Your first offering is free to list.">New offering</PageTitle>
      <OfferingForm action={createOffering} topics={topics} submitLabel="Publish offering" />
      {provider.status !== "approved" ? (
        <p className="mt-4 text-sm text-grey-600">It becomes visible to others once your provider profile is approved.</p>
      ) : null}
    </>
  );
}
