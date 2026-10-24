import { BrandMark } from "@/components/brand-mark";
import { ButtonLink } from "@/components/ui/button-link";
import { ctaLabels, routes, siteConfig } from "@/lib/site";
const steps=[
  {title:"Discover someone",body:"Search by username or browse people who are open to being found."},
  {title:"Send a request",body:"Say hello. Your first message arrives as a request, so the other person stays in control."},
  {title:"Start talking",body:"Once they accept, your private chat is open. Come back anytime to continue."},
] as const;
const principles=[
  {title:"You choose who can chat",body:"Message requests put the recipient in control of who can start a conversation."},
  {title:"Your chats stay private",body:"Conversations are for the people in them, not a public feed."},
  {title:"Pick up where you left off",body:"Your accepted conversations and message history stay in your inbox."},
] as const;
export default function Home(){
 return <>
  <section className="relative isolate overflow-hidden bg-navy-950 text-white">
   <div aria-hidden="true" className="absolute -right-24 -top-28 -z-10 h-96 w-96 rounded-full border border-white/10 sm:h-[34rem] sm:w-[34rem]"/>
   <div aria-hidden="true" className="absolute -right-8 top-10 -z-10 h-64 w-64 rounded-full border border-white/10 sm:h-96 sm:w-96"/>
   <div className="mx-auto grid max-w-6xl gap-12 px-5 py-16 sm:px-8 sm:py-24 lg:grid-cols-[1.1fr_0.9fr] lg:items-center lg:gap-20 lg:py-28">
    <div>
     <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1.5 text-sm text-navy-100"><BrandMark className="h-4 w-7"/><span>Real people. Private conversations.</span></div>
     <h1 className="max-w-3xl font-serif text-5xl font-medium leading-[1.02] tracking-tight sm:text-6xl lg:text-7xl">{siteConfig.headline}</h1>
     <p className="mt-6 max-w-xl text-lg leading-relaxed text-navy-100 sm:text-xl">{siteConfig.description}</p>
     <div className="mt-9 flex flex-col gap-3 sm:flex-row"><ButtonLink href={routes.getStarted}>{ctaLabels.explore}</ButtonLink><ButtonLink href={routes.signIn} variant="inverse">I already have an account</ButtonLink></div>
     <p className="mt-4 text-sm text-navy-100">Free to discover people and start a message request.</p>
    </div>
    <div className="mx-auto w-full max-w-md rounded-[2rem] border border-white/15 bg-white p-4 text-ink shadow-2xl shadow-black/20 sm:p-5">
     <div className="flex items-center gap-3 border-b border-grey-200 px-2 pb-4"><div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-navy-900 text-white"><BrandMark className="h-5 w-8"/></div><div><p className="font-semibold">Your conversations</p><p className="text-sm text-grey-600">A little closer, one chat at a time</p></div><span className="ml-auto h-2.5 w-2.5 rounded-full bg-emerald-500" aria-hidden="true"/></div>
     <div className="space-y-4 px-2 py-5">
      <div className="flex items-start gap-3"><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-navy-100 text-sm font-bold text-navy-900">A</div><div className="max-w-[85%] rounded-2xl rounded-tl-sm bg-grey-50 px-4 py-3"><p className="text-xs font-semibold text-grey-600">Alex · Message request</p><p className="mt-1 text-sm">Hey, I’d love to hear your perspective on this.</p></div></div>
      <div className="ml-8 rounded-2xl border border-navy-100 bg-navy-50 px-4 py-3"><p className="text-xs font-semibold text-navy-900">You’re in control</p><p className="mt-1 text-sm text-grey-600">Accept a request to open the private chat.</p></div>
      <div className="flex items-start justify-end gap-3"><div className="max-w-[85%] rounded-2xl rounded-tr-sm bg-navy-900 px-4 py-3 text-white"><p className="text-xs font-semibold text-white/70">You</p><p className="mt-1 text-sm">Accepted. Let’s talk.</p></div><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-grey-100 text-sm font-bold">Y</div></div>
     </div>
     <div className="flex items-center gap-2 border-t border-grey-200 px-2 pt-4"><div className="h-11 flex-1 rounded-full border border-grey-200 bg-grey-50 px-4 text-sm leading-[2.7rem] text-grey-600">Write a message…</div><div className="flex h-11 w-11 items-center justify-center rounded-full bg-navy-900 text-white" aria-hidden="true">↑</div></div>
     <p className="mt-3 text-center text-[11px] text-grey-600">Illustration · not a real conversation</p>
    </div>
   </div>
  </section>
  <section id="how-it-works" className="border-b border-grey-200"><div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 lg:py-24">
   <p className="text-xs font-bold uppercase tracking-[0.18em] text-navy-900">Simple by design</p><h2 className="mt-3 max-w-xl font-serif text-3xl font-medium tracking-tight sm:text-4xl">A better way to start a conversation.</h2>
   <ol className="mt-10 grid gap-5 md:grid-cols-3">{steps.map((step,index)=><li key={step.title} className="card p-6 sm:p-7"><span aria-hidden="true" className="flex h-10 w-10 items-center justify-center rounded-2xl bg-navy-50 font-serif text-xl font-semibold text-navy-900">{index+1}</span><h3 className="mt-5 text-xl font-semibold">{step.title}</h3><p className="mt-2 leading-relaxed text-grey-600">{step.body}</p></li>)}</ol>
  </div></section>
  <section id="privacy" className="bg-grey-50"><div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 lg:py-24"><h2 className="max-w-xl font-serif text-3xl font-medium tracking-tight sm:text-4xl">Connection, with your choice at the center.</h2>
   <dl className="mt-10 grid gap-8 md:grid-cols-3 md:gap-12">{principles.map((item)=><div key={item.title} className="border-t-2 border-navy-900 pt-5"><dt className="text-xl font-semibold">{item.title}</dt><dd className="mt-2 leading-relaxed text-grey-600">{item.body}</dd></div>)}</dl>
  </div></section>
  <section className="mx-auto max-w-6xl px-5 py-16 sm:px-8 lg:py-24"><div className="rounded-3xl bg-navy-950 px-6 py-10 text-white sm:px-10 sm:py-14"><h2 className="max-w-2xl font-serif text-3xl font-medium tracking-tight sm:text-4xl">Someone you haven’t met yet could change your day.</h2><p className="mt-4 max-w-xl text-navy-100">Find them, send a request, and see where the conversation goes.</p><div className="mt-7"><ButtonLink href={routes.getStarted}>{ctaLabels.explore}</ButtonLink></div></div></section>
 </>;
}