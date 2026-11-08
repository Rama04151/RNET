/* RNET Supabase public client configuration.
 * Publishable key is intended for browser use. Keep RLS enabled.
 * Never put service_role/secret keys or database passwords here.
 */
window.RNET_CONFIG = {
  SUPABASE_URL: "https://eidbmblfwwrlipzevbow.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_J2xSsziYgbQzQog0Livnyw_0Hv8h8ye"
};

window.rnetClient = null;
if (window.supabase) {
  window.rnetClient = window.supabase.createClient(
    window.RNET_CONFIG.SUPABASE_URL,
    window.RNET_CONFIG.SUPABASE_ANON_KEY
  );
}
