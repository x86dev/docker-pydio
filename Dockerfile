# Pull base image.
FROM kdelfour/supervisor-docker
MAINTAINER Andreas Löffler <andy@x86dev.com>

# Based on: https://github.com/kdelfour/pydio-docker

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y \
    wget nginx fontconfig-config fonts-dejavu-core \
    php5-fpm php5-common php5-json php5-cli php5-common php5-mysql \
    php5-gd php5-json php5-mcrypt php5-readline psmisc ssl-cert \
    ufw php-pear libgd-tools libmcrypt-dev mcrypt mysql-server mysql-client

# Add Pydio as the only Nginx site.
ADD pydio-nginx.conf /etc/nginx/sites-available/pydio
RUN ln -s /etc/nginx/sites-available/pydio /etc/nginx/sites-enabled/pydio
RUN rm /etc/nginx/sites-enabled/default

# Install Pydio.
RUN mkdir -p /var/www
ENV PYDIO_VER 6.0.8
RUN wget -P /tmp http://downloads.sourceforge.net/project/ajaxplorer/pydio/stable-channel/${PYDIO_VER}/pydio-core-${PYDIO_VER}.tar.gz
RUN tar xvzf /tmp/pydio-core-${PYDIO_VER}.tar.gz -C /tmp
RUN mv /tmp/pydio-core-${PYDIO_VER} /var/www/pydio-core

# Expose default database credentials via ENV in order to ease overwriting.
ENV DB_NAME pydio
ENV DB_USER pydio
ENV DB_PASS pydio

# Link volumes to actual directories.
RUN ln -s /var/www/pydio-core/data /pydio-data
RUN ln -s /var/lib/mysql/pydio /pydio-db

# Expose ports.
EXPOSE 80
EXPOSE 443

# Expose volumes.
VOLUME /pydio-data/files
VOLUME /pydio-data/personal
VOLUME /pydio-db

# Always re-configure database with current ENV when RUNning container, then monitor all services.
RUN mkdir -p /srv
ADD setup-pydio.sh            /srv/setup-pydio.sh
ADD update-pydio.sh           /srv/update-pydio.sh
ADD start-pydio.sh            /srv/start-pydio.sh

# Database stuff.
ADD pydio-scheme.mysql        /srv/pydio-scheme.mysql
ADD pydio-bootstrap.json      /srv/pydio-bootstrap.json

RUN mkdir -p /etc/supervisor/conf.d
ADD service-nginx.conf        /etc/supervisor/conf.d/nginx.conf
ADD service-php5-fpm.conf     /etc/supervisor/conf.d/php5-fpm.conf
ADD service-mysql.conf        /etc/supervisor/conf.d/mysql.conf

# Clean up.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Start setting up everything.
WORKDIR /srv
CMD ["/srv/setup-pydio.sh", "--start"]
