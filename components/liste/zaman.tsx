import { tarihSaat } from "@/lib/bicim";

// Tarih-saat her listede aynı biçimde yazılır: gg.aa.yyyy ss:dd (Türkiye saati).
// "etiket" zamanın neyi anlattığını söyler: "Kayıt" (sistemin yazdığı an) ile olayın anı karışmasın.
export function Zaman({ deger, etiket, className }: { deger: string | null | undefined; etiket?: string; className?: string }) {
  if (!deger) return <span className={className}>—</span>;
  return (
    <time dateTime={deger} className={className}>
      {etiket ? `${etiket}: ` : ""}
      <span className="tabular-nums">{tarihSaat(deger)}</span>
    </time>
  );
}
