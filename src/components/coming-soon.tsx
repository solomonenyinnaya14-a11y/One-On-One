import { ButtonLink } from "@/components/ui/button-link";
import { routes } from "@/lib/site";

type ComingSoonProps = {
  title: string;
  body: string;
};

/** An honest placeholder for a feature that is being built and not open yet. */
export function ComingSoon({ title, body }: ComingSoonProps) {
  return (
    <section className="mx-auto max-w-3xl px-5 py-20 sm:px-8 sm:py-28">
      <h1 className="font-serif text-4xl font-medium leading-tight tracking-tight sm:text-5xl">
        {title}
      </h1>
      <p className="mt-6 max-w-prose text-lg text-grey-600">{body}</p>
      <ButtonLink href={routes.home} variant="secondary" className="mt-10">
        Back to home
      </ButtonLink>
    </section>
  );
}
