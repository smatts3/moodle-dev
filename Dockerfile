FROM php:8.3-apache

# Install basic tools
RUN apt update && apt install git -y

# Import dev source code
WORKDIR /var/www/html
RUN git clone --branch develop --single-branch https://github.com/lsuonline/lsuce-moodle.git .
# RUN wget https://github.com/lsuonline/lsuce-moodle/archive/refs/heads/develop.zip
# COPY ./lsuce-moodle-develop.zip ./
# RUN unzip lsuce-moodle-develop.zip && rm lsuce-moodle-develop.zip && mv lsuce-moodle-develop/* . && rm -rf lsuce-moodle-develop*

# Install dependencies

RUN apt install -y \
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

# Copy over configs

COPY ./config/php.ini /usr/local/etc/php/php.ini
COPY ./config/config.php /var/www/html/config_local.php

# Tweaky stuff

RUN git config --global --add safe.directory /var/www/html && \
    chown -R www-data:www-data /var/www/html && chmod -R 755 /var/www/html && \
    mkdir -p /var/www/moodledata/storage && chown -R www-data:www-data /var/www/moodledata

CMD ["apache2-foreground"]
