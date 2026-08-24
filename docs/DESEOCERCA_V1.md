# DeseoCerca V1

## Product position

DeseoCerca is an adults-only social discovery and profile platform for Peru. It is designed for people aged 18+ to create profiles, discover nearby adults, communicate privately, and use safety controls such as reporting and blocking.

The V1 product must not be used to offer, price, book, broker, or collect commissions for paid sexual services. It must also prohibit minors, trafficking, exploitation, non-consensual intimate content, impersonation, doxxing, and illegal content.

## Domain

Primary domain: `deseocerca.com`

Planned canonical host: `https://deseocerca.com`

`www.deseocerca.com` should redirect to the canonical host.

The domain may remain registered with Alibaba Cloud. DNS can later be delegated to the selected production DNS/CDN provider without moving the registration.

Production apex/`www` DNS must remain unchanged until staging acceptance is complete.

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
- Account deactivation with a defined recovery/deletion lifecycle.

### Communication

- Private mail.
- Instant messaging.
- Friend/contact relationships.
- Notifications.
- Server-side block enforcement for private mail and instant messaging.
- Messaging cooldown and message-length limits.

### Trust and safety

- Manual approval for avatars, pictures and videos during V1.
- User and content reporting.
- Blocking tools.
- Registration CAPTCHA.
- Login-attempt protection.
- Admin moderation queues.
- Audit-friendly admin operations.
- Inactive/deactivated profiles hidden from public profile/discovery flows.
- Spanish Terms, Privacy, Legal Notice and Contact/Safety entry points.

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

Spanish is pinned from the upstream pH7 Internationalization project and is now installed during the staging image build. Runtime timezone/date defaults are adjusted to Lima/Peru while retaining the compatible `es_ES` locale identifier.

The translations should still be reviewed for natural Peruvian Spanish before public launch. The bootstrap SQL registers Spanish, makes it the default UI language and adds Peru-focused Spanish SEO metadata.

## Current deployment architecture

The staging path is containerized and reproducible:

- Docker Compose
- MySQL 8.0 with a persistent database volume
- PHP 8.2 + Apache application image
- Caddy edge container for HTTP/HTTPS
- account-lifecycle sidecar
- persistent runtime volume for installer-generated `_constants.php`
- persistent application configuration/data/module volumes
- GitHub Actions SSH deployment workflow

The application entrypoint restores `_constants.php` after container replacement. Once an installed runtime is detected it removes `_install` on every start so rebuilding the image does not reopen the installer.

Spanish/Lima localization is part of the built staging image rather than an untracked post-deploy mutation.

## CI baseline

Pull-request CI covers:

- Composer validation
- PHPUnit test matrix
- PHPStan
- development Docker Compose
- development image build and installer response
- staging Compose validation
- staging image build
- DeseoCerca maintenance/runtime PHP syntax
- Spanish locale presence
- staging entrypoint syntax
- runtime `_constants.php` persistence/restore behavior
- installer-directory removal for an installed runtime

A green CI result is necessary but is not equivalent to staging E2E acceptance.

## Deployment order

The detailed operational runbook is `docs/DESEOCERCA_STAGING.md`.

1. Obtain hosting-provider approval for the actual legal 18+ social/dating UGC model.
2. Provision the staging VPS with Docker Engine/Compose and SSH-key access.
3. Point only `staging.deseocerca.com` to the staging VPS; leave production apex/`www` unchanged.
4. Configure the `DESEOCERCA_STAGING_*` GitHub Actions secrets.
5. Dispatch `DeseoCerca Staging Deploy` with `apply_bootstrap=false` for the first infrastructure deployment.
6. Complete the pH7 browser installer using MySQL host `db`, database/user `deseocerca`, prefix `ph7_`, and protected path `/var/www/html/_protected/`.
7. Dispatch the staging workflow once with `apply_bootstrap=true` to apply the DeseoCerca bootstrap and run runtime verification.
8. Configure and verify SMTP, then test activation and password-recovery email.
9. Complete account, photo moderation, discovery, block, report, messaging, lifecycle and legal-page E2E acceptance.
10. Confirm container replacement preserves database/application state and keeps `_install` unavailable.
11. Complete the Legal Notice with the real operator identity, legal/tax details as applicable, legal address and final hosting provider.
12. Obtain Peru legal review for production Terms/Privacy/Legal Notice.
13. Enable production DNS for `deseocerca.com` and `www.deseocerca.com` only after all staging gates pass.

## Current external production blockers

Code must not invent these values. They must be supplied and verified before launch:

- Legal name/entity operating DeseoCerca.
- Applicable tax/registration identifier.
- Legal address.
- Final hosting-provider identity and written business-model approval.
- Production SMTP sender/domain verification.
- Final Peru legal review.
- Staging VPS/SSH credentials and DNS record.

## Next implementation milestones

### Staging acceptance

- First real staging deployment.
- First browser installation and one-time bootstrap.
- HTTPS and email verification.
- Full E2E acceptance across user and moderator flows.
- Mobile/responsive review on the live staging URL.

### Product maturity after staging baseline

- Peru/Lima discovery tuning using real staging data.
- Registration/onboarding copy cleanup.
- Profile card and discovery UX polish.
- Moderation queue UX refinement.
- Conversation empty/error-state polish.
- Verified-profile workflow.

### Monetization readiness

- Featured placement.
- Boost inventory.
- Premium filters.
- Billing abstraction, with gateway integration only after merchant approval.
- Analytics and conversion events.

## Reference code policy

The pH7Builder fork is used because it already contains mature dating/social logic and is MIT licensed. Upstream copyright and license files must remain intact. DeseoCerca-specific work should stay isolated on the `deseocerca-v1` branch until it has passed CI and staging acceptance.

PR #1 should remain draft until staging E2E, operational and legal launch gates are complete.
