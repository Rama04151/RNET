/* RNET browser client config is supplied at runtime by a Netlify Function.
 * Only the public Supabase URL and publishable key are returned to the browser.
 * Never expose SUPABASE_SERVICE_ROLE_KEY or Telegram credentials here.
 */
(function () {
  const request = new XMLHttpRequest();
  request.open("GET", "/.netlify/functions/public-config", false);
  request.setRequestHeader("Accept", "application/json");
  try {
    request.send();
    if (request.status < 200 || request.status >= 300) throw new Error("HTTP " + request.status);
    const config = JSON.parse(request.responseText);
    if (!config.supabaseUrl || !config.supabaseAnonKey || !window.supabase) throw new Error("Konfigurasi Supabase tidak lengkap.");
    window.RNET_CONFIG = { SUPABASE_URL: config.supabaseUrl, SUPABASE_ANON_KEY: config.supabaseAnonKey };
    window.rnetClient = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey);
  } catch (error) {
    console.error("RNET config error:", error.message);
    window.rnetClient = null;
    alert("Konfigurasi RNET belum tersedia. Periksa Environment Variables Netlify.");
  }
})();
