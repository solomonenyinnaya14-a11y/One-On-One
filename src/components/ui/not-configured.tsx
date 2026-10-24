/** Shown instead of crashing when the backend connection is not set up. */
export function NotConfigured() {
  return (
    <section className="mx-auto max-w-md px-5 py-20">
      <h1 className="font-serif text-3xl font-medium">This preview isn&apos;t connected yet.</h1>
      <p className="mt-4 text-grey-600">
        The app is built, but the database connection hasn&apos;t been set up for this
        environment, so sign-in is switched off rather than pretending to work.
      </p>
    </section>
  );
}
