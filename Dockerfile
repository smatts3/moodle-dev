FROM php:8.3-apache

# Install basic tools
RUN apt update && apt install git -y

# Import dev source code
RUN su -g www-data -c "git clone --branch develop --single-branch https://github.com/lsuonline/lsuce-moodle.git /var/www/html/"

# Install dependencies
RUN apt-get install -y \
		libpng-dev \
		libonig-dev \
		libjpeg-dev \
		libfreetype6-dev \
		libzip-dev \
		libicu-dev \
		libxml2-dev \
		mariadb-client \
		libxslt-dev \
		zip \
		unzip \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
	&& docker-php-ext-install -j$(nproc) gd mysqli pdo_mysql zip intl xml opcache \
	&& a2enmod rewrite \
	&& docker-php-ext-install intl mbstring exif xsl soap \
	&& pecl install redis \
	&& docker-php-ext-enable redis \
	&& apt clean

# Copy over configs
COPY --chown=www-data:www-data config/php.ini /usr/local/etc/php/php.ini
COPY --chown=www-data:www-data config/config.php /var/www/html/config.php
# COPY --chmod=0777 config/install.sh /install.sh

# Tweaky stuff && set permissions
RUN git config --global --add safe.directory /var/www/html && \
chown www-data:www-data /var/www/html/config.php && \
	chmod 755 /var/www/html/config.php && \
	chown www-data:www-data /usr/local/etc/php/php.ini && \
	chmod 755 /usr/local/etc/php/php.ini && \
	mkdir -p /var/www/moodledata/storage && \ 
	chown -R www-data:www-data /var/www/moodledata

#Install VSCode extensions
CMD ["apache2-foreground"]
#http://localhost:63942/admin/index.php?cache=0&agreelicense=1&confirmrelease=1&lang=en
