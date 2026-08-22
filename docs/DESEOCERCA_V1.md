# DeseoCerca V1

## Product position

DeseoCerca is an adults-only social discovery and profile platform for Peru. It is designed for people aged 18+ to create profiles, discover nearby adults, communicate privately, and use safety controls such as reporting and blocking.

The V1 product must not be used to offer, price, book, broker, or collect commissions for paid sexual services. It must also prohibit minors, trafficking, exploitation, non-consensual intimate content, impersonation, doxxing, and illegal content.

## Domain

Primary domain: `deseocerca.com`

Planned canonical host: `https://deseocerca.com`

`www.deseocerca.com` should redirect to the canonical host.

The domain may remain registered with Alibaba Cloud. DNS can later be delegated to the selected production DNS/CDN provider without moving the registration.

## V1 feature set

### Public discovery

- Adults-only entry gate.
- Profile cards and profile detail pages.
- Search and filtering by age, gender/preferences and location.
- Nearby people / location discovery.
- Featured profiles.
- Responsive mobile-first experience.

### Account and profile

- Registration and login.
- Minimum registration age of 18.
- Email activation.
- Required profile image during launch stage.
- Photo albums and profile information.
- Privacy controls.
- Profile visitors and related profiles.

### Communication

- Private mail.
- Instant messaging.
- Friend/contact relationships.
- Notifications.

### Trust and safety

- Manual approval for avatars, pictures and videos during V1.
- User and content reporting.
- Blocking tools.
- Registration CAPTCHA.
- Login-attempt protection.
- Admin moderation queues.
- Audit-friendly admin operations.

### Business features kept for later activation

- Premium membership groups.
- Featured placement / boosts.
- Advertising inventory.

Payment gateways remain disabled until the selected payment processor has approved the actual business model and Peru operating entity.

## Modules disabled for V1

The post-install bootstrap disables modules that add complexity without helping the initial social-discovery product:

- Affiliate
- Forum
- Community notes/blog
- Company blog
- Love calculator
- Invite friends

They can be restored later from the admin panel after moderation and operations are stable.

## Brand direction

The `datelove` theme is used as the initial base because it already inherits the maintained pH7Builder base templates. DeseoCerca overrides the theme identity and adds a dark, privacy-oriented visual layer.

Initial design direction:

- Dark neutral background.
- Warm rose accent.
- Rounded cards and controls.
- Large tap targets on mobile.
- Avoid explicit or pornographic imagery in product chrome and marketing assets.

## Peru localization

The initial repository still contains the upstream English UI strings. Spanish should be installed from the upstream pH7 Internationalization project and reviewed for Peruvian Spanish before `defaultLanguage` is switched to `es_ES`.

The included bootstrap SQL already adds Spanish SEO metadata for the Peru landing page.

## Production baseline

pH7Builder 18.x currently requires:

- PHP 8.2+
- MySQL 8.0+
- nginx or Apache with URL rewriting
- HTTPS
- SMTP transport for account email

Recommended first deployment:

- Ubuntu LTS VPS
- nginx
- PHP 8.2 FPM
- MySQL 8.0
- Let's Encrypt TLS
- Daily database backup plus encrypted off-server backup
- Separate SMTP provider

Do not deploy production media or secrets into GitHub.

## Deployment order

1. Provision a clean VPS whose provider has approved the intended adult social/dating content and UGC model.
2. Point the staging hostname to the VPS.
3. Install PHP 8.2+, MySQL 8.0 and nginx.
4. Deploy the `deseocerca-v1` branch.
5. Run the pH7Builder browser installer with a one-time install token.
6. Remove/disable installer access.
7. Run `deploy/deseocerca/bootstrap.sql` against the installed database.
8. Configure `PH7_MAILER_DSN` in the server environment and test activation email.
9. Install and review the Spanish language pack, then switch the default language to `es_ES`.
10. Complete manual account, photo, report, block, message and admin moderation tests.
11. Enable production DNS for `deseocerca.com` only after the staging checks pass.

## Next implementation milestones

### Sprint 1 — launch foundation

- Spanish localization.
- Peru/Lima-first location defaults.
- Registration/onboarding cleanup.
- Modern home/discovery layout.
- Profile card redesign.
- Account/profile photo moderation workflow.

### Sprint 2 — safety and communication

- Block/report entry points on every profile and conversation.
- Messaging anti-spam limits.
- Conversation empty/error states.
- Moderator history and audit view.
- Verified-profile workflow.

### Sprint 3 — monetization readiness

- Featured placement.
- Boost inventory.
- Premium filters.
- Billing abstraction, with gateway integration only after merchant approval.
- Analytics and conversion events.

## Reference code policy

The pH7Builder fork is used because it already contains mature dating/social logic and is MIT licensed. Upstream copyright and license files must remain intact. DeseoCerca-specific work should stay isolated on the `deseocerca-v1` branch until it has passed CI and staging acceptance.
