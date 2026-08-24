# DeseoCerca Staging Runbook

This runbook is the operational path from the `deseocerca-v1` branch to the first internet-accessible staging environment. It deliberately keeps production DNS unchanged until staging acceptance is complete.

## 1. Hosting boundary

DeseoCerca V1 is an adults-only (18+) social/dating UGC product. It is not a marketplace or broker for paid sexual services. The product prohibits minors, trafficking, exploitation, non-consensual intimate content, impersonation, harassment and paid sexual-service solicitation/intermediation.

Before purchasing production capacity, obtain written confirmation from the hosting provider that this exact business model is acceptable. For the current staging candidate, DigitalOcean's current AUP focuses its pornography prohibition on unlawful pornography/CSAM/non-consensual sexual material rather than banning all legal adult social products. Provider approval is still required because providers retain enforcement discretion.

Do not use Hetzner for this project while its published terms continue to prohibit pornographic or obscene material broadly.

## 2. Staging server

Recommended starting capacity:

- Ubuntu LTS
- 2 vCPU minimum
- 4 GB RAM minimum
- 80 GB SSD or larger
- Public IPv4
- SSH key authentication only
- Inbound TCP 22, 80 and 443
- Docker Engine with Docker Compose v2

Create a non-root deployment user with Docker permission. Disable password SSH login after verifying key access.

The GitHub Actions workflow deploys to:

`/opt/deseocerca-staging`

## 3. Staging hostname

Preferred hostname:

`staging.deseocerca.com`

Once the VPS public IP is known, create one DNS `A` record:

- Host: `staging`
- Type: `A`
- Value: `<STAGING_VPS_IPV4>`

Do not change the apex `deseocerca.com` or `www` records yet.

Caddy handles HTTP to HTTPS and certificate issuance when `STAGING_SITE_ADDRESS` contains the staging hostname and DNS resolves to the VPS.

## 4. GitHub Actions secrets

Configure these repository Actions secrets. Never commit their values.

- `DESEOCERCA_STAGING_HOST` — staging VPS IPv4 or resolvable hostname
- `DESEOCERCA_STAGING_USER` — non-root SSH deployment user
- `DESEOCERCA_STAGING_PORT` — usually `22`
- `DESEOCERCA_STAGING_SSH_KEY` — private SSH key dedicated to staging deployment
- `DESEOCERCA_STAGING_SITE_ADDRESS` — `staging.deseocerca.com` after DNS is ready; use `:80` only for a temporary IP-only first boot
- `DESEOCERCA_STAGING_DB_PASSWORD` — strong random MySQL application password
- `DESEOCERCA_STAGING_DB_ROOT_PASSWORD` — separate strong random MySQL root password
- `DESEOCERCA_STAGING_MAILER_DSN` — SMTP DSN after an email provider has been configured; it may be empty only during the earliest infrastructure smoke test

Use a dedicated staging SSH key and dedicated database passwords. Do not reuse personal keys or production credentials.

## 5. What the staging workflow does

`.github/workflows/deseocerca-staging.yml` performs the deployment through SSH:

1. validates required secrets;
2. synchronizes the `deseocerca-v1` branch to the VPS;
3. writes the protected `.env` file on the server;
4. runs `docker compose up -d --build --remove-orphans`;
5. starts MySQL, the PHP/Apache app, the account-lifecycle sidecar and Caddy;
6. verifies container-level HTTP response;
7. distinguishes a first-install state from an installed runtime;
8. on an installed runtime, requires the installer directory to remain removed and runs `verify-runtime.php`.

Runtime state is persisted separately from the image. `_constants.php`, application configuration, public/protected data, module data and MySQL data survive container replacement.

## 6. First installation

On the first deployment, `_constants.php` does not yet exist and the installer is intentionally available.

Complete the pH7Builder browser installer on the staging hostname using:

- MySQL host: `db`
- MySQL port: `3306`
- Database: `deseocerca`
- Database user: `deseocerca`
- Database password: the value of `DESEOCERCA_STAGING_DB_PASSWORD`
- Table prefix: `ph7_`
- Protected path: `/var/www/html/_protected/`
- Dating-oriented base configuration
- A unique admin username/password not used anywhere else

Do not add sample/fake user data to staging acceptance.

After installation finishes, the container entrypoint mirrors `_constants.php` to the runtime volume. On subsequent starts, the entrypoint restores the file and removes `_install` automatically.

## 7. Apply DeseoCerca bootstrap once

After the browser installer is complete, manually dispatch `DeseoCerca Staging Deploy` again with the workflow input:

`apply_bootstrap = true`

The workflow calls `deploy/deseocerca/apply-bootstrap.sh`. It refuses to run unless the site is installed and the configured database prefix is exactly `ph7_`.

Bootstrap applies the DeseoCerca brand, Spanish/Lima defaults, 18+ registration requirements, moderation settings, V1 module choices, favorites/blocks/lifecycle schema and related launch configuration. It then runs the read-only runtime verifier.

Normal future deployments must leave `apply_bootstrap` false.

## 8. Required staging acceptance

Do not point the production domain until all of these pass on staging:

- HTTPS certificate valid;
- home page loads without installer redirect;
- registration rejects users under 18;
- email activation works;
- login/logout and password recovery work;
- avatar/photo upload enters the configured moderation workflow;
- inactive/deactivated profiles are not publicly discoverable;
- search and nearby discovery work for Peru/Lima;
- favorite and recent-view flows work;
- block immediately prevents private mail and instant messaging in both directions;
- report flow creates an admin-visible moderation record;
- report self-target/invalid-target protections work;
- Terms, Privacy, Legal Notice and Contact/Safety are reachable from the footer;
- account deactivation/reactivation works during the recovery period;
- lifecycle service is running and the 60/83/90-day policy tables are present;
- `_install` is absent after installation;
- `php deploy/deseocerca/verify-runtime.php` returns `healthy: true`;
- MySQL and application data survive `docker compose up -d --build` and a container replacement;
- no test credentials, SSH keys or database passwords are committed to GitHub.

## 9. Production blockers that remain outside code

Before production launch, provide and verify:

- legal name/entity operating DeseoCerca;
- applicable tax/registration identifier and legal address;
- final hosting-provider identity for the public Legal Notice;
- hosting-provider written approval for the actual 18+ social/dating UGC model;
- production SMTP sender/domain verification;
- final privacy/terms legal review for Peru;
- production DNS change for `deseocerca.com` and `www.deseocerca.com` only after staging acceptance.

Until these items and staging E2E are complete, PR #1 should remain draft and production DNS should remain unchanged.
