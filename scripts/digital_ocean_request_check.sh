#! /bin/bash
#
curl --request POST \
--data 'name=le%20guin&email=ursula_le_guin%40gmail.com' \
https://zero2prod-qs93j.ondigitalocean.app/subscriptions \
--verbose
