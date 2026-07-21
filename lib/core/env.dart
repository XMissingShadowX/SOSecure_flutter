// Mismos valores públicos que NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY
// en el proyecto Next.js — el anon key está diseñado para ir embebido en clientes.
class Env {
  static const supabaseUrl = 'https://mtpbgfumbqfiiqgyjcey.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im10cGJnZnVtYnFmaWlxZ3lqY2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczMTUyMzIsImV4cCI6MjA5Mjg5MTIzMn0.z6oQOF1YVE1xnD1tEaL14aOJL1f0Q_hwB-ErzIDouMM';

  // Mismo backend Next.js que consume la web — las rutas /api/pin, /api/chat, etc.
  // viven ahí, sin cambios (ver plan de migración).
  // TEMPORAL: apuntando a Next.js local vía adb reverse tcp:3000 tcp:3000, para probar
  // el fix de getAuthedUser() antes de que se despliegue a producción. Revertir a
  // 'https://sosecure.site' antes de hacer merge/build de release.
  static const apiBaseUrl = 'http://localhost:3000';
}
