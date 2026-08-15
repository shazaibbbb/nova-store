# NOVA Store — Final Production Package (Phase 5)

NOVA is a Supabase-backed e-commerce storefront designed for deployment on Vercel with a custom domain.

## Included
- Customer storefront
- Search/categories/cart
- Supabase Auth signup/login/password reset
- Checkout and delivery information
- Atomic order creation + stock validation
- Customer order history
- Admin dashboard
- Product/category/order/customer/settings management
- Product image storage policies
- Email + WhatsApp notification Edge Function
- Notification logs
- Security headers
- SEO placeholders
- Legal-page placeholders
- Deployment and testing documentation

## Important
This package is **deployment-ready but not already connected to your accounts**. You must add your own Supabase project values and notification-provider secrets. Never send private API keys in chat.

## First setup
1. Create Supabase project.
2. Run `schema.sql`.
3. Configure Email Auth.
4. Edit `config.js` with Supabase URL + anon key.
5. Create your first account.
6. Promote that account to admin with:

```sql
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL');
```

7. Deploy the notification Edge Function and configure its secrets.
8. Put the folder in GitHub and import it into Vercel.
9. Add your existing domain in Vercel.
10. Replace legal/SEO placeholders and run `TESTING.md` before opening the store publicly.

## Security
Only the Supabase anon/public key belongs in `config.js`. Never expose the Supabase service-role key or email/WhatsApp provider secrets in browser code.
