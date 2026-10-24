// Quiet source indicators in the header: a small dot + name, green only when live.
export type PillState = "on" | "off" | "warn";

export function StatusPills({ pills }: { pills: { label: string; state: PillState }[] }) {
  return (
    <ul className="sources" aria-label="Connections">
      {pills.map((p) => (
        <li key={p.label} className={`source ${p.state}`}>
          <span className="source-dot" aria-hidden="true" />
          {p.label}
          <span className="sr-only">{p.state === "on" ? " connected" : p.state === "warn" ? " partly connected" : " not connected"}</span>
        </li>
      ))}
    </ul>
  );
}
