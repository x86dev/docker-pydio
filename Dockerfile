# ------------------------------------------------------------------------------
# Based on a work at https://github.com/docker/docker.
# ------------------------------------------------------------------------------
# Pull base image.
FROM dockerfile/supervisor
MAINTAINER Kevin Delfour <kevin@delfour.eu>

# ------------------------------------------------------------------------------
# Install Base
RUN apt-get update
RUN apt-get install -yq wget unzip nginx fontconfig-config fonts-dejavu-core \
    php5-fpm php5-common php5-json php5-cli php5-common \
    php5-gd php5-json php5-mcrypt php5-readline psmisc ssl-cert \
    ufw php-pear libgd-tools libmcrypt-dev mcrypt

# ------------------------------------------------------------------------------
# Configure php-fpm
WORKDIR /etc/php5
RUN ln -s /etc/php5/cli/php.ini php.ini
RUN sed -i -e "s/output_buffering = 4096/output_buffering=off/g" php.ini
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" php.ini
RUN sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 1G/g" php.ini
RUN sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 1G/g" php.ini
RUN php5enmod mcrypt

# ------------------------------------------------------------------------------
# Configure nginx
RUN mkdir /var/www
RUN chown www-data:www-data /var/www
RUN rm /etc/nginx/sites-enabled/*
ADD conf/drop.conf /etc/nginx/
ADD conf/php.conf /etc/nginx/
ADD conf/pydio /etc/nginx/sites-enabled/

# ------------------------------------------------------------------------------
# Install Pydio
WORKDIR /var/www
RUN wget http://downloads.sourceforge.net/project/ajaxplorer/pydio/dev-channel/5.3.2/pydio-core-5.3.2.zip
RUN unzip pydio-core-5.3.2.zip
RUN chown -R www-data:www-data /var/www/

VOLUME /var/www/pydio-core-5.3.2

# ------------------------------------------------------------------------------
# Expose ports.
EXPOSE 80
EXPOSE 443

# ------------------------------------------------------------------------------
# Add supervisord conf
ADD conf/php5-fpm.conf /etc/supervisor/conf.d/

# Start supervisor, define default command.
CMD supervisord -c /etc/supervisor/supervisord.conf