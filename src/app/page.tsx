export default function Home() {
  return (
    <main
      style={{
        minHeight: "100dvh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "1rem",
        fontFamily: "system-ui, -apple-system, sans-serif",
        textAlign: "center",
      }}
    >
      <h1 style={{ fontSize: "clamp(1.75rem, 4vw, 2.5rem)", margin: 0 }}>
        Luxe CRM
      </h1>
      <p style={{ color: "#555", marginTop: "0.5rem" }}>
        Multi-brand, multi-store CRM. Sign-in and contacts coming soon.
      </p>
    </main>
  );
}
