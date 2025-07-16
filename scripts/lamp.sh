#!/bin/bash

set -e

WEB_DIR="/var/www/html"
ROOT_PASSWORD=""
CREATE_TEST_FILE="yes"
SECURE_MARIADB="yes"
SKIP_UPDATE="no"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --web-dir PATH        Web directory (default: $WEB_DIR)"
    echo "  -p, --root-password PASS  MariaDB root password"
    echo "  -s, --skip-update         Skip system update"
    echo "  -t, --no-test-file        Don't create PHP test file"
    echo "  -n, --no-secure           Don't secure MariaDB"
    echo "  -h, --help                Show help"
    echo ""
    echo "Environment variables:"
    echo "  MARIADB_ROOT_PASSWORD     (recommended)"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--web-dir)
                WEB_DIR="$2"
                shift 2
                ;;
            -p|--root-password)
                ROOT_PASSWORD="$2"
                shift 2
                ;;
            -s|--skip-update)
                SKIP_UPDATE="yes"
                shift
                ;;
            -t|--no-test-file)
                CREATE_TEST_FILE="no"
                shift
                ;;
            -n|--no-secure)
                SECURE_MARIADB="no"
                shift
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
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Use sudo"
        exit 1
    fi
    
    if [ -z "$ROOT_PASSWORD" ] && [ -n "$MARIADB_ROOT_PASSWORD" ]; then
        ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD"
    fi
    
    if [ -z "$ROOT_PASSWORD" ]; then
        ROOT_PASSWORD="SecureLAMP$(date +%s)!"
    fi
}

show_step() {
    echo ""
    echo ">>> $1"
    echo "----------------------------------------"
}

update_system() {
    if [ "$SKIP_UPDATE" = "yes" ]; then
        return 0
    fi
    
    show_step "STEP 1: Updating system"
    
    if apt update && apt upgrade -y; then
        echo "System updated successfully"
    else
        echo "ERROR: System update failed"
        exit 1
    fi
}

install_apache() {
    show_step "STEP 2: Installing Apache"
    
    if apt install apache2 -y; then
        systemctl enable apache2
        systemctl start apache2
        
        if systemctl is-active apache2 > /dev/null; then
            echo "Apache is running"
        else
            echo "WARNING: Apache may not be running"
        fi
    else
        echo "ERROR: Apache installation failed"
        exit 1
    fi
}

install_mariadb() {
    show_step "STEP 3: Installing MariaDB"
    
    if apt install mariadb-server mariadb-client -y; then
        systemctl enable mariadb
        systemctl start mariadb
        
        if systemctl is-active mariadb > /dev/null; then
            echo "MariaDB is running"
        else
            echo "ERROR: MariaDB failed to start"
            exit 1
        fi
    else
        echo "ERROR: MariaDB installation failed"
        exit 1
    fi
}

install_php() {
    show_step "STEP 4: Installing PHP"
    
    if apt install php libapache2-mod-php php-mysql -y; then
        echo "PHP installed successfully"
        echo "PHP version: $(php -v | head -n1 | cut -d' ' -f2)"
    else
        echo "ERROR: PHP installation failed"
        exit 1
    fi
}

configure_apache_php() {
    show_step "STEP 5: Configuring Apache for PHP"
    
    if [ -f /etc/apache2/mods-enabled/dir.conf ]; then
        cp /etc/apache2/mods-enabled/dir.conf /etc/apache2/mods-enabled/dir.conf.backup 2>/dev/null || true
        sed -i 's/DirectoryIndex index.html/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf
        systemctl restart apache2
        echo "Apache configured for PHP"
    else
        echo "WARNING: dir.conf not found"
    fi
}

create_test_file() {
    if [ "$CREATE_TEST_FILE" = "no" ]; then
        return 0
    fi
    
    show_step "STEP 6: Creating test file"
    
    mkdir -p "$WEB_DIR"
    echo "<?php phpinfo(); ?>" > "$WEB_DIR/info.php"
    echo "Test file created: info.php"
    echo "WARNING: Remove info.php after test for security"
}

secure_mariadb() {
    if [ "$SECURE_MARIADB" = "no" ]; then
        return 0
    fi
    
    show_step "STEP 7: Securing MariaDB"
    
    local CONNECTION_METHOD=""
    if mysql -e "SELECT 1;" 2>/dev/null; then
        CONNECTION_METHOD="mysql"
    elif sudo mysql -e "SELECT 1;" 2>/dev/null; then
        CONNECTION_METHOD="sudo mysql"
    elif mysql -u root -p"$ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null; then
        CONNECTION_METHOD="mysql -u root -p$ROOT_PASSWORD"
    else
        CONNECTION_METHOD="none"
    fi
    
    if [ "$CONNECTION_METHOD" != "none" ]; then
        cat > /tmp/secure_mysql.sql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        
        if [ "$CONNECTION_METHOD" = "mysql" ]; then
            mysql < /tmp/secure_mysql.sql 2>/dev/null
        elif [ "$CONNECTION_METHOD" = "sudo mysql" ]; then
            sudo mysql < /tmp/secure_mysql.sql 2>/dev/null
        else
            eval "$CONNECTION_METHOD" < /tmp/secure_mysql.sql 2>/dev/null
        fi
        
        rm -f /tmp/secure_mysql.sql
        echo "MariaDB secured"
    else
        echo "WARNING: Could not secure MariaDB - check manually"
    fi
}

setup_permissions() {
    show_step "STEP 8: Setting permissions"
    
    mkdir -p "$WEB_DIR"
    chown -R www-data:www-data "$WEB_DIR"
    chmod -R 755 "$WEB_DIR"
    echo "Permissions set"
}

show_completion_summary() {
    show_step "Installation Complete"
    
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo "LAMP Stack ready!"
    echo ""
    echo "Web server: http://$SERVER_IP/"
    
    if [ "$CREATE_TEST_FILE" = "yes" ]; then
        echo "PHP test: http://$SERVER_IP/info.php"
        echo "Remove test file: rm $WEB_DIR/info.php"
    fi
    
    if [ "$SECURE_MARIADB" = "yes" ]; then
        echo "MariaDB root password: $ROOT_PASSWORD"
        echo "Save this password securely"
    fi
    
    echo ""
    echo "Installation completed successfully!"
}

main() {
    echo "=== LAMP Stack Installation ==="
    echo ""
    
    parse_arguments "$@"
    check_prerequisites
    
    update_system
    install_apache
    install_mariadb
    install_php
    configure_apache_php
    create_test_file
    secure_mariadb
    setup_permissions
    show_completion_summary
}

trap 'echo "ERROR: Installation interrupted"; rm -f /tmp/secure_mysql.sql; exit 1' INT TERM

main "$@"
