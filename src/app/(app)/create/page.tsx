import type { Metadata } from "next";
import { PageTitle } from "@/components/app/states";

export const metadata: Metadata = { title: "Create" };

export default function CreatePage() {
  return (
    <>
      <PageTitle sub="Offer your time and experience.">Create</PageTitle>
      <section className="rounded-2xl border border-grey-200 p-6">
        <h2 className="font-serif text-xl font-medium">Paid conversations</h2>
        <p className="mt-2 text-grey-600">
          Provider applications and offering management are the next thing being built. Nothing
          here is switched on yet, so there is nothing to set up today.
        </p>
      </section>
    </>
  );
}
