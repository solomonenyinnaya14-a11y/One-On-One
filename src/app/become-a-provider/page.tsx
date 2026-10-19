import type { Metadata } from "next";
import { ComingSoon } from "@/components/coming-soon";

export const metadata: Metadata = {
  title: "Become a Provider",
};

export default function BecomeProviderPage() {
  return (
    <ComingSoon
      title="Provider sign-up isn't open yet."
      body="We're building accounts and provider profiles first. When sign-up opens, you'll be able to set your topics, your price and the times you're available."
    />
  );
}
