#!/bin/bash

echo "=== LAMP Backup Script ==="
echo "Starting backup: $(date)"

# Configuration
WEB_DIR="/var/www/html"
BACKUP_DIR="/var/backups/lamp"
DATE=$(date +%Y%m%d_%H%M%S)
MYSQL_USER="root"
MYSQL_PASS="Devops_2025"

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo
echo ">>> Step 1: Web Files Backup"
echo "----------------------------------------"

# Check if web directory exists
if [ ! -d "$WEB_DIR" ]; then
    echo "ERROR: Web directory not found"
    exit 1
fi

# Backup web files
WEB_BACKUP="web_$DATE.tar.gz"
echo "Creating web backup: $WEB_BACKUP"

if tar -czf "$BACKUP_DIR/$WEB_BACKUP" -C "$WEB_DIR" . ; then
    WEB_SIZE=$(du -h "$BACKUP_DIR/$WEB_BACKUP" | cut -f1)
    echo "SUCCESS: Web backup created ($WEB_SIZE)"
else
    echo "ERROR: Web backup failed"
    exit 1
fi

echo
echo ">>> Step 2: Database Backup"
echo "----------------------------------------"

# Check MariaDB status
if ! systemctl is-active mariadb > /dev/null; then
    echo "ERROR: MariaDB not running"
    exit 1
fi

# Test database connection
if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT 1;" 2>/dev/null; then
    echo "ERROR: Cannot connect to database with provided credentials"
    exit 1
fi

# Get databases list
DATABASES=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v Database | grep -v information_schema | grep -v performance_schema | grep -v sys)

if [ -z "$DATABASES" ]; then
    echo "No user databases found"
    DB_COUNT=0
else
    echo "Found databases: $DATABASES"
    DB_COUNT=0
    
    # Backup each database
    for db in $DATABASES; do
        DB_BACKUP="${db}_$DATE.sql"
        echo "Backing up database: $db"
        
        if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db" > "$BACKUP_DIR/$DB_BACKUP" 2>/dev/null; then
            gzip "$BACKUP_DIR/$DB_BACKUP"
            DB_SIZE=$(du -h "$BACKUP_DIR/${DB_BACKUP}.gz" | cut -f1)
            echo "SUCCESS: $db backed up ($DB_SIZE)"
            DB_COUNT=$((DB_COUNT + 1))
        else
            echo "ERROR: Failed to backup $db"
        fi
    done
fi

# Backup MySQL users
echo "Backing up MySQL users"
mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User, Host FROM mysql.user;" > "$BACKUP_DIR/mysql_users_$DATE.txt" 2>/dev/null

echo
echo ">>> Step 3: Cleanup Old Backups"
echo "----------------------------------------"

# Remove backups older than 7 days
REMOVED_COUNT=$(find "$BACKUP_DIR" -name "web_*.tar.gz" -mtime +7 -delete -print 2>/dev/null | wc -l)
REMOVED_COUNT=$((REMOVED_COUNT + $(find "$BACKUP_DIR" -name "*_*.sql.gz" -mtime +7 -delete -print 2>/dev/null | wc -l)))
REMOVED_COUNT=$((REMOVED_COUNT + $(find "$BACKUP_DIR" -name "mysql_users_*.txt" -mtime +7 -delete -print 2>/dev/null | wc -l)))

echo "Removed $REMOVED_COUNT old backup files"

echo
echo ">>> Backup Summary"
echo "----------------------------------------"
echo "Backup location: $BACKUP_DIR"
echo "Web backup: $WEB_BACKUP ($WEB_SIZE)"
echo "Databases backed up: $DB_COUNT"
echo "Backup completed: $(date)"

echo
echo "Current backups:"
ls -lht "$BACKUP_DIR" | head -10

echo
echo "Backup completed successfully!"
