#!/bin/bash

###############################################################################
# NetBox Docker Installation Script for openSUSE
# Uses Official NetBox Docker Repository
###############################################################################
#
# CREDENTIALS & PASSWORDS DOCUMENTATION
# ======================================
#
# This script sets up NetBox using the official Docker containers with:
#
# 1. POSTGRES_PASSWORD
#    - Purpose: PostgreSQL database password for NetBox
#    - Used by: NetBox container to connect to PostgreSQL container
#    - Location: Stored in docker-compose.override.yml and .env file
#    - Security: 32 bytes base64-encoded random string (~43 characters)
#
# 2. REDIS_PASSWORD (Optional - Redis in Docker typically doesn't use auth by default)
#    - Purpose: Redis authentication (if enabled)
#    - Used by: NetBox container to connect to Redis container
#    - Note: Official NetBox Docker setup doesn't require Redis password by default
#
# 3. SECRET_KEY
#    - Purpose: Django secret key for cryptographic signing
#    - Used by: NetBox for session management, CSRF protection, etc.
#    - Location: Stored in docker-compose.override.yml and .env file
#    - Security: 48 bytes base64-encoded random string (~64 characters)
#    - WARNING: Changing this will invalidate existing sessions/tokens
#
# 4. SUPERUSER_PASSWORD
#    - Purpose: Initial admin user password for NetBox web interface
#    - Used by: First login to NetBox web interface
#    - Location: Stored in docker-compose.override.yml and .env file
#    - Security: 24 bytes base64-encoded random string (~32 characters)
#
# All credentials are:
# - Generated using OpenSSL's cryptographically secure random generator
# - Saved to /root/netbox_docker_credentials.txt (permissions: 600)
# - Stored in environment variables in docker-compose.override.yml
# - Can be modified in the .env file before starting containers
#
###############################################################################

set -e  # Exit on any error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Configuration
NETBOX_DOCKER_PATH="/opt/netbox-docker"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   NetBox Docker Installation Script   ║${NC}"
echo -e "${GREEN}║   For openSUSE (Fresh Installation)   ║${NC}"
echo -e "${GREEN}║   Using Official NetBox Docker        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}            PASSWORD CONFIGURATION${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Please configure passwords for your NetBox installation."
echo -e "You can enter custom passwords or press ENTER to auto-generate."
echo ""

# PostgreSQL Password
echo -e "${BLUE}[1/4] PostgreSQL Database Password${NC}"
echo -e "Used by NetBox to connect to the database"
read -p "Enter password (or press ENTER to auto-generate): " POSTGRES_PASSWORD
if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    echo -e "${GREEN}✓ Auto-generated PostgreSQL password${NC}"
else
    echo -e "${GREEN}✓ Using custom PostgreSQL password${NC}"
fi
echo ""

# Django Secret Key
echo -e "${BLUE}[2/4] Django Secret Key${NC}"
echo -e "Used for cryptographic signing (sessions, CSRF tokens, etc.)"
echo -e "${YELLOW}⚠ WARNING: Never change this after initial setup!${NC}"
read -p "Enter secret key (or press ENTER to auto-generate): " SECRET_KEY
if [ -z "$SECRET_KEY" ]; then
    SECRET_KEY=$(openssl rand -base64 48)
    echo -e "${GREEN}✓ Auto-generated secret key${NC}"
else
    echo -e "${GREEN}✓ Using custom secret key${NC}"
fi
echo ""

# Superuser Password
echo -e "${BLUE}[3/4] Admin/Superuser Password${NC}"
echo -e "Password for logging into NetBox web interface"
echo -e "Username will be: ${GREEN}admin${NC}"
read -s -p "Enter admin password (or press ENTER to auto-generate): " SUPERUSER_PASSWORD
echo ""
if [ -z "$SUPERUSER_PASSWORD" ]; then
    SUPERUSER_PASSWORD=$(openssl rand -base64 24)
    echo -e "${GREEN}✓ Auto-generated admin password${NC}"
else
    echo -e "${GREEN}✓ Using custom admin password${NC}"
fi
echo ""

# Superuser API Token
echo -e "${BLUE}[4/4] API Token${NC}"
echo -e "Token for API authentication"
read -p "Enter API token (or press ENTER to auto-generate): " SUPERUSER_API_TOKEN
if [ -z "$SUPERUSER_API_TOKEN" ]; then
    SUPERUSER_API_TOKEN=$(openssl rand -hex 40)
    echo -e "${GREEN}✓ Auto-generated API token${NC}"
else
    echo -e "${GREEN}✓ Using custom API token${NC}"
fi
echo ""

# Fixed superuser details
SUPERUSER_NAME="admin"
SUPERUSER_EMAIL="admin@example.com"

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Password configuration complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
sleep 2

echo -e "${YELLOW}[1/6] Updating system packages...${NC}"
zypper refresh
zypper update -y

echo -e "${YELLOW}[2/6] Installing Docker and Docker Compose...${NC}"

# Install Docker
zypper install -y docker docker-compose git

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify Docker installation
docker --version
docker-compose --version

echo -e "${GREEN}✓ Docker and Docker Compose installed${NC}"

echo -e "${YELLOW}[3/6] Downloading official NetBox Docker repository...${NC}"

# Clone the official NetBox Docker repository
cd /opt
if [ -d "$NETBOX_DOCKER_PATH" ]; then
    echo -e "${YELLOW}NetBox Docker directory already exists, removing...${NC}"
    rm -rf "$NETBOX_DOCKER_PATH"
fi

git clone https://github.com/netbox-community/netbox-docker.git netbox-docker
cd "$NETBOX_DOCKER_PATH"

echo -e "${GREEN}✓ NetBox Docker repository cloned${NC}"

echo -e "${YELLOW}[4/6] Configuring NetBox Docker environment...${NC}"

# Create docker-compose.override.yml with custom configuration
cat > docker-compose.override.yml <<EOF
version: '3.4'
services:
  netbox:
    ports:
      - "80:8080"  # Expose NetBox on port 80
    environment:
      # Database configuration
      DB_PASSWORD: '$POSTGRES_PASSWORD'
      
      # Secret key for Django
      SECRET_KEY: '$SECRET_KEY'
      
      # Superuser configuration (will be created automatically)
      SUPERUSER_NAME: '$SUPERUSER_NAME'
      SUPERUSER_EMAIL: '$SUPERUSER_EMAIL'
      SUPERUSER_PASSWORD: '$SUPERUSER_PASSWORD'
      SUPERUSER_API_TOKEN: '$SUPERUSER_API_TOKEN'
      
      # Skip the startup scripts that require user interaction
      SKIP_STARTUP_SCRIPTS: 'false'
      
  postgres:
    environment:
      POSTGRES_PASSWORD: '$POSTGRES_PASSWORD'
    volumes:
      - netbox-postgres-data:/var/lib/postgresql/data

  redis:
    volumes:
      - netbox-redis-data:/data

  redis-cache:
    volumes:
      - netbox-redis-cache-data:/data

volumes:
  netbox-postgres-data:
    driver: local
  netbox-redis-data:
    driver: local
  netbox-redis-cache-data:
    driver: local
EOF

# Also create a .env file for easier manual configuration
cat > .env <<EOF
# NetBox Docker Environment Configuration
# ========================================
# Generated on: $(date)

# PostgreSQL Database Password
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Django Secret Key (DO NOT CHANGE after initial setup!)
SECRET_KEY=$SECRET_KEY

# Superuser Credentials (for initial login)
SUPERUSER_NAME=$SUPERUSER_NAME
SUPERUSER_EMAIL=$SUPERUSER_EMAIL
SUPERUSER_PASSWORD=$SUPERUSER_PASSWORD
SUPERUSER_API_TOKEN=$SUPERUSER_API_TOKEN

# You can modify these values before starting the containers
# After modifying, run: docker-compose up -d
EOF

chmod 600 .env docker-compose.override.yml

echo -e "${GREEN}✓ NetBox Docker configured${NC}"

echo -e "${YELLOW}[5/6] Pulling Docker images and starting NetBox...${NC}"
echo -e "${BLUE}This may take several minutes on first run...${NC}"

# Pull all required images
docker-compose pull

# Start all containers in detached mode
docker-compose up -d

echo -e "${GREEN}✓ Docker containers started${NC}"

echo -e "${YELLOW}[6/6] Waiting for NetBox to be ready...${NC}"
echo -e "${BLUE}Waiting for database initialization and migrations...${NC}"

# Wait for NetBox to be healthy
RETRIES=0
MAX_RETRIES=60
until docker-compose exec -T netbox /bin/bash -c "curl -f http://localhost:8080/login/ > /dev/null 2>&1"; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -eq $MAX_RETRIES ]; then
        echo -e "${RED}NetBox failed to start within expected time${NC}"
        echo -e "${YELLOW}Check logs with: docker-compose logs${NC}"
        exit 1
    fi
    echo -e "${BLUE}Waiting for NetBox... ($RETRIES/$MAX_RETRIES)${NC}"
    sleep 5
done

echo -e "${GREEN}✓ NetBox is ready!${NC}"

# Open firewall for HTTP if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo -e "${YELLOW}Opening firewall for HTTP...${NC}"
    firewall-cmd --permanent --add-service=http
    firewall-cmd --reload
    echo -e "${GREEN}✓ Firewall configured${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            NetBox Docker Installation Complete!           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}NetBox is now running at:${NC} ${BLUE}http://localhost${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SUPERUSER LOGIN CREDENTIALS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "Username: ${GREEN}$SUPERUSER_NAME${NC}"
echo -e "Password: ${GREEN}$SUPERUSER_PASSWORD${NC}"
echo -e "Email:    ${GREEN}$SUPERUSER_EMAIL${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}DATABASE CREDENTIALS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "PostgreSQL Password: ${GREEN}$POSTGRES_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}SECURITY KEYS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "Secret Key:      ${GREEN}$SECRET_KEY${NC}"
echo -e "API Token:       ${GREEN}$SUPERUSER_API_TOKEN${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}IMPORTANT INFORMATION${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Installation Directory: ${GREEN}$NETBOX_DOCKER_PATH${NC}"
echo -e "Configuration Files:"
echo -e "  - ${GREEN}$NETBOX_DOCKER_PATH/docker-compose.override.yml${NC}"
echo -e "  - ${GREEN}$NETBOX_DOCKER_PATH/.env${NC}"
echo ""
echo -e "Credentials saved to: ${GREEN}/root/netbox_docker_credentials.txt${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}DOCKER COMMANDS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "View running containers:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose ps${NC}"
echo ""
echo -e "View logs:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose logs -f netbox${NC}"
echo ""
echo -e "Stop NetBox:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose stop${NC}"
echo ""
echo -e "Start NetBox:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose start${NC}"
echo ""
echo -e "Restart NetBox:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose restart${NC}"
echo ""
echo -e "Update NetBox to latest version:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose pull && docker-compose up -d${NC}"
echo ""
echo -e "Execute commands in NetBox container:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose exec netbox /bin/bash${NC}"
echo ""
echo -e "Backup database:"
echo -e "  ${GREEN}cd $NETBOX_DOCKER_PATH && docker-compose exec -T postgres pg_dump -U netbox netbox > backup.sql${NC}"
echo ""
echo -e "${RED}⚠ IMPORTANT: Save the credentials above in a secure location!${NC}"
echo ""

# Save credentials to file with comprehensive documentation
cat > /root/netbox_docker_credentials.txt <<EOF
╔════════════════════════════════════════════════════════════════════════╗
║              NetBox Docker Installation Credentials                   ║
║                         KEEP THIS FILE SECURE!                         ║
╚════════════════════════════════════════════════════════════════════════╝

Installation Date: $(date)
Installation Path: $NETBOX_DOCKER_PATH
NetBox URL: http://localhost

═══════════════════════════════════════════════════════════════════════════
1. WEB INTERFACE LOGIN (SUPERUSER)
═══════════════════════════════════════════════════════════════════════════

Purpose: Initial administrator account for NetBox web interface
URL: http://localhost

Username: $SUPERUSER_NAME
Password: $SUPERUSER_PASSWORD
Email:    $SUPERUSER_EMAIL

⚠️  IMPORTANT: Change this password after first login!
   Go to: User Menu → Profile → Change Password


═══════════════════════════════════════════════════════════════════════════
2. API TOKEN (SUPERUSER)
═══════════════════════════════════════════════════════════════════════════

Purpose: API authentication for programmatic access
Used by: Scripts, automation tools, API clients

API Token: $SUPERUSER_API_TOKEN

Usage Example:
  curl -H "Authorization: Token $SUPERUSER_API_TOKEN" \\
       http://localhost/api/

To create additional tokens:
  Web UI → User Menu → Profile → API Tokens


═══════════════════════════════════════════════════════════════════════════
3. POSTGRESQL DATABASE
═══════════════════════════════════════════════════════════════════════════

Purpose: NetBox uses PostgreSQL as its primary database
Container: postgres

Database Name: netbox
Username:      netbox
Password:      $POSTGRES_PASSWORD
Port:          5432 (internal to Docker network)

Connection String:
  postgresql://netbox:$POSTGRES_PASSWORD@postgres:5432/netbox

To connect from host:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec postgres psql -U netbox

To backup database:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec -T postgres pg_dump -U netbox netbox > backup.sql

To restore database:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec -T postgres psql -U netbox netbox < backup.sql


═══════════════════════════════════════════════════════════════════════════
4. DJANGO SECRET KEY
═══════════════════════════════════════════════════════════════════════════

Purpose: Django framework uses this for cryptographic operations
Used by: Session management, CSRF protection, password reset tokens

Secret Key: $SECRET_KEY

⚠️  CRITICAL WARNING: Never change this key after initial setup!
    Changing it will invalidate:
    - All user sessions (users will be logged out)
    - Password reset tokens
    - Any cryptographically signed data

Storage Locations:
  - $NETBOX_DOCKER_PATH/docker-compose.override.yml
  - $NETBOX_DOCKER_PATH/.env


═══════════════════════════════════════════════════════════════════════════
5. REDIS (CACHE & QUEUE)
═══════════════════════════════════════════════════════════════════════════

Purpose: Redis is used for caching and background task queuing
Containers: redis (tasks/queue) and redis-cache (caching)

Note: The official NetBox Docker setup does not use Redis authentication
      by default. Redis is only accessible within the Docker network.

Redis Containers:
  - redis:        Background task queue (port 6379)
  - redis-cache:  Application caching (port 6379)

To connect to Redis:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec redis redis-cli
  docker-compose exec redis-cache redis-cli


═══════════════════════════════════════════════════════════════════════════
DOCKER CONTAINERS
═══════════════════════════════════════════════════════════════════════════

Running Containers:
  - netbox:        Main NetBox application
  - netbox-worker: Background task worker
  - postgres:      PostgreSQL database
  - redis:         Redis task queue
  - redis-cache:   Redis caching

To view all containers:
  cd $NETBOX_DOCKER_PATH
  docker-compose ps

To view logs:
  docker-compose logs -f netbox         # NetBox application logs
  docker-compose logs -f postgres       # Database logs
  docker-compose logs -f netbox-worker  # Background worker logs


═══════════════════════════════════════════════════════════════════════════
CONFIGURATION FILES
═══════════════════════════════════════════════════════════════════════════

Main Configuration:
  $NETBOX_DOCKER_PATH/docker-compose.yml
  - Base Docker Compose configuration (DO NOT EDIT)

Custom Configuration:
  $NETBOX_DOCKER_PATH/docker-compose.override.yml
  - Your custom settings and credentials
  - Edit this file to change configuration

Environment Variables:
  $NETBOX_DOCKER_PATH/.env
  - Environment variables for easy configuration
  - Edit credentials here, then restart: docker-compose up -d

NetBox Configuration:
  Mounted in container at: /etc/netbox/config/
  Can be customized by creating: $NETBOX_DOCKER_PATH/configuration/


═══════════════════════════════════════════════════════════════════════════
DATA PERSISTENCE
═══════════════════════════════════════════════════════════════════════════

All data is stored in Docker volumes:

PostgreSQL Data:
  Volume: netbox-postgres-data
  Location: /var/lib/docker/volumes/netbox-docker_netbox-postgres-data

Redis Data:
  Volume: netbox-redis-data
  Location: /var/lib/docker/volumes/netbox-docker_netbox-redis-data

Redis Cache:
  Volume: netbox-redis-cache-data
  Location: /var/lib/docker/volumes/netbox-docker_netbox-redis-cache-data

Media Files:
  Volume: netbox-docker_netbox-media-files
  Location: User-uploaded files

To backup volumes:
  docker run --rm -v netbox-postgres-data:/data -v /backup:/backup \\
    alpine tar czf /backup/postgres-backup.tar.gz -C /data .


═══════════════════════════════════════════════════════════════════════════
COMMON OPERATIONS
═══════════════════════════════════════════════════════════════════════════

Start NetBox:
  cd $NETBOX_DOCKER_PATH
  docker-compose up -d

Stop NetBox:
  cd $NETBOX_DOCKER_PATH
  docker-compose stop

Restart NetBox:
  cd $NETBOX_DOCKER_PATH
  docker-compose restart

View logs:
  cd $NETBOX_DOCKER_PATH
  docker-compose logs -f

Update to latest version:
  cd $NETBOX_DOCKER_PATH
  docker-compose pull
  docker-compose up -d

Access NetBox shell:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec netbox python manage.py shell

Run database migrations:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec netbox python manage.py migrate

Create additional superuser:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec netbox python manage.py createsuperuser

Collect static files:
  cd $NETBOX_DOCKER_PATH
  docker-compose exec netbox python manage.py collectstatic --no-input


═══════════════════════════════════════════════════════════════════════════
SECURITY RECOMMENDATIONS
═══════════════════════════════════════════════════════════════════════════

✓ Change the default admin password after first login
✓ Keep this credentials file secure (permissions: 600)
✓ Backup credentials to encrypted storage
✓ Regular backups of PostgreSQL database
✓ Keep Docker and NetBox images updated
✓ Monitor logs for suspicious activity
✓ Use firewall rules to restrict access
✓ Consider setting up HTTPS with reverse proxy (nginx/traefik)
✓ Regularly review user accounts and permissions
✓ Enable two-factor authentication in NetBox


═══════════════════════════════════════════════════════════════════════════
BACKUP STRATEGY
═══════════════════════════════════════════════════════════════════════════

Regular Backup Script Example:
  #!/bin/bash
  BACKUP_DIR=/backup/netbox/\$(date +%Y%m%d)
  mkdir -p \$BACKUP_DIR
  
  cd $NETBOX_DOCKER_PATH
  
  # Backup database
  docker-compose exec -T postgres pg_dump -U netbox netbox > \\
    \$BACKUP_DIR/database.sql
  
  # Backup Docker volumes
  docker run --rm \\
    -v netbox-postgres-data:/data \\
    -v \$BACKUP_DIR:/backup \\
    alpine tar czf /backup/postgres-volume.tar.gz -C /data .
  
  # Backup configuration
  cp docker-compose.override.yml \$BACKUP_DIR/
  cp .env \$BACKUP_DIR/

Schedule with cron:
  0 2 * * * /path/to/backup-script.sh


═══════════════════════════════════════════════════════════════════════════
TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════════════

NetBox won't start:
  1. Check logs: docker-compose logs netbox
  2. Verify all containers running: docker-compose ps
  3. Check Docker daemon: systemctl status docker
  4. Verify port 80 is not in use: netstat -tlnp | grep :80

Can't login:
  1. Verify credentials in this file
  2. Reset password: 
     docker-compose exec netbox python manage.py changepassword admin
  3. Check NetBox logs: docker-compose logs netbox

Database connection errors:
  1. Verify postgres container is running: docker-compose ps postgres
  2. Check postgres logs: docker-compose logs postgres
  3. Verify password in docker-compose.override.yml

Performance issues:
  1. Check container resources: docker stats
  2. Increase worker count in docker-compose.override.yml
  3. Check Redis status: docker-compose exec redis redis-cli PING


═══════════════════════════════════════════════════════════════════════════
USEFUL LINKS
═══════════════════════════════════════════════════════════════════════════

NetBox Documentation:      https://docs.netbox.dev/
NetBox Docker GitHub:      https://github.com/netbox-community/netbox-docker
NetBox Community:          https://github.com/netbox-community/netbox/discussions
Docker Documentation:      https://docs.docker.com/
Docker Compose Reference:  https://docs.docker.com/compose/


═══════════════════════════════════════════════════════════════════════════
End of NetBox Docker Credentials File
═══════════════════════════════════════════════════════════════════════════
EOF

chmod 600 /root/netbox_docker_credentials.txt

echo -e "${GREEN}Credentials saved to: /root/netbox_docker_credentials.txt${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Installation complete! Access NetBox at http://localhost${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
