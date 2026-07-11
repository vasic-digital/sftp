🚀 Production-Ready SFTP Server with Docker/Podman Compose

This project provides a fully deployable SFTP server using the official atmoz/sftp Docker image. It runs on custom port 7721 (or any 77XX port), exposes the service to your entire network, and includes simple management for users, directories, and permissions. All configuration is done via plain-text files – no rebuilding required.

---

📁 Project Structure

```
sftp-server/
├── docker-compose.yml    # Compose definition (Docker & Podman compatible)
├── .env                  # Environment variables (port, etc.)
├── users.conf            # User list (add/remove users here)
├── sshd_config           # (Optional) Custom SSH daemon settings
├── data/                 # Host directory for all user data (auto-created)
│   ├── alice/            # User 'alice' home (auto-created on first upload)
│   └── bob/              # User 'bob' home
└── README.md             # This guide (you can omit, but we include full docs)
```

---

🛠 Prerequisites

· Docker or Podman with podman-compose installed.
· A cloud server (Ubuntu/Debian recommended) with port 7721 open in the firewall and cloud security group.
· Basic knowledge of Linux file permissions.

---

📄 File Contents

docker-compose.yml

```yaml
version: '3.8'

services:
  sftp:
    image: atmoz/sftp:latest
    container_name: sftp_production
    ports:
      - "${SFTP_PORT:-7721}:22"          # Map host port 7721 → container port 22
    volumes:
      - ./data:/sftp_data                # All user data stored here
      - ./users.conf:/etc/sftp/users.conf:ro   # Read‑only user list
      # - ./sshd_config:/etc/ssh/sshd_config:ro  # Uncomment to use custom SSH config
    environment:
      - SFTP_USERS_FILE=/etc/sftp/users.conf   # Tell atmoz/sftp where to find users
    restart: unless-stopped
    # For podman, you may need to add: 
    #   - "--userns=keep-id" under `podman run` flags, but Compose handles it.
```

.env

```env
# Choose any port starting with 77XX (e.g., 7721, 7701, 7799)
SFTP_PORT=7721
```

users.conf

Format: user:password:uid:gid:home_directory[:options]
One user per line.
Replace passwords with strong ones (or later use SSH keys).

```
alice:MyS3cur3P@ss!:1000:1000:/sftp_data/alice
bob:An0th3rP@ssw0rd:1001:1001:/sftp_data/bob
```

💡 Tip: The home_directory must be a path inside the container. Since we mount ./data to /sftp_data, each user’s home should be /sftp_data/username. This keeps all data under the host’s ./data/ folder.

(Optional) sshd_config

If you want to tighten security (e.g., disable password login, force SFTP only), create a custom sshd_config and uncomment the volume mount in docker-compose.yml. Below is a hardened example:

```
Port 22
Protocol 2

# Disable root login
PermitRootLogin no

# Use internal SFTP subsystem
Subsystem sftp internal-sftp

# Only allow SFTP for all users (no shell)
Match Group sftp
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    PermitTTY no
    X11Forwarding no
    PasswordAuthentication yes   # Change to "no" after setting up keys
```

---

🚀 Step‑by‑Step Deployment

1. Create the project directory and files

```bash
mkdir ~/sftp-server && cd ~/sftp-server
```

Copy the above file contents into their respective files using nano or vim.

2. Prepare the data directory

```bash
mkdir -p data
```

3. Set correct ownership for user directories (important!)

For each user, you must ensure the host directory is owned by the same UID/GID as defined in users.conf. This allows the container user to read/write files.

```bash
# Create subdirectories (they will be automatically created when users upload, but we create them manually to set permissions)
mkdir -p data/alice data/bob

# Change ownership to match UID/GID (replace 1000:1000 etc.)
sudo chown 1000:1000 data/alice
sudo chown 1001:1001 data/bob

# Set secure permissions (755 for directories, 644 for files – will be applied automatically)
```

⚠️ Important: The UID/GID must exist in the container. If your host doesn’t have a user with that UID, chown will accept numeric IDs anyway. The container will use the same numeric IDs.

4. Start the container

Using Docker:

```bash
docker-compose up -d
```

Using Podman (with podman-compose):

```bash
podman-compose up -d
```

Check logs:

```bash
docker-compose logs -f   # or podman-compose logs -f
```

You should see that the users are created successfully.

5. Open firewall port on the cloud server

For Ubuntu/Debian (UFW):

```bash
sudo ufw allow 7721/tcp
sudo ufw reload
```

For CentOS/RHEL (firewalld):

```bash
sudo firewall-cmd --permanent --add-port=7721/tcp
sudo firewall-cmd --reload
```

Also update your cloud provider’s security group (AWS, GCP, Azure, etc.) – allow inbound TCP on port 7721 from 0.0.0.0/0 (or restrict to your IPs).

---

🧪 Testing the SFTP Connection

From any machine with an SFTP client:

```bash
sftp -P 7721 alice@<your-server-ip>
```

Enter the password from users.conf. You should be dropped into the /sftp_data/alice directory. Try uploading a file:

```bash
sftp> put test.txt
```

The file appears in ./data/alice/ on the host.

---

👥 User Management

Add a new user

1. Edit users.conf and add a new line.
2. Create the user’s home directory on the host:
   ```bash
   mkdir -p data/newuser
   sudo chown <uid>:<gid> data/newuser
   ```
3. Restart the container:
   ```bash
   docker-compose restart
   ```
   (The container will read the updated users.conf.)

Remove a user

1. Delete the line from users.conf.
2. Optionally delete the data directory: rm -rf data/username.
3. Restart the container.

Change a user’s password

1. Edit the password in users.conf.
2. Restart the container.

🔒 Security Note: Passwords are stored in plain text in users.conf. For production, consider using SSH keys (see below) to eliminate passwords entirely.

---

🔑 Enabling SSH Key Authentication (Recommended)

1. For each user, create an .ssh directory inside their home with an authorized_keys file:
   ```bash
   mkdir -p data/alice/.ssh
   echo "ssh-rsa AAAAB3..." > data/alice/.ssh/authorized_keys
   sudo chown -R 1000:1000 data/alice/.ssh
   chmod 700 data/alice/.ssh
   chmod 600 data/alice/.ssh/authorized_keys
   ```
2. In users.conf, you can remove the password (set it to *) or keep it, but you can also disable password authentication globally by setting PasswordAuthentication no in sshd_config (and uncomment the volume mount).
3. Connect using key:
   ```bash
   sftp -P 7721 -i ~/.ssh/private_key alice@<server-ip>
   ```

---

📂 Mapping Additional Host Directories

If you need to expose a shared folder (e.g., /mnt/backup) to all users, you can mount it as a separate volume in docker-compose.yml:

```yaml
volumes:
  - ./data:/sftp_data
  - /mnt/backup:/sftp_data/shared   # mount host dir into container
```

Then each user can access /sftp_data/shared (permissions will depend on UID/GID – you may need to set chmod 777 or adjust ownership).

To give a specific user access to a separate external directory, mount that directory directly to their home:

```yaml
volumes:
  - ./data:/sftp_data
  - /external/disk:/sftp_data/alice   # override alice's home
```

But then you must adjust the user’s home in users.conf to /sftp_data/alice (or the mounted path) – be careful with overlays.

---

🔐 Security Hardening (Production Checklist)

· Use SSH keys only – disable password authentication.
· Restrict IPs – add ALLOWED_IPS or use firewall rules.
· Limit login attempts – install fail2ban and configure it for port 7721.
· Run container as non‑root – atmoz/sftp already drops privileges.
· Keep container updated – use :latest or pin to a known tag.
· Disable shell access – our config ensures ForceCommand internal-sftp.
· Monitor logs – docker-compose logs -f and integrate with a SIEM.

---

🛑 Stopping & Cleaning Up

```bash
docker-compose down     # stops and removes container (data remains)
docker-compose down -v  # also removes anonymous volumes (none here)
```

---

❓ Troubleshooting

Permission denied when uploading

· Check that the host directory has the correct UID/GID ownership (run ls -n data/ to see numeric owners).
· Ensure the home directory exists and is owned by the user.

Container fails to start

· Check logs: docker-compose logs.
· Verify users.conf syntax – each line must have exactly the required fields.
· Make sure the port 7721 is not already in use.

Cannot connect from remote

· Verify firewall (UFW/firewalld/cloud security group).
· Test locally first: sftp -P 7721 alice@localhost.
· Ensure your server’s public IP is correct.

---

📚 Summary

You now have a production‑ready SFTP server that:

· Runs on a custom port (7721).
· Supports multiple users with isolated home directories.
· Stores data persistently on the host (easy backups).
· Allows easy user management by editing users.conf.
· Can be extended with SSH keys and advanced security.

All files are provided – just copy, configure, and run. Enjoy your secure file transfer service!

