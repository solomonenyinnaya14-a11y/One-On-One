import { ConversationVisual } from "@/components/conversation-visual";
import { ButtonLink } from "@/components/ui/button-link";
import { ctaLabels, routes, siteConfig } from "@/lib/site";

const steps = [
  {
    title: "Find someone",
    body: "Browse people by what they know and what you want to talk about. Compare prices and availability before you decide.",
  },
  {
    title: "Book a time",
    body: "Choose a text or voice conversation, see the price up front, and pick a time that works for both of you.",
  },
  {
    title: "Have the conversation",
    body: "Talk one on one. When it's done, you can review the person you spoke with.",
  },
] as const;

const principles = [
  {
    title: "Private by design",
    body: "Only you and the person you're talking to can see a conversation.",
  },
  {
    title: "Prices you can see first",
    body: "Every provider sets their own price. You see it before you book.",
  },
  {
    title: "Reviews from real conversations",
    body: "Only people who have finished a conversation can review it.",
  },
] as const;

export default function Home() {
  return (
    <>
      <section className="mx-auto grid max-w-6xl gap-12 px-5 pb-16 pt-12 sm:px-8 sm:pt-16 lg:grid-cols-[1.15fr_0.85fr] lg:items-center lg:gap-16 lg:pb-24 lg:pt-24">
        <div>
          <h1 className="max-w-3xl font-serif text-[2.75rem] font-medium leading-[1.04] tracking-tight sm:text-6xl lg:text-7xl">
            {siteConfig.headline}
          </h1>
          <p className="mt-6 max-w-xl text-lg text-grey-600 sm:text-xl sm:leading-relaxed">
            {siteConfig.description}
          </p>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <ButtonLink href={routes.explore}>{ctaLabels.explore}</ButtonLink>
            <ButtonLink href={routes.becomeProvider} variant="secondary">
              {ctaLabels.becomeProvider}
            </ButtonLink>
          </div>
        </div>
        <div className="lg:justify-self-end">
          <ConversationVisual />
        </div>
      </section>

      <section id="how-it-works" className="border-t border-grey-200">
        <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 lg:grid lg:grid-cols-[0.8fr_1.2fr] lg:gap-16 lg:py-24">
          <h2 className="font-serif text-3xl font-medium tracking-tight sm:text-4xl">
            How it works
          </h2>
          <ol className="mt-10 divide-y divide-grey-200 border-y border-grey-200 lg:mt-0">
            {steps.map((step, index) => (
              <li key={step.title} className="flex gap-6 py-7">
                <span
                  aria-hidden="true"
                  className="w-8 shrink-0 font-serif text-4xl font-medium leading-none text-navy-900"
                >
                  {index + 1}
                </span>
                <div>
                  <h3 className="text-xl font-semibold">{step.title}</h3>
                  <p className="mt-2 max-w-prose text-grey-600">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="bg-grey-50">
        <div className="mx-auto grid max-w-6xl gap-px px-5 py-16 sm:px-8 md:grid-cols-2 lg:py-24">
          <div className="md:pr-12">
            <h2 className="font-serif text-3xl font-medium tracking-tight sm:text-4xl">
              Write it out
            </h2>
            <p className="mt-4 max-w-md text-grey-600">
              Text conversations let you take your time. Think, write back, and
              keep going at your own pace.
            </p>
          </div>
          <div className="mt-10 border-t border-grey-300 pt-10 md:mt-0 md:border-l md:border-t-0 md:pl-12 md:pt-0">
            <h2 className="font-serif text-3xl font-medium tracking-tight sm:text-4xl">
              Talk it through
            </h2>
            <p className="mt-4 max-w-md text-grey-600">
              Voice conversations happen live, right in your browser, with
              nothing to install.
            </p>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-5 py-16 sm:px-8 lg:py-24">
        <h2 className="max-w-xl font-serif text-3xl font-medium tracking-tight sm:text-4xl">
          Built for honest conversations
        </h2>
        <dl className="mt-10 grid gap-8 md:grid-cols-3 md:gap-12">
          {principles.map((item) => (
            <div key={item.title} className="border-t-2 border-ink pt-5">
              <dt className="text-xl font-semibold">{item.title}</dt>
              <dd className="mt-2 text-grey-600">{item.body}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section id="for-providers" className="on-navy bg-navy-950 text-white">
        <div className="mx-auto flex max-w-6xl flex-col gap-8 px-5 py-16 sm:px-8 md:flex-row md:items-center md:justify-between lg:py-20">
          <div className="max-w-xl">
            <h2 className="font-serif text-3xl font-medium tracking-tight sm:text-4xl">
              Have experience worth sharing?
            </h2>
            <p className="mt-4 text-lg text-navy-100">
              Set your topics, your price and the times you&apos;re available.
              Then talk with people who want to learn from you.
            </p>
          </div>
          <ButtonLink href={routes.becomeProvider} variant="inverse" className="shrink-0">
            {ctaLabels.becomeProvider}
          </ButtonLink>
        </div>
      </section>
    </>
  );
}
