# prod: docker build --target prod ; dev adds xdebug (never in prod image)
ARG PHP_VERSION=8.4
FROM serversideup/php:${PHP_VERSION}-fpm-nginx AS prod
USER root
RUN install-php-extensions gd intl exif sockets mysqli
USER www-data

FROM prod AS dev
USER root
RUN install-php-extensions xdebug
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN docker-php-serversideup-set-id www-data $USER_ID:$GROUP_ID \
    && docker-php-serversideup-set-file-permissions --owner $USER_ID:$GROUP_ID
USER www-data
