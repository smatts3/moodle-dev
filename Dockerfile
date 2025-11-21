FROM php:8.3-apache

# Install basic tools
RUN apt update && apt install git wget unzip -y

# Import dev source code
WORKDIR /var/www/html
RUN su -g www-data -c "git clone --branch develop --single-branch https://github.com/lsuonline/lsuce-moodle.git ."

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
    && a2enmod rewrite

RUN docker-php-ext-install intl mbstring exif xsl soap

RUN pecl install redis && docker-php-ext-enable redis

RUN apt clean

# Tweaky stuff
RUN git config --global --add safe.directory /var/www/html

# Copy over configs
COPY config/php.ini /usr/local/etc/php/php.ini
COPY config/config.php /var/www/html/config.php

# Set permissions
RUN chown www-data:www-data /var/www/html/config.php && \
    chmod 755 /var/www/html/config.php && \
    chown www-data:www-data /usr/local/etc/php/php.ini && \
    chmod 755 /usr/local/etc/php/php.ini && \
    mkdir -p /var/www/moodledata/storage && \ 
    chown -R www-data:www-data /var/www/moodledata

#Install VSCode extensions

CMD ["apache2-foreground"]
