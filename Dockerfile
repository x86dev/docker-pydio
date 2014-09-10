# ------------------------------------------------------------------------------
# Based on a work at https://github.com/docker/docker.
# ------------------------------------------------------------------------------
# Pull base image.
FROM dockerfile/supervisor
MAINTAINER Kevin Delfour <kevin@delfour.eu>

# ------------------------------------------------------------------------------
# Install
RUN apt-get update
RUN apt-get install -y wget mysql-server mysql-client
RUN echo "deb http://dl.ajaxplorer.info/repos/apt stable main" >> /etc/apt/sources.list
RUN echo "deb-src http://dl.ajaxplorer.info/repos/apt stable main" >> /etc/apt/sources.list
RUN wget -O - http://dl.ajaxplorer.info/repos/charles@ajaxplorer.info.gpg.key | apt-key add -

# ------------------------------------------------------------------------------
# Install Pydio
RUN apt-get update
RUN apt-get install -y pydio

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
    
# php-fpm config
RUN sed -i -e "s/output_buffering=4096/output_buffering=Off/g" /etc/php5/apache2/php.ini
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/apache2/php.ini
RUN sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 1G/g" /etc/php5/apache2/php.ini
RUN sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 1G/g" /etc/php5/apache2/php.ini

RUN rm /etc/apache2/sites-enabled/000-default.conf 
ADD conf/pydio.conf /etc/apache2/sites-enabled/

RUN apt-get install -y php5-mcrypt php5-mysql
RUN php5enmod mcrypt

VOLUME /usr/share/pydio/data/

# ------------------------------------------------------------------------------
# Expose ports.
EXPOSE 80

# ------------------------------------------------------------------------------
# Add supervisord conf
ADD conf/startup.conf /etc/supervisor/conf.d/

# Start supervisor, define default command.
CMD supervisord -c /etc/supervisor/supervisord.conf