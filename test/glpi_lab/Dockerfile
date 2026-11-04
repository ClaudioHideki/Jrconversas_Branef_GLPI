FROM php:8.3-apache-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libpng-dev libjpeg62-turbo-dev libfreetype6-dev libicu-dev libzip-dev libbz2-dev libonig-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j2 gd intl mysqli zip bz2 mbstring exif opcache \
    && rm -rf /var/lib/apt/lists/*

ADD --checksum=sha256:fe044e021c17ee88e088a8a4392c7807c9a0f397a1a551689d2eb7f668439e96 \
    https://github.com/glpi-project/glpi/releases/download/10.0.18/glpi-10.0.18.tgz /tmp/glpi.tgz
RUN tar -xzf /tmp/glpi.tgz -C /var/www && rm /tmp/glpi.tgz && chown -R www-data:www-data /var/www/glpi \
    && a2enmod rewrite
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY entrypoint.sh /usr/local/bin/branef-glpi-lab
COPY bootstrap.php /usr/local/lib/branef-glpi-bootstrap.php
COPY template_fixtures.php /usr/local/lib/branef-glpi-template-fixtures.php
RUN printf 'memory_limit=256M\nupload_max_filesize=20M\npost_max_size=25M\nmax_execution_time=120\n' > /usr/local/etc/php/conf.d/branef-lab.ini
WORKDIR /var/www/glpi
ENTRYPOINT ["bash", "/usr/local/bin/branef-glpi-lab"]
