import { redirect } from "next/navigation";
/** Marketplace creation tools are intentionally out of the messaging-first MVP. */
export default function DeferredMarketplaceLayout({ children }: { children: React.ReactNode }) { void children; redirect("/discover"); }