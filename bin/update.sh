#!/usr/bin/env bash
#
# Author: Philipp A. Mohrenweiser
# Contact: mailto:phiamo@googlemail.com
# Version: $id$
# 
# update your app
# 

set +e
scriptPath=$(readlink -f "${0%/*}")

. $scriptPath/envvars

APP="app/console"
APACHE_RUN_USER="${APACHE_RUN_USER-www-data}"
APACHE_RUN_GROUP="${APACHE_RUN_GROUP-www-data}"
dirs="${dirs-app/cache app/logs}"
COMPOSER="$(which composer.phar)"
UPDATEPROD=0
WITHDB=0
WITHCOMPOSERUPDATE=1

function usage() {
    cat << EOF
Usage: $(basename $0) <options> -t

This script updates a sf2 environment

OPTIONS:
   -p Update prod env after dev env
   -d With db reset
   -c Skip composer
   -h Show this help
EOF
}

while getopts "hpcd:" OPTION ; do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        p)
            UPDATEPROD=1
            ;;
        c)
            WITHCOMPOSERUPDATE=0
            ;;
        d)
            WITHDB=1
            ;;
        ?)
            usage
            exit 1
            ;;
    esac
done

dirs="${dirs-app/cache app/logs web/media/ web/images/barcode_playground}"

MDBOTHBEFORE="$(md5sum composer.json composer.lock)"

#pre setup
rm -rf web/media/cache/_*
mkdir -p web/media

# update source
git pull

MDBOTHAFTER="$(md5sum composer.json composer.lock)"
if [ $WITHCOMPOSERUPDATE == 1 ]; then
    if [ "$MDBOTHBEFORE" != "$MDBOTHAFTER" ]; then
        $COMPOSER install
    fi 
    $COMPOSER update
fi

if [ $WITHDB = 1 ]; then
    # create db
    $APP doctrine:database:drop --force
    $APP doctrine:database:create
    $APP doctrine:schema:drop --force
    $APP doctrine:schema:create
    $APP init:acl
    $APP doctrine:fixtures:load -v
fi

# dump dev assets
$APP assets:install --symlink web
$APP assetic:dump --env=dev 


if [ $UPDATEPROD = 0 ]; then
    echo "Ok ... Not updating prod env"
    exit 0
fi

echo "RUNNING CHMOD AS $APACHE_RUN_USER:$APACHE_RUN_GROUP on $dirs"

app/console cache:clear --env=prod --no-debug

echo "restarting your webserver:"

if [ -e "/etc/init.d/apache2" ]; then
    sudo /etc/init.d/apache2 restart
elif [ -e "/etc/init.d/nginx" ]; then
    sudo /etc/init.d/nginx restart
    sudo /etc/init.d/php5-fpm restart
elif [ -e "/etc/init.d/lighttpd" ]; then
    sudo /etc/init.d/lighttpd restart
else
    echo "NOT WEBSERVER FOUND!"
fi

app/console assets:install --env=prod web
app/console assetic:dump --env=prod --no-debug
sudo chown $APACHE_RUN_USER.$APACHE_RUN_GROUP -R $dirs
sudo chmod 775 -R $dirs
