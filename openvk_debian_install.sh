#!/bin/bash
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Not running as root"
    exit
fi

INITIAL_PWD=$(pwd)
## Satisfying dependencies
cd /tmp

echo -e "\n\e[32mRunning apt update...\e[0m"
apt update

echo -e "\n\e[32mInstalling Curl...\e[0m"
apt install -y curl

# Installing Node Repo
echo -e "\n\e[32mInstalling Node Repo...\e[0m"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -

# Installing Yarn repo
echo -e "\n\e[32mInstalling Yarn repo...\e[0m"
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list

echo -e "\n\e[32mRunning apt update...\e[0m"
apt update
# Install everything
echo -e "\n\e[32mInstalling Installing most of dependencies...\e[0m"
apt install -y php7.4-{bz2,cli,curl,fpm,gd,json,mbstring,mysql,opcache,readline,xml,zip} php-yaml nginx mariadb-server nodejs yarn ffmpeg git unzip expect

# Install Composer
echo -e "'\n\e[32mInstalling Composer...\e[0m"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
rm composer-setup.php
mv composer.phar /usr/local/bin/composer


SQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc a-zA-Z0-9 | fold -w 16 | head -n 1)

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Switch to unix_socket authentication\"
send \"n\r\"
expect \"Change the root password?\"
send \"y\r\"
expect \"New password:\"
send \"$SQL_ROOT_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$SQL_ROOT_PASSWORD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"

## Installing phpMyAdmin
echo -e "\n\e[32mInstalling phpMyAdmin at /opt/phpmyadmin...\e[0m"
cd /opt
yes | composer create-project phpmyadmin/phpmyadmin
chown -R www-data: phpmyadmin/
#PMA may require additional config


## Installing OpenVK
echo -e "\n\e[32mInstalling Chandler with OpenVK at /opt/chandler...\e[0m"
OPENVK_DB_PASSWORD=$(cat /dev/urandom | tr -dc a-zA-Z0-9 | fold -w 16 | head -n 1)
git clone https://github.com/openvk/chandler.git
cd chandler
yes | composer install
echo "chandler:
    debug: true
    websiteUrl: null
    rootApp:    \"openvk\"
    
    preferences:
        appendExtension: \"xhtml\"
        adminUrl: \"/chandlerd\"
        exposeChandler: true
    
    extensions:
        path: null
        allEnabled: false
    
    database:
        dsn: \"mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=openvk\"
        user: \"openvk\"
        password: \"${OPENVK_DB_PASSWORD}\"
    
    security:
        secret: \"$(cat /dev/random | tr -dc 'a-z0-9' | fold -w 128 | head -n 1)\"
        csrfProtection: \"permissive\"
        extendedValidation: false
        sessionDuration: 14" > chandler.yml
cd extensions/available
git clone https://github.com/openvk/commitcaptcha.git
cd commitcaptcha/
yes | composer install

cd ..
git clone --recursive https://github.com/openvk/openvk.git
cd openvk/
yes | composer install
cd Web/static/js
yarn install
cd ../../..
echo "openvk:
    debug: true
    appearance:
        name: \"OpenVK\"
        motd: \"Yet another OpenVK instance\"
    
    preferences:
        femaleGenderPriority: true
        uploads:
            disableLargeUploads: false
            mode: \"basic\"
        shortcodes:
            minLength: 3 # won't affect existing short urls or the ones set via admin panel
            forbiddenNames:
                - \"index.php\"
        security:
            requireEmail: false
            requirePhone: false
            forcePhoneVerification: false
            forceEmailVerification: false
            enableSu: true
            rateLimits:
                actions: 5
                time: 20
                maxViolations: 50
                maxViolationsAge: 120
                autoban: true
        registration:
            enable: true
            reason: \"\" # reason for disabling registration
        support:
            supportName: \"Moderator\"
            adminAccount: 1 # Change this ok
            fastAnswers:
                - \"This is a list of quick answers to common questions for support. Post your responses here and agents can send it quickly with just 3 clicks\"
                - \"There can be as many answers as you want, but it is best to have a maximum of 10.\\n\\nYou can also remove all answers from the list to disable this feature\"
                - \"Good luck filling! If you are a regular support agent, inform the administrator that he forgot to fill the config\"
        messages:
            strict: false
        wall:
            christian: false
            anonymousPosting:
                enable: false
                account: 100
            postSizes:
                maxSize: 60000
                processingLimit: 3000
                emojiProcessingLimit: 1000
        commerce: false
        menu:
            links:
                - name: \"@left_menu_donate\"
                  url: \"/donate\"
        adPoster:
            enable: false
            src: \"https://example.org/ad_poster.jpeg\"
            caption: \"Ad caption\"
            link: \"https://example.org/product.aspx?id=10&from=ovk\"
        bellsAndWhistles:
            fartscroll: false
            testLabel: false
    
    telemetry:
        plausible:
            enable: false
            domain: \"\"
            server: \"\"
    
    credentials:
        smsc:
            enable: false
            client: \"\"
            secret: \"SECRET_KEY_HERE\"
        telegram:
            enable: false
            token: \"TOKEN_HERE\"
            helpdeskChat: \"\"
        eventDB:
            enable: false # Better enable this
            database:
                dsn: \"mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=openvk_eventdb\"
                user: \"openvk\"
                password: \"${OPENVK_DB_PASSWORD}\"
        notificationsBroker:
            enable: false
            kafka:
                addr: \"127.0.0.1\"
                port: 9092
                topic: \"OvkEvents\"" > openvk.yml

ln -s /opt/chandler/extensions/available/commitcaptcha/ /opt/chandler/extensions/enabled/commitcaptcha
ln -s /opt/chandler/extensions/available/openvk/ /opt/chandler/extensions/enabled/openvk
cd /opt
chown -R www-data: chandler/


echo -e "\n\e[32mCreating openvk user and creating openvk and openvk_eventdb databases...\e[0m"
mysql -u root -p$SQL_ROOT_PASSWORD -Be "CREATE USER 'openvk'@'localhost' IDENTIFIED BY '${OPENVK_DB_PASSWORD}';CREATE DATABASE openvk;GRANT ALL PRIVILEGES ON openvk.* TO 'openvk'@'localhost';CREATE DATABASE openvk_eventdb;GRANT ALL PRIVILEGES ON openvk_eventdb.* TO 'openvk'@'localhost';FLUSH PRIVILEGES;"
echo -e "\n\e[32mInstalling databases...\e[0m"
mysql -u root -p$SQL_ROOT_PASSWORD openvk < /opt/chandler/install/init-db.sql
mysql -u root -p$SQL_ROOT_PASSWORD openvk < /opt/chandler/extensions/enabled/openvk/install/init-static-db.sql
cd /opt/chandler/extensions/enabled/openvk/install/sqls
for i in * 
do
    if test -f "$i" 
    then
       mysql -u root -p$SQL_ROOT_PASSWORD openvk < $i
    fi
done

mysql -u root -p$SQL_ROOT_PASSWORD openvk_eventdb < /opt/chandler/extensions/enabled/openvk/install/init-event-db.sql


## NGINX Configuration
echo -e "\n\e[32mSwitching default nginx site off...\e[0m"
rm /etc/nginx/sites-enabled/default
echo -e "\n\e[32mCreating phpMyAdmin nginx config at \e[97mlocalhost:8080\e[0m"
echo "server {
	listen 8080 default_server;
	listen [::]:8080 default_server;

	# SSL configuration
	#
	# listen 443 ssl default_server;
	# listen [::]:443 ssl default_server;
	#
	# Note: You should disable gzip for SSL traffic.
	# See: https://bugs.debian.org/773332
	#
	# Read up on ssl_ciphers to ensure a secure configuration.
	# See: https://bugs.debian.org/765782
	#
	# Self signed certs generated by the ssl-cert package
	# Don't use them in a production server!
	#
	# include snippets/snakeoil.conf;

	root /opt/phpmyadmin;

	index index.php;

	server_name _;

	location / {
		try_files \$uri \$uri/ =404;
	}

	# pass PHP scripts to FastCGI server
	
	location ~ \.php$ {
		include snippets/fastcgi-php.conf;
	
		# With php-fpm (or other unix sockets):
		fastcgi_pass unix:/run/php/php7.4-fpm.sock;
	}

	# deny access to .htaccess files, if Apache's document root
	# concurs with nginx's one
	
	location ~ /\.ht {
		deny all;
	}
}" > /etc/nginx/sites-available/001-phpmyadmin
ln -s /etc/nginx/sites-available/001-phpmyadmin /etc/nginx/sites-enabled/001-phpmyadmin

echo -e "\n\e[32mCreating OpenVK nginx config at \e[97mlocalhost:80\e[0m"
echo "server {
	listen 80 default_server;
	listen [::]:80 default_server;

	# SSL configuration
	#
	# listen 443 ssl default_server;
	# listen [::]:443 ssl default_server;
	#
	# Note: You should disable gzip for SSL traffic.
	# See: https://bugs.debian.org/773332
	#
	# Read up on ssl_ciphers to ensure a secure configuration.
	# See: https://bugs.debian.org/765782
	#
	# Self signed certs generated by the ssl-cert package
	# Don't use them in a production server!
	#
	# include snippets/snakeoil.conf;

	root /opt/chandler/htdocs;

    client_max_body_size 100m;

	index index.php;

	server_name _;

	location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    # DO NOT DELETE \"(?!well-known).*\" if you want to use let's encrypt.
    location ~ /\.(?!well-known).* {
        deny all;
        access_log off;
        log_not_found off;
    }

	# pass PHP scripts to FastCGI server
	
	location ~ \index.php$ {
		include snippets/fastcgi-php.conf;
	
		# With php-fpm (or other unix sockets):
		fastcgi_pass unix:/run/php/php7.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	}
}" > /etc/nginx/sites-available/002-openvk
ln -s /etc/nginx/sites-available/002-openvk /etc/nginx/sites-enabled/002-openvk

echo -e "\n\e[32mRestarting NGINX...\e[0m"
sudo systemctl reload nginx
cd $INITIAL_PWD

echo -e "\n\n\e[32mDone! \e[0m"
echo -e "\e[32m\e[97mphpMyAdmin\e[32m is installed at \e[97mlocalhost:8080\e[0m"
echo -e "\e[32m\e[97mOpenVK\e[32m is installed at \e[97mlocalhost:80\e[0m"
echo -e "\e[31mphpMyAdmin may require further configuration (creating config file at http://localhost:8080/setup) but it's working now at least\e[0m"
echo -e "\e[32mSQL \e[97mroot\e[32m user password: \e[97m${SQL_ROOT_PASSWORD}\e[0m"
echo -e "\e[32mSQL \e[97mopenvk\e[32m user password: \e[97m${OPENVK_DB_PASSWORD}\e[0m"
echo -e "\e[32mPlease, save them in your password manager.\e[0m"
