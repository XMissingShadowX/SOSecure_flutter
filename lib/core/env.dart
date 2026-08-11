// Mismos valores públicos que NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY
// en el proyecto Next.js — el anon key está diseñado para ir embebido en clientes.
class Env {
  static const supabaseUrl = 'https://mtpbgfumbqfiiqgyjcey.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im10cGJnZnVtYnFmaWlxZ3lqY2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczMTUyMzIsImV4cCI6MjA5Mjg5MTIzMn0.z6oQOF1YVE1xnD1tEaL14aOJL1f0Q_hwB-ErzIDouMM';

  // Mismo backend Next.js que consume la web — las rutas /api/pin, /api/chat, etc.
  // viven ahí, sin cambios (ver plan de migración).
  //
  // Va CON 'www' a propósito. El dominio canónico en Vercel es
  // www.sosecure.site; 'https://sosecure.site' responde 307 hacia el www, y en
  // ese redirect un POST pierde el cuerpo y devuelve HTML ("Redirecting...")
  // en vez de JSON — el mismo fallo que causaba la barra final faltante en
  // plan_api.dart. Verificado: sin www da 307, con www da 401 JSON.
  //
  // Antes apuntaba a 'https://sosecure-ten.vercel.app' porque sosecure.site no
  // resolvía DNS en el teléfono de pruebas; ese problema ya no ocurre (ping OK
  // desde el Pixel a 216.198.79.1).
  static const apiBaseUrl = 'https://www.sosecure.site';
}
