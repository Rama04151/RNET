/* Isi dengan Project URL dan publishable/anon key dari Supabase.
   Jangan pernah menaruh service_role key atau database password di frontend. */
window.RNET_CONFIG={SUPABASE_URL:"https://YOUR-PROJECT.supabase.co",SUPABASE_ANON_KEY:"YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY"};
window.rnetClient=null;
if(window.supabase&&!window.RNET_CONFIG.SUPABASE_URL.includes("YOUR-PROJECT")&&!window.RNET_CONFIG.SUPABASE_ANON_KEY.startsWith("YOUR_")){window.rnetClient=window.supabase.createClient(window.RNET_CONFIG.SUPABASE_URL,window.RNET_CONFIG.SUPABASE_ANON_KEY);}