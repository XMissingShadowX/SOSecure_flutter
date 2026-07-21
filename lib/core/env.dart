// Mismos valores públicos que NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY
// en el proyecto Next.js — el anon key está diseñado para ir embebido en clientes.
class Env {
  static const supabaseUrl = 'https://mtpbgfumbqfiiqgyjcey.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im10cGJnZnVtYnFmaWlxZ3lqY2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczMTUyMzIsImV4cCI6MjA5Mjg5MTIzMn0.z6oQOF1YVE1xnD1tEaL14aOJL1f0Q_hwB-ErzIDouMM';

  // Mismo backend Next.js que consume la web — las rutas /api/pin, /api/chat, etc.
  // viven ahí, sin cambios (ver plan de migración).
  // NOTA: 'sosecure.site' es el dominio documentado en CLAUDE.md como fuente de verdad
  // para los redirects de Magic Link (Supabase Auth) — pero en la red de prueba usada
  // para la Fase 2 ese dominio no resolvía DNS en el teléfono físico (fallo consistente,
  // no transitorio; sí resuelve desde la PC). Se usa el dominio de Vercel directamente
  // para desbloquear las pruebas. Si se prueba el flujo de "olvidé mi PIN"
  // (Magic Link) desde Flutter, revisar si Supabase acepta este dominio en su allowlist
  // de redirect URLs, o volver a 'https://sosecure.site' una vez resuelto el DNS.
  static const apiBaseUrl = 'https://sosecure-ten.vercel.app';
}
