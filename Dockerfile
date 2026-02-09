FROM php:8.3-apache

# Install basic tools
RUN apt update && apt install git -y

# Import dev source code
RUN su -g www-data -c "git clone --branch develop --single-branch https://github.com/lsuonline/lsuce-moodle.git /var/www/html/"

# Install dependencies
RUN apt-get install -y --fix-missing \
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
	&& pecl install xdebug \
	&& docker-php-ext-enable xdebug \
	&& apt clean

# Copy over configs
COPY --chown=www-data:www-data config/php.ini /usr/local/etc/php/php.ini

# Tweaky stuff && set permissions
RUN git config --global --add safe.directory /var/www/html && \
	git config pull.ff only && \
	git config pull.rebase true && \
	chown www-data:www-data /usr/local/etc/php/php.ini && \
	chmod 755 /usr/local/etc/php/php.ini && \
	mkdir -p /var/www/moodledata/storage && \ 
	chown -R www-data:www-data /var/www/moodledata && \
	echo 'enrol/workdaystudent/\nblocks/wdsprefs/' >> /var/www/html/.git/info/exclude && \
	git -C /var/www/html ls-files enrol/workdaystudent blocks/wdsprefs | xargs git -C /var/www/html update-index --skip-worktree && \
	rm -rf /var/www/html/enrol/workdaystudent /var/www/html/blocks/wdsprefs && \
	git clone https://github.com/lsuonline/moodle-enrol_workdaystudent.git /var/www/html/enrol/workdaystudent && \
	git clone https://github.com/lsuonline/moodle-block_wdsprefs.git /var/www/html/blocks/wdsprefs && \
	git config --global alias.co checkout && \
	git config --global alias.br branch && \
	git config --global alias.ci commit && \
	git config --global alias.st status && \
	git config --global pull.ff only
#Install VSCode extensions
CMD ["apache2-foreground"]
#http://localhost:63942/admin/index.php?cache=0&agreelicense=1&confirmrelease=1&lang=en
