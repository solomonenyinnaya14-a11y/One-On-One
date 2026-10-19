export const siteConfig = {
  name: "One On One",
  headline: "One conversation can change your perspective.",
  description:
    "Find people worth talking to. Get advice, explore new perspectives, and learn from real experiences through one-on-one conversations.",
} as const;

export const routes = {
  home: "/",
  explore: "/explore",
  becomeProvider: "/become-a-provider",
} as const;

export const primaryNav = [
  { label: "How it works", href: "/#how-it-works" },
  { label: "For providers", href: "/#for-providers" },
] as const;

export const ctaLabels = {
  explore: "Explore People",
  becomeProvider: "Become a Provider",
} as const;
