import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { siteConfig } from "@/lib/site";

// Everything here depends on who is signed in, so it is never prerendered.
export const dynamic = "force-dynamic";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <main id="main" className="mx-auto flex min-h-dvh max-w-md flex-col px-5 py-8">
      <Link href="/" className="flex items-center gap-2.5 text-navy-900" aria-label={`${siteConfig.name} home`}>
        <BrandMark className="h-6 w-10" />
        <span className="font-serif text-xl font-semibold tracking-tight text-ink">{siteConfig.name}</span>
      </Link>
      <div className="flex flex-1 flex-col justify-center py-10">{children}</div>
    </main>
  );
}
