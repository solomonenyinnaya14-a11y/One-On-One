import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { ctaLabels, routes, siteConfig } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="border-t border-grey-200 bg-grey-50">
      <div className="mx-auto flex max-w-6xl flex-col gap-8 px-5 py-10 sm:px-8 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-2.5 text-navy-900">
          <BrandMark className="h-5 w-8" />
          <span className="font-serif text-lg font-semibold text-ink">
            {siteConfig.name}
          </span>
        </div>

        <nav aria-label="Footer" className="flex flex-col gap-3 sm:flex-row sm:gap-8">
          <Link href={routes.explore} className="font-medium text-ink hover:underline">
            {ctaLabels.explore}
          </Link>
          <Link
            href={routes.becomeProvider}
            className="font-medium text-ink hover:underline"
          >
            {ctaLabels.becomeProvider}
          </Link>
        </nav>

        <div className="text-sm text-grey-600 md:text-right">
          <p>&copy; {new Date().getFullYear()} {siteConfig.name}</p>
          <p className="mt-1 text-xs">By Black Core Tech</p>
        </div>
      </div>
    </footer>
  );
}
