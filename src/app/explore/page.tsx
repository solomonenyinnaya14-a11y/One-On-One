import type { Metadata } from "next";
import { ComingSoon } from "@/components/coming-soon";

export const metadata: Metadata = {
  title: "Explore People",
};

export default function ExplorePage() {
  return (
    <ComingSoon
      title="People to talk to are on the way."
      body="Browsing isn't open yet. When it is, you'll be able to search by topic, compare prices and see when each person is available."
    />
  );
}
