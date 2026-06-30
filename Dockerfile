FROM php:8.3-apache

# Install basic tools
RUN apt update && apt install git -y

# Import dev source code. lsuonline/moodleus is private; the token comes in via
# a BuildKit secret (id=github_token). docker-compose.yml maps it from the
# GITHUB_TOKEN env var; build.sh passes --secret id=github_token,env=GITHUB_TOKEN.
# Both entry points use submodulizer-local/lib-github-token.sh to populate
# GITHUB_TOKEN. The token is consumed via `git -c url...insteadOf`, so neither
# the token nor the username persist in image layers or /var/www/html/.git/config.
# Falls back to an anonymous clone when no secret is provided (useful for testing
# against any future public mirror; fails for the real private repo).
RUN --mount=type=secret,id=github_token \
    su -g www-data -c 'URL=https://github.com/lsuonline/moodleus.git; \
        if [ -s /run/secrets/github_token ]; then \
            TOKEN=$(cat /run/secrets/github_token); \
            git -c "url.https://smatts3%40lsu.edu:${TOKEN}@github.com/.insteadOf=https://github.com/" \
                clone --branch MOODLE_405_MAIN --single-branch "$URL" /var/www/html/; \
        else \
            git clone --branch MOODLE_405_MAIN --single-branch "$URL" /var/www/html/; \
        fi'

# Install dependencies. `apt-get update` must run in the same layer as install:
# the base image ships a cached apt index that pins -security package versions
# Debian removes over time (e.g. libpng1.6 .deb 404s on stale indexes).
RUN apt-get update && apt-get install -y --fix-missing \
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
		jq \
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
COPY config/moodle-pull /usr/local/bin/moodle-pull

# Tweaky stuff && set permissions
RUN chmod +x /usr/local/bin/moodle-pull && \
	git config --global --add safe.directory /var/www/html && \
	git config pull.ff only && \
	git config pull.rebase true && \
	chown www-data:www-data /usr/local/etc/php/php.ini && \
	chmod 755 /usr/local/etc/php/php.ini && \
	mkdir -p /var/www/moodledata/storage && \ 
	chown -R www-data:www-data /var/www/moodledata && \
	echo 'blocks/ues_people/' >> /var/www/html/.git/info/exclude && \
	git -C /var/www/html config --add safe.directory /var/www/html && \
	git -C /var/www/html ls-files blocks/ues_people | xargs -r git -C /var/www/html update-index --skip-worktree && \
	rm -rf /var/www/html/blocks/ues_people && \
	chown -R www-data:www-data /var/www/html && \
	git config --global alias.co checkout && \
	git config --global alias.br branch && \
	git config --global alias.ci commit && \
	git config --global alias.st status && \
	git config --global pull.ff only
#Install VSCode extensions
CMD ["apache2-foreground"]
#http://localhost:63942/admin/index.php?cache=0&agreelicense=1&confirmrelease=1&lang=en
