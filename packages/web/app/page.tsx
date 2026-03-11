import Link from "next/link";

export default function HomePage() {
  return (
    <main className="space-y-8">
      <section className="rounded-2xl border border-white/40 bg-hero-glow bg-slate-950/90 p-10 text-slate-50 shadow-glass">
        <p className="mb-3 text-sm uppercase tracking-[0.22em] text-slate-300">Governance + Markets</p>
        <h2 className="max-w-3xl text-4xl font-semibold leading-tight">
          Launch timestamp-based DAO governance and token bonding curves in one transaction.
        </h2>
        <p className="mt-4 max-w-2xl text-slate-300">
          This monorepo includes on-chain factory deployment and an app router frontend with live reads,
          writes, and proposal workflows.
        </p>
        <div className="mt-6 flex gap-3">
          <Link className="rounded-md bg-white px-4 py-2 text-sm font-medium text-slate-900" href="/tokens">
            Explore markets
          </Link>
          <Link
            className="rounded-md border border-white/40 px-4 py-2 text-sm font-medium text-white"
            href="/my-daos"
          >
            Open my dashboard
          </Link>
        </div>
      </section>
    </main>
  );
}
