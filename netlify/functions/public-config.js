// Returns only the public Supabase browser configuration.
// Set SUPABASE_URL and SUPABASE_ANON_KEY in Netlify Environment Variables.
// Never add service-role keys or Telegram credentials to this response.
exports.handler = async (event) => {
  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers: { "Content-Type": "application/json", "Allow": "GET" }, body: JSON.stringify({ error: "Method not allowed" }) };
  }
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.error("[public-config] Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variable");
    return { statusCode: 500, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" }, body: JSON.stringify({ error: "Konfigurasi Supabase belum lengkap di Netlify." }) };
  }
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=300" },
    body: JSON.stringify({ supabaseUrl: SUPABASE_URL, supabaseAnonKey: SUPABASE_ANON_KEY })
  };
};
