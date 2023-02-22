#!/bin/bash

sudo su

# Install or update needed software
apt-get update
apt-get install -yq git supervisor systemctl python3-pip python3-venv nginx vim ufw jq
apt-get install python3 python3-pip python3-dev build-essential libssl-dev libffi-dev python3-setuptools -y

systemctl start nginx
systemctl enable nginx

# Fetch source code
mkdir /opt/apps
git clone https://github.com/RamyaGangadharan/project /opt/apps

# Python environment setup
cd /opt/apps/

python3 -m venv /opt/apps/env
source /opt/apps/env/bin/activate
pip3 install flask
pip3 install gunicorn

deactivate
# Start application
#gunicorn --bind 0.0.0.0:5000 app:app

mv flask.service /etc/systemd/system/flask.service

chown -R root:www-data /opt/apps
chmod -R 775 /opt/apps

systemctl daemon-reload

systemctl start flask
systemctl enable flask

mv flask.conf /etc/nginx/conf.d/flask.conf

systemctl restart nginx


oc delete pod nginx-pod
oc delete svc myapp-ingress
oc delete secret myapp-secret
oc delete routes myapp-route1 myapp-route2