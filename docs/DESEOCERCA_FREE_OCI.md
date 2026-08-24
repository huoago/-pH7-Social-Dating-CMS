# DeseoCerca — Oracle Cloud Always Free staging

This runbook is the preferred zero-monthly-cost staging path for DeseoCerca.
It is designed for the existing Docker Compose stack and does not require a
rewrite of the PHP/MySQL application.

## 1. Create one Oracle Cloud Free Tier account

Oracle requires the account owner to complete identity/contact/payment-card
verification. Do not create multiple free accounts. Do not upgrade to Pay As
You Go unless you intentionally want paid resources.

Choose the home region carefully because Always Free compute must be created in
the tenancy home region. For a Peru-focused staging site, try a nearby South
America region with available Always Free A1 capacity, preferably Santiago,
then Valparaiso/Bogota if those are the available choices during signup.

## 2. Create the VM

Recommended shape when available:

- Shape: `VM.Standard.A1.Flex` (Always Free eligible)
- OCPU: 2
- Memory: 12 GB
- Image: Ubuntu 24.04 LTS or Ubuntu 22.04 LTS
- Boot volume: 50 GB is sufficient for staging
- Public IPv4: enabled
- SSH: add your own public key; never upload a private key

Fallback if A1 has no capacity:

- `VM.Standard.E2.1.Micro` (Always Free eligible)
- The bootstrap automatically adds a 2 GB swap file on low-memory VMs
- This fallback is suitable for staging/testing but much less comfortable for
  the complete MySQL + PHP + Caddy Docker stack

If OCI reports `Out of host capacity`, try another availability domain when the
region provides one, or retry later. Do not create a paid shape just to bypass
Always Free capacity.

## 3. Paste the cloud-init

During instance creation, paste the contents of:

`deploy/deseocerca/oracle-cloud-init.yaml.example`

into the instance initialization/cloud-init field.

The VM will automatically:

1. install Docker Engine + Compose and Git;
2. enable the host firewall;
3. clone `deseocerca-v1`;
4. generate strong MySQL credentials;
5. create `/opt/deseocerca-staging/.env` with mode `600`;
6. start MySQL, the PHP/Apache app, Caddy and the lifecycle service;
7. perform a local HTTP smoke check.

The generated database credentials remain root-only at:

`/root/deseocerca-staging-secrets.txt`

Never paste that file into a public issue, pull request or chat screenshot.

## 4. OCI network ingress

The Ubuntu firewall is configured by the bootstrap, but the OCI VCN/security
list also has to allow the traffic before the site is reachable from the
internet.

Allow inbound TCP:

- `22` from your administration IP where practical;
- `80` from the internet for first-install HTTP and ACME redirects;
- `443` from the internet for HTTPS after DNS is configured.

Do not expose MySQL `3306` publicly. The database is reachable only through the
Docker internal network.

## 5. First browser installation

Before production DNS changes, open the VM public IPv4 address in a browser.
The pH7 installer should appear.

Use:

- Database host: `db`
- Database name: `deseocerca`
- Database user: `deseocerca`
- Database password: read the generated value from the root-only secrets file
- Table prefix: **exactly `ph7_`**

Complete the administrator setup with a strong unique password.

After the browser installer finishes, the container entrypoint persists
`_constants.php` outside the image and removes `_install`. Rebuilding the image
therefore does not reopen the installer.

## 6. Apply the guarded DeseoCerca bootstrap once

SSH to the VM and run:

```bash
cd /opt/deseocerca-staging
sudo bash deploy/deseocerca/apply-bootstrap.sh
```

This applies the DeseoCerca brand, Spanish/Peru defaults, 18+ restrictions,
manual-media moderation defaults, favorites/blocks/lifecycle tables and module
configuration, then runs the read-only runtime verifier.

Do not repeatedly execute the SQL manually.

## 7. Point only the staging hostname

Do **not** point `deseocerca.com` yet.

At the current DNS provider create:

- Type: `A`
- Host: `staging`
- Value: the Oracle VM public IPv4
- TTL: 600 or the provider's automatic/default value

Then on the VM change `STAGING_SITE_ADDRESS` in `.env` from `:80` to:

`staging.deseocerca.com`

and restart the proxy:

```bash
cd /opt/deseocerca-staging
docker compose --env-file .env -f deploy/deseocerca/compose.staging.yml up -d caddy
```

Caddy will request and renew HTTPS automatically once public DNS and ports
80/443 are correct.

## 8. Configure GitHub redeployments

After the first VM is healthy, add repository Actions secrets:

- `DESEOCERCA_STAGING_HOST`
- `DESEOCERCA_STAGING_USER`
- `DESEOCERCA_STAGING_SSH_KEY`
- `DESEOCERCA_STAGING_DB_PASSWORD`
- `DESEOCERCA_STAGING_DB_ROOT_PASSWORD`
- optional `DESEOCERCA_STAGING_PORT`
- optional `DESEOCERCA_STAGING_SITE_ADDRESS`
- optional `DESEOCERCA_STAGING_MAILER_DSN`

The database values are in `/root/deseocerca-staging-secrets.txt`. The SSH key
must be the private key corresponding to the public key installed on the VM.
Store it only as a GitHub secret.

## 9. Staging acceptance gate

Do not merge PR #1 or point the production domain until all of these pass on the
real VM:

- HTTPS valid;
- `_install` inaccessible after a container rebuild;
- `verify-runtime.php` healthy;
- user registration with 18+ confirmation;
- email activation and password recovery;
- profile/photo upload + moderator approval;
- discovery/search/nearby/favorites/recent views;
- report + block + private mail + IM restrictions;
- administrator moderation screens;
- voluntary deletion + recovery link;
- inactivity lifecycle dry-run/controlled test;
- container replacement preserves database, uploaded data and `_constants.php`;
- mobile layout acceptance.

## Operational limits of the zero-cost approach

Always Free capacity is not an SLA-backed production guarantee. OCI may reclaim
eligible idle Always Free compute under its published idle-resource rules, and
capacity for A1 shapes can temporarily be unavailable. For that reason this is
an excellent zero-cost staging/early-launch path, but backups and a migration
plan remain mandatory before the site accumulates irreplaceable user data.
