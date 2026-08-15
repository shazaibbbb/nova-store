# NOVA Phase 3 — Order notifications

This Supabase Edge Function sends:
- Admin new-order email
- Customer order-confirmation email
- Admin WhatsApp notification

## Required secrets
Set these as Supabase Edge Function secrets, never in `config.js`:

- `RESEND_API_KEY`
- `EMAIL_FROM`
- `ADMIN_EMAIL` (fallback if Store Settings admin_email is empty)
- `WHATSAPP_ACCESS_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_ADMIN_TO`
- `WHATSAPP_TEMPLATE_NAME` (recommended)
- `WHATSAPP_TEMPLATE_LANGUAGE` (default `en_US`)

Resend requires a verified sending domain for production sending. WhatsApp Cloud API business-initiated messages may require an approved Meta message template; configure `WHATSAPP_TEMPLATE_NAME` with an approved template whose first four body variables are order number, customer name, phone, and total.

## Deploy
Install Supabase CLI, log in, link the project, then:

```bash
supabase secrets set RESEND_API_KEY=... EMAIL_FROM='NOVA <orders@yourdomain.com>' ADMIN_EMAIL=... WHATSAPP_ACCESS_TOKEN=... WHATSAPP_PHONE_NUMBER_ID=... WHATSAPP_ADMIN_TO=... WHATSAPP_TEMPLATE_NAME=order_notification WHATSAPP_TEMPLATE_LANGUAGE=en_US
supabase functions deploy send-order-notifications
```

Run the Phase 3 SQL in `schema.sql` before testing.
