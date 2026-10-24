import Link from "next/link";
import type { ComponentProps } from "react";

type Variant = "primary" | "secondary" | "inverse";
type Size = "md" | "sm";

const base =
  "inline-flex items-center justify-center rounded-full font-semibold transition-colors";

const variants: Record<Variant, string> = {
  primary: "bg-navy-900 text-white hover:bg-navy-800",
  secondary: "border-2 border-ink bg-paper text-ink hover:bg-grey-100",
  inverse: "bg-paper text-navy-900 hover:bg-navy-100",
};

const sizes: Record<Size, string> = {
  md: "min-h-12 px-7 text-base",
  sm: "min-h-10 px-4 text-sm",
};

type ButtonLinkProps = ComponentProps<typeof Link> & {
  variant?: Variant;
  size?: Size;
};

export function ButtonLink({
  variant = "primary",
  size = "md",
  className,
  ...props
}: ButtonLinkProps) {
  const classes = [base, variants[variant], sizes[size], className]
    .filter(Boolean)
    .join(" ");

  return <Link className={classes} {...props} />;
}
