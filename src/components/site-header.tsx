import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { ButtonLink } from "@/components/ui/button-link";
import { ctaLabels, primaryNav, routes, siteConfig } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-grey-200 bg-paper/95 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-5 sm:px-8">
        <Link
          href={routes.home}
          className="flex items-center gap-2.5 text-navy-900"
          aria-label={`${siteConfig.name} home`}
        >
          <BrandMark className="h-6 w-10" />
          <span className="font-serif text-xl font-semibold tracking-tight text-ink">
            {siteConfig.name}
          </span>
        </Link>

        <nav aria-label="Main" className="hidden items-center gap-8 md:flex">
          {primaryNav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="text-base font-medium text-grey-600 transition-colors hover:text-ink"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <ButtonLink href={routes.explore} size="sm">
          {ctaLabels.explore}
        </ButtonLink>
      </div>
    </header>
  );
}
