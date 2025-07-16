#!/bin/bash

set -e

WEB_DIR="/var/www/html"
BACKUP_DIR="/var/backups/lamp"
MYSQL_USER="root"
ROOT_PASSWORD=""
RETENTION_DAYS=7
LOG_FILE="/var/log/backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --web-dir PATH        Web directory (default: $WEB_DIR)"
    echo "  -b, --backup-dir PATH     Backup directory (default: $BACKUP_DIR)"
    echo "  -u, --mysql-user USER     MySQL user (default: $MYSQL_USER)"
    echo "  -p, --root-password PASS  MySQL root password"
    echo "  -r, --retention DAYS      Retention days (default: $RETENTION_DAYS)"
    echo "  -l, --log-file PATH       Log file (default: $LOG_FILE)"
    echo "  -h, --help               Show help"
    echo ""
    echo "Environment variables:"
    echo "  MARIADB_ROOT_PASSWORD     MariaDB root password (recommended)"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--web-dir)
                WEB_DIR="$2"
                shift 2
                ;;
            -b|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -u|--mysql-user)
                MYSQL_USER="$2"
                shift 2
                ;;
            -p|--root-password)
                ROOT_PASSWORD="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    if [ -z "$ROOT_PASSWORD" ] && [ -n "$MARIADB_ROOT_PASSWORD" ]; then
        ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD"
    fi
    
    if [ ! -d "$WEB_DIR" ]; then
        log_message "ERROR: Web directory not found: $WEB_DIR"
        exit 1
    fi
    
    if ! command -v mysqldump >/dev/null 2>&1; then
        log_message "ERROR: mysqldump not found"
        exit 1
    fi
    
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        log_message "ERROR: Cannot create backup directory: $BACKUP_DIR"
        exit 1
    fi
    
    if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "ERROR: Cannot create log directory: $(dirname "$LOG_FILE")"
        exit 1
    fi
}

backup_web_files() {
    log_message ">>> Step 1: Web Files Backup"
    log_message "----------------------------------------"
    
    local DATE=$(date +%Y%m%d_%H%M%S)
    local WEB_BACKUP="web_$DATE.tar.gz"
    
    log_message "Creating web backup: $WEB_BACKUP"
    
    if tar -czf "$BACKUP_DIR/$WEB_BACKUP" -C "$WEB_DIR" . ; then
        local WEB_SIZE=$(du -h "$BACKUP_DIR/$WEB_BACKUP" | cut -f1)
        log_message "SUCCESS: Web backup created ($WEB_SIZE)"
        echo "WEB_BACKUP=$WEB_BACKUP" > /tmp/backup_vars
        echo "WEB_SIZE=$WEB_SIZE" >> /tmp/backup_vars
    else
        log_message "ERROR: Web backup failed"
        exit 1
    fi
}

backup_databases() {
    log_message ""
    log_message ">>> Step 2: Database Backup"
    log_message "----------------------------------------"
    
    if ! systemctl is-active mariadb > /dev/null; then
        log_message "ERROR: MariaDB not running"
        exit 1
    fi
    
    local mysql_opts=""
    if [ -n "$ROOT_PASSWORD" ]; then
        mysql_opts="-p$ROOT_PASSWORD"
    fi
    
    if ! mysql -u "$MYSQL_USER" $mysql_opts -e "SELECT 1;" 2>/dev/null; then
        log_message "ERROR: Cannot connect to database"
        exit 1
    fi
    
    local DATABASES=$(mysql -u "$MYSQL_USER" $mysql_opts -e "SHOW DATABASES;" 2>/dev/null | grep -v Database | grep -v information_schema | grep -v performance_schema | grep -v sys)
    local DATE=$(date +%Y%m%d_%H%M%S)
    local DB_COUNT=0
    
    if [ -z "$DATABASES" ]; then
        log_message "No user databases found"
    else
        log_message "Found databases: $DATABASES"
        
        for db in $DATABASES; do
            local DB_BACKUP="${db}_$DATE.sql"
            log_message "Backing up database: $db"
            if mysqldump -u "$MYSQL_USER" $mysql_opts "$db" > "$BACKUP_DIR/$DB_BACKUP" 2>/dev/null; then
                gzip "$BACKUP_DIR/$DB_BACKUP"
                local DB_SIZE=$(du -h "$BACKUP_DIR/${DB_BACKUP}.gz" | cut -f1)
                log_message "SUCCESS: $db backed up ($DB_SIZE)"
                DB_COUNT=$((DB_COUNT + 1))
            else
                log_message "ERROR: Failed to backup $db"
            fi
        done
    fi
    
    log_message "Backing up MySQL users"
    mysql -u "$MYSQL_USER" $mysql_opts -e "SELECT User, Host FROM mysql.user;" > "$BACKUP_DIR/mysql_users_$DATE.txt" 2>/dev/null
    
    echo "DB_COUNT=$DB_COUNT" >> /tmp/backup_vars
}

cleanup_old_backups() {
    log_message ""
    log_message ">>> Step 3: Cleanup Old Backups"
    log_message "----------------------------------------"
    
    local REMOVED_COUNT=$(find "$BACKUP_DIR" -name "web_*.tar.gz" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | wc -l)
    REMOVED_COUNT=$((REMOVED_COUNT + $(find "$BACKUP_DIR" -name "*_*.sql.gz" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | wc -l)))
    REMOVED_COUNT=$((REMOVED_COUNT + $(find "$BACKUP_DIR" -name "mysql_users_*.txt" -mtime +$RETENTION_DAYS -delete -print 2>/dev/null | wc -l)))
    
    log_message "Removed $REMOVED_COUNT old backup files"
}

show_summary() {
    log_message ""
    log_message ">>> Backup Summary"
    log_message "----------------------------------------"
    
    if [ -f /tmp/backup_vars ]; then
        source /tmp/backup_vars
    fi
    
    log_message "Backup location: $BACKUP_DIR"
    [ -n "$WEB_BACKUP" ] && log_message "Web backup: $WEB_BACKUP ($WEB_SIZE)"
    [ -n "$DB_COUNT" ] && log_message "Databases backed up: $DB_COUNT"
    log_message "Backup completed: $(date)"
    log_message ""
    log_message "Current backups:"
    ls -lht "$BACKUP_DIR" | head -10 | while read line; do log_message "$line"; done
    log_message ""
    log_message "Backup completed successfully!"
    
    rm -f /tmp/backup_vars
}

main() {
    log_message "=== LAMP Backup Script ==="
    log_message "Starting backup: $(date)"
    
    parse_arguments "$@"
    check_prerequisites
    mkdir -p "$BACKUP_DIR"
    
    backup_web_files
    backup_databases
    cleanup_old_backups
    show_summary
}

trap 'log_message "ERROR: Script interrupted"; rm -f /tmp/backup_vars; exit 1' INT TERM

main "$@"
