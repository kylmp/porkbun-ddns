# Dynamic DNS Updates for Porkbun

A lightweight Bash script that retrieves your public IP address and updates DNS records on **Porkbun** automatically using their API.

Rotates IP services to avoid rate limiting.

Writes to a status file info of the last script execution.

This script supports **multiple records**, each with its own configurable:

- **Domain**
- **TTL**
- **Type** (e.g., A, AAAA)
- **Subdomain** (supports root `@`, wildcard `*`, and normal subdomains)

---

## How It Works

1. Script fetches your current **public IP**.
2. Compares it with the previously saved IP (stored locally).
3. If the IP has changed, it updates your configured DNS records via the Porkbun API.
4. If unchanged, it can still update in case Porkbun was out of sync.

---

## Installation (Unix / Linux)

1. **Clone the repository**
   ```bash
   git clone https://github.com/kylmp/porkbun-ddns.git
   ```

2. **Enter the directory**
   ```bash
   cd porkbun-ddns
   ```

3. **Copy and configure the config file**
   ```bash
   cp ddns.conf.example ddns.conf
   ```
   Then edit `ddns.conf`:
   ```bash
   nano ddns.conf
   ```

4. **If needed, update the config path in the script (line 4)**

5. **Make the script executable**
   ```bash
   chmod +x ddns.sh
   ```

6. **(Optional) Restrict permissions**
   ```bash
   chmod 600 ddns.conf
   ```

---

## Verification

Before testing:

- Ensure Porkbun already has DNS records matching each entry in your `ddns.conf`.
- For testing, set them temporarily to a random IP in the Porkbun dashboard.

Then run:

```bash
./ddns.sh
```

Refresh the Porkbun UI and verify that the DNS records have been updated to your current public IP.

---

## Scheduling with Cron

You should run this script automatically every 5 minutes.

1. Find the full path to the script:
   ```bash
   realpath ddns.sh
   ```

2. Edit crontab:
   ```bash
   crontab -e
   ```

3. Add this line (update the path accordingly):
   ```cron
   */5 * * * * /path/to/porkbun-ddns/ddns.sh >/dev/null 2>&1
   ```

This ensures your DNS stays up to date whenever your public IP changes.

---

## Credit

Based originally on the script found here https://github.com/luxeon/porkbun-ddns
