import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { updateOffering } from "@/app/(app)/create/actions";
import { OfferingForm } from "@/components/app/offering-form";
import { PageTitle } from "@/components/app/states";
import { getMyOffering, getTopics } from "@/lib/provider-queries";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Edit offering" };

export default async function EditOfferingPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const session = await requireSession();
  const offering = await getMyOffering(session.supabase, session.userId, id);
  if (!offering) notFound();
  const topics = await getTopics(session.supabase);
  return (
    <>
      <p className="mb-2">
        <Link href="/create" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Create</Link>
      </p>
      <PageTitle>Edit offering</PageTitle>
      <OfferingForm action={updateOffering.bind(null, id)} topics={topics} offering={offering} submitLabel="Save changes" lockKind />
    </>
  );
}
