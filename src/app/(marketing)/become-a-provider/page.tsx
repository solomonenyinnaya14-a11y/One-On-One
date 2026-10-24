import { redirect } from "next/navigation";
/** Provider and paid marketplace features are intentionally deferred from the MVP. */
export default function BecomeProviderPage() { redirect("/register"); }