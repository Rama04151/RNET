// Netlify Function: receives proof image, forwards it to Telegram, and creates a pending deposit.
// Required Netlify environment variables (never commit these):
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
const json=(statusCode,body)=>({statusCode,headers:{"Content-Type":"application/json","Cache-Control":"no-store"},body:JSON.stringify(body)});
exports.handler=async(event)=>{
 if(event.httpMethod!=="POST")return json(405,{error:"Method tidak diizinkan."});
 const origin=event.headers.origin||event.headers.Origin;
 if(origin&&origin!=="https://rnetstore.netlify.app")return json(403,{error:"Origin tidak diizinkan."});
 const env=process.env;
 for(const key of ["SUPABASE_URL","SUPABASE_ANON_KEY","SUPABASE_SERVICE_ROLE_KEY","TELEGRAM_BOT_TOKEN","TELEGRAM_CHAT_ID"])if(!env[key])return json(500,{error:"Konfigurasi server belum lengkap: "+key});
 const auth=event.headers.authorization||event.headers.Authorization||"";
 const token=auth.startsWith("Bearer ")?auth.slice(7):"";
 if(!token)return json(401,{error:"Silakan login kembali."});
 let input;try{input=JSON.parse(event.body||"{}")}catch{return json(400,{error:"Format permintaan tidak valid."})}
 const amount=Number(input.amount),method=String(input.payment_method_id||""),mime=String(input.mime_type||""),image=String(input.image_base64||"");
 if(!Number.isSafeInteger(amount)||amount<1000)return json(400,{error:"Minimal deposit Rp1.000."});
 if(!/^[0-9a-f-]{36}$/i.test(method))return json(400,{error:"Metode pembayaran tidak valid."});
 if(!["image/jpeg","image/png","image/webp"].includes(mime))return json(400,{error:"Format bukti harus JPG, PNG, atau WEBP."});
 if(!image||image.length>4*1024*1024)return json(400,{error:"Bukti kosong atau terlalu besar. Maksimal 3 MB."});
 const buffer=Buffer.from(image,"base64");if(buffer.length>3*1024*1024)return json(400,{error:"Ukuran bukti maksimal 3 MB."});
 const base=env.SUPABASE_URL.replace(/\/$/,""),headers={"apikey":env.SUPABASE_SERVICE_ROLE_KEY,"Authorization":"Bearer "+env.SUPABASE_SERVICE_ROLE_KEY,"Content-Type":"application/json"};
 try{
  const authRes=await fetch(base+"/auth/v1/user",{headers:{"apikey":env.SUPABASE_ANON_KEY,"Authorization":"Bearer "+token}});
  if(!authRes.ok)return json(401,{error:"Sesi login tidak valid. Silakan login kembali."});
  const user=await authRes.json();
  const profileRes=await fetch(base+"/rest/v1/profiles?id=eq."+encodeURIComponent(user.id)+"&select=id,full_name,role,is_active",{headers});
  const profiles=await profileRes.json();const profile=profiles[0];
  if(!profile||!profile.is_active||!["buyer","admin"].includes(profile.role))return json(403,{error:"Akun tidak aktif atau tidak diizinkan."});
  const methodRes=await fetch(base+"/rest/v1/payment_methods?id=eq."+encodeURIComponent(method)+"&is_active=eq.true&select=id,name,account_name,account_number",{headers});
  const methods=await methodRes.json();if(!methods.length)return json(400,{error:"Metode pembayaran sudah tidak tersedia."});
  const payment=methods[0];
  const createRes=await fetch(base+"/rest/v1/deposits",{method:"POST",headers:{...headers,"Prefer":"return=representation"},body:JSON.stringify({user_id:user.id,payment_method_id:method,amount,status:"pending"})});
  const created=await createRes.json();if(!createRes.ok||!created[0])return json(500,{error:"Gagal membuat antrean deposit di database."});
  const deposit=created[0];
  const ext=mime==="image/png"?"png":mime==="image/webp"?"webp":"jpg";
  const form=new FormData();form.append("chat_id",env.TELEGRAM_CHAT_ID);
  const caption="🧾 DEPOSIT RNET STORE\nNomor: "+deposit.id+"\nNama: "+(profile.full_name||user.email||"Buyer")+"\nEmail: "+(user.email||"-")+"\nNominal: Rp"+amount.toLocaleString("id-ID")+"\nMetode: "+payment.name+"\nAkun tujuan: "+[payment.account_name,payment.account_number].filter(Boolean).join(" / ")+"\nStatus: MENUNGGU VERIFIKASI";
  form.append("caption",caption);form.append("photo",new Blob([buffer],{type:mime}),"bukti-deposit."+ext);
  const tg=await fetch("https://api.telegram.org/bot"+env.TELEGRAM_BOT_TOKEN+"/sendPhoto",{method:"POST",body:form});
  const tgResult=await tg.json();
  if(!tg.ok||!tgResult.ok){await fetch(base+"/rest/v1/deposits?id=eq."+encodeURIComponent(deposit.id),{method:"DELETE",headers});return json(502,{error:"Telegram gagal menerima bukti. Deposit belum dibuat, silakan coba lagi."})}
  const fileId=tgResult.result?.photo?.slice(-1)[0]?.file_id||"sent";
  await fetch(base+"/rest/v1/deposits?id=eq."+encodeURIComponent(deposit.id),{method:"PATCH",headers,body:JSON.stringify({proof_url:"telegram:"+fileId})});
  return json(200,{ok:true,deposit_id:deposit.id,status:"pending"});
 }catch(error){return json(500,{error:"Kesalahan server saat memproses deposit."})}
};