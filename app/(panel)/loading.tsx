// Sayfa geçişinde veri gelene kadar görünen iskelet. Next.js bunu kendiliğinden kullanır:
// kenar çubuğu ve üst bar yerinde kalır, yalnızca içerik alanı soluk kutularla dolar.
function Kutu({ className }: { className: string }) {
  return <div className={`animate-pulse rounded-lg bg-muted ${className}`} />;
}

export default function Yukleniyor() {
  return (
    <div className="flex flex-col gap-6" role="status" aria-live="polite">
      <span className="sr-only">Sayfa yükleniyor…</span>
      <div className="flex flex-col gap-2">
        <Kutu className="h-8 w-64" />
        <Kutu className="h-4 w-96 max-w-full" />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="flex flex-col gap-2 rounded-xl border bg-card p-4">
            <Kutu className="h-4 w-28" />
            <Kutu className="h-8 w-16" />
            <Kutu className="h-3 w-36" />
          </div>
        ))}
      </div>
      <div className="flex flex-col overflow-hidden rounded-lg border bg-card">
        <Kutu className="h-10 rounded-none" />
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="flex items-center gap-4 border-t px-3 py-3">
            <Kutu className="h-4 w-24" />
            <Kutu className="h-4 w-40" />
            <Kutu className="h-4 flex-1" />
            <Kutu className="h-6 w-20 rounded-full" />
          </div>
        ))}
      </div>
    </div>
  );
}
