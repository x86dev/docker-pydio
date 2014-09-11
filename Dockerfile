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
    php5-fpm php5-common php5-json php5-cli php5-common php5-mysql\
    php5-gd php5-json php5-mcrypt php5-readline psmisc ssl-cert \
    ufw php-pear libgd-tools libmcrypt-dev mcrypt mysql-server mysql-client

# ------------------------------------------------------------------------------
# Configuration
# mysql config
RUN sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf
RUN service mysql start && \
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS pydio" && \
    mysql -uroot -e "CREATE USER 'pydio'@'%' IDENTIFIED BY 'pydio'" && \
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'pydio'@'%' WITH GRANT OPTION" && \
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'pydio'@'127.0.0.1' WITH GRANT OPTION" && \
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'pydio'@'localhost' WITH GRANT OPTION"
    
# ------------------------------------------------------------------------------
# Configure php-fpm
WORKDIR /etc/php5
RUN ln -s /etc/php5/fpm/php.ini php.ini
RUN sed -i -e "s/output_buffering\s*=\s*4096/output_buffering = Off/g" php.ini
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
RUN chown -R www-data:www-data /var/www/pydio-core-5.3.2
RUN chmod -R 770 /var/www/pydio-core-5.3.2

VOLUME /var/www/pydio-core-5.3.2

RUN update-rc.d nginx defaults
RUN update-rc.d php5-fpm defaults
RUN update-rc.d mysqld defaults
# ------------------------------------------------------------------------------
# Expose ports.
EXPOSE 80
EXPOSE 443

# ------------------------------------------------------------------------------
# Add supervisord conf
ADD conf/php5-nginx.conf /etc/supervisor/conf.d/

# Start supervisor, define default command.
CMD supervisord -c /etc/supervisor/supervisord.conf