# NOVA Production Test Checklist

## Authentication
- [ ] Signup with valid data
- [ ] Reject invalid email/password
- [ ] Login/logout
- [ ] Password reset
- [ ] Customer cannot access admin functions
- [ ] Admin can access dashboard

## Storefront
- [ ] Products load from Supabase
- [ ] Search works
- [ ] Category filter works
- [ ] Product detail works
- [ ] Add/remove/change cart quantity
- [ ] Cart survives refresh
- [ ] Out-of-stock product cannot be ordered

## Checkout
- [ ] Login required
- [ ] Name/phone/email/address validation
- [ ] Correct delivery fee
- [ ] Correct total
- [ ] Order number generated
- [ ] Database order created
- [ ] Order items created from database prices
- [ ] Stock is reduced atomically
- [ ] Customer receives order confirmation
- [ ] Admin receives new-order email
- [ ] Admin WhatsApp notification works

## Admin
- [ ] Dashboard statistics
- [ ] Add/edit/archive product
- [ ] Manage categories
- [ ] Update order status
- [ ] View customers
- [ ] Update store settings
- [ ] Upload product image

## Production
- [ ] HTTPS/custom domain
- [ ] Security headers
- [ ] robots.txt uses real domain
- [ ] sitemap.xml uses real domain
- [ ] Legal pages finalized
- [ ] No secrets committed to Git
- [ ] No Supabase service-role key in frontend
