# NOVA — Phase 5 Production Deployment

## What this final package contains
- Supabase-backed storefront and authentication
- Customer accounts and order history
- Admin dashboard with RLS-protected store management
- Atomic order placement and stock validation
- Product image storage bucket policies
- Resend email + Meta WhatsApp notification Edge Function
- Notification logging
- Vercel security headers
- SEO robots/sitemap placeholders
- Legal-page placeholders

## 1. Supabase
1. Create a Supabase project.
2. Run `schema.sql` in SQL Editor.
3. Enable Email authentication.
4. Create an admin account through the website.
5. Promote it with the SQL shown in README.md.
6. Deploy `supabase/functions/send-order-notifications` with the Supabase CLI.
7. Set Edge Function secrets from `.env.example`.
8. Configure a verified Resend sending domain.
9. Configure Meta WhatsApp Cloud API and an approved template for business-initiated messages.

## 2. Frontend configuration
Edit `config.js` and put only the Supabase project URL and anon/public key there. Never put a service-role key in this file.

## 3. Vercel
1. Put this folder in a private GitHub repository.
2. Import the repository into Vercel.
3. Framework preset: Other.
4. Build command: leave empty.
5. Output directory: `.`.
6. Deploy.
7. Add the existing custom domain in Vercel → Settings → Domains.
8. Update DNS at your domain registrar using the exact records Vercel shows.

## 4. Replace placeholders before launch
- `YOUR-DOMAIN.example` in `robots.txt` and `sitemap.xml`
- Legal pages with your actual policies
- Store name/logo/contact details in Admin → Settings
- Email sending identity
- WhatsApp template and number

## 5. Final smoke test
- Create customer account
- Log in/out
- Add product to cart
- Change quantity
- Checkout with valid delivery data
- Confirm order appears in Supabase
- Confirm stock decreases atomically
- Confirm admin sees the order
- Confirm admin can change order status
- Confirm customer only sees their own orders
- Confirm admin email, customer email and WhatsApp notification results are logged
- Test mobile layout
- Test invalid/empty forms
- Test out-of-stock product
- Test a failed notification without losing the order
