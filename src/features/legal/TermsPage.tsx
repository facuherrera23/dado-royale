import { Link } from 'react-router-dom';

/**
 * Términos y avisos de juego responsable. Ruta pública: se enlaza desde
 * el registro (aceptación obligatoria) y desde el pie de página.
 */
export function TermsPage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-10">
      <h1 className="text-3xl font-bold text-casino-gold">Términos y juego responsable</h1>

      <section className="flex flex-col gap-4 rounded-xl border border-casino-border bg-casino-surface p-6 text-sm leading-relaxed text-casino-muted">
        <h2 className="text-lg font-semibold text-casino-text">1. Fichas virtuales</h2>
        <p>
          Todas las fichas de Dado Royale son{' '}
          <strong>virtuales y no tienen ningún valor monetario</strong>. No pueden comprarse,
          venderse, canjearse ni convertirse en dinero real ni en bienes de ningún tipo. No existen
          pasarelas de pago.
        </p>

        <h2 className="text-lg font-semibold text-casino-text">2. Edad mínima</h2>
        <p>La aplicación está destinada exclusivamente a mayores de 18 años.</p>

        <h2 className="text-lg font-semibold text-casino-text">3. Reglas del juego</h2>
        <ul className="list-inside list-disc space-y-1">
          <li>
            Cada jugador lanza 2 dados de 6 caras; generados en el servidor con aleatoriedad
            criptográfica.
          </li>
          <li>Gana el total más alto. El pozo es apuesta fija × jugadores.</li>
          <li>La casa se queda con el 4% del pozo como comisión (redondeo a favor del jugador).</li>
          <li>
            Empate: se desempata entre los empatados (máx. 3). Si persiste, se devuelven las
            apuestas íntegras.
          </li>
          <li>Si una ronda queda atascada, las apuestas se reembolsan sin comisión.</li>
        </ul>

        <h2 className="text-lg font-semibold text-casino-text">4. Juego responsable</h2>
        <p>
          Esto es un juego de entretenimiento sin dinero real. Aun así, te recomendamos jugar con
          moderación. Si el juego deja de ser divertido, para. Busca ayuda en asociaciones de juego
          responsable de tu país si la necesitas.
        </p>

        <h2 className="text-lg font-semibold text-casino-text">5. Transparencia</h2>
        <p>
          Todos los movimientos de fichas quedan registrados en un libro contable auditable (visible
          en tu billetera). Los dados se generan en el servidor; ningún cliente puede influir en el
          resultado.
        </p>
      </section>

      <Link to="/auth" className="text-sm text-casino-gold underline">
        ← Volver
      </Link>
    </main>
  );
}
