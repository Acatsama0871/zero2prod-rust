#!/bin/bash

curl "https://api.postmarkapp.com/email" \
-X POST \
-H "Accept: application/json" \
-H "Content-Type: application/json" \
-H "X-Postmark-Server-Token: 76e2937e-c521-46f8-b10b-2e20f4b02cb5" \
-d '{
"From": "no-reply@haohang.io",
"To": "dev@haohang.io",
"Subject": "Postmark test",
"TextBody": "Hello dear Postmark user.",
"HtmlBody": "<html><body><strong>Hello</strong> dear Postmark user.</body></html>"
}'
