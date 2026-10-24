// Header pills showing which data sources are connected.
export type PillState = "on" | "off" | "warn";

interface Pill {
  label: string;
  state: PillState;
}

export function StatusPills({ pills }: { pills: Pill[] }) {
  return (
    <div className="pills">
      {pills.map((p) => (
        <span key={p.label} className={`pill ${p.state}`}>
          <span className="dot" />
          {p.label}
        </span>
      ))}
    </div>
  );
}
