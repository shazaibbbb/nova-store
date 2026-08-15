import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const esc = (v: unknown) => String(v ?? '')
  .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
  .replaceAll('"','&quot;').replaceAll("'",'&#039;');

const money = (n: number) => `Rs. ${Number(n || 0).toLocaleString('en-PK')}`;

function emailHtml(title: string, body: string) {
  return `<!doctype html><html><body style="margin:0;background:#f4f7fb;font-family:Arial,sans-serif;color:#111827"><div style="max-width:680px;margin:30px auto;background:#fff;border-radius:18px;padding:28px;box-shadow:0 8px 30px rgba(0,0,0,.06)"><div style="font-size:25px;font-weight:800;margin-bottom:22px">NOVA<span style="color:#2563eb">.</span></div><h1 style="font-size:24px">${title}</h1>${body}<p style="color:#6b7280;font-size:13px;margin-top:30px">This is an automated message from NOVA.</p></div></body></html>`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const auth = req.headers.get('Authorization');
    if (!auth) throw new Error('Authentication required');

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey);
    const token = auth.replace(/^Bearer\s+/i, '');
    const { data: callerData, error: callerError } = await admin.auth.getUser(token);
    if (callerError || !callerData.user) throw new Error('Invalid session');

    const { order_id } = await req.json();
    if (!order_id) throw new Error('order_id is required');

    const { data: order, error: orderError } = await admin.from('orders').select('*').eq('id', order_id).single();
    if (orderError || !order) throw new Error('Order not found');

    const { data: profile } = await admin.from('profiles').select('role').eq('id', callerData.user.id).maybeSingle();
    const isAdmin = profile?.role === 'admin';
    if (!isAdmin && order.user_id !== callerData.user.id) throw new Error('Not allowed');

    const { data: items, error: itemsError } = await admin.from('order_items').select('*').eq('order_id', order_id);
    if (itemsError) throw itemsError;
    const { data: settings } = await admin.from('store_settings').select('*').eq('id', true).single();
    const storeName = settings?.store_name || 'NOVA';
    const adminEmail = settings?.admin_email || Deno.env.get('ADMIN_EMAIL') || '';
    const waTo = settings?.whatsapp || Deno.env.get('WHATSAPP_ADMIN_TO') || '';

    const itemRows = (items || []).map((i: any) => `<tr><td style="padding:9px;border-bottom:1px solid #e5e7eb">${esc(i.product_name)}</td><td style="padding:9px;border-bottom:1px solid #e5e7eb">${i.quantity}</td><td style="padding:9px;border-bottom:1px solid #e5e7eb;text-align:right">${money(i.unit_price * i.quantity)}</td></tr>`).join('');
    const table = `<table style="width:100%;border-collapse:collapse;margin:20px 0"><tr><th style="text-align:left;padding:9px">Product</th><th style="padding:9px">Qty</th><th style="text-align:right;padding:9px">Amount</th></tr>${itemRows}</table>`;
    const details = `<p><b>Order:</b> ${esc(order.order_number)}<br><b>Customer:</b> ${esc(order.customer_name)}<br><b>Phone:</b> ${esc(order.customer_phone)}<br><b>Address:</b> ${esc(order.delivery_address)}, ${esc(order.city)} ${esc(order.postal_code)}<br><b>Payment:</b> Cash on Delivery</p>`;
    const total = `<p style="font-size:18px"><b>Total: ${money(order.total)}</b></p>`;

    const resendKey = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('EMAIL_FROM') || 'NOVA <onboarding@resend.dev>';
    const emailResults: any[] = [];
    if (resendKey) {
      const sendEmail = async (to: string, subject: string, html: string) => {
        if (!to) return { skipped: true };
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from, to: [to], subject, html }),
        });
        const text = await r.text();
        if (!r.ok) throw new Error(`Resend ${r.status}: ${text}`);
        return JSON.parse(text);
      };
      try {
        emailResults.push({ channel:'admin_email', ...(await sendEmail(adminEmail, `New Order ${order.order_number}`, emailHtml(`New order received`, details + table + total))) });
      } catch (e) { emailResults.push({channel:'admin_email', error:String(e)}); }
      try {
        emailResults.push({ channel:'customer_email', ...(await sendEmail(order.customer_email, `Order confirmed — ${order.order_number}`, emailHtml(`Thank you for your order`, details + table + total + `<p>We have received your order and will process it shortly.</p>`))) });
      } catch (e) { emailResults.push({channel:'customer_email', error:String(e)}); }
    } else {
      emailResults.push({channel:'email', skipped:true, reason:'RESEND_API_KEY not configured'});
    }

    const waToken = Deno.env.get('WHATSAPP_ACCESS_TOKEN');
    const waPhoneId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
    const waTemplate = Deno.env.get('WHATSAPP_TEMPLATE_NAME');
    let whatsappResult: any = { skipped:true };
    if (waToken && waPhoneId && waTo) {
      const digits = waTo.replace(/\D/g,'');
      if (!digits) throw new Error('WHATSAPP_ADMIN_TO must contain a phone number');
      const text = `🛍️ NEW ORDER\nOrder: ${order.order_number}\nCustomer: ${order.customer_name}\nPhone: ${order.customer_phone}\nAddress: ${order.delivery_address}, ${order.city}\nTotal: ${money(order.total)}\nPayment: COD`;
      const payload = waTemplate ? {
        messaging_product:'whatsapp', to:digits, type:'template',
        template:{ name:waTemplate, language:{code:Deno.env.get('WHATSAPP_TEMPLATE_LANGUAGE') || 'en_US'}, components:[{type:'body',parameters:[
          {type:'text',text:order.order_number},{type:'text',text:order.customer_name},{type:'text',text:order.customer_phone},{type:'text',text:money(order.total)}
        ]}]}
      } : { messaging_product:'whatsapp', to:digits, type:'text', text:{body:text} };
      const r = await fetch(`https://graph.facebook.com/v23.0/${waPhoneId}/messages`, {method:'POST',headers:{Authorization:`Bearer ${waToken}`,'Content-Type':'application/json'},body:JSON.stringify(payload)});
      const tx = await r.text();
      whatsappResult = r.ok ? JSON.parse(tx) : {error:`WhatsApp ${r.status}: ${tx}`};
    } else {
      whatsappResult = {skipped:true, reason:'WhatsApp environment variables are not configured'};
    }

    const logs = emailResults.map(x => ({order_id, channel:x.channel || 'email', status:x.error ? 'failed' : (x.skipped ? 'skipped':'sent'), provider_response:x}));
    logs.push({order_id, channel:'whatsapp', status:whatsappResult.error ? 'failed' : (whatsappResult.skipped ? 'skipped':'sent'), provider_response:whatsappResult});
    await admin.from('notification_logs').insert(logs);

    return new Response(JSON.stringify({ok:true, email:emailResults, whatsapp:whatsappResult}), {headers:{...cors,'Content-Type':'application/json'}});
  } catch (e) {
    return new Response(JSON.stringify({ok:false,error:String(e)}), {status:400, headers:{...cors,'Content-Type':'application/json'}});
  }
});
