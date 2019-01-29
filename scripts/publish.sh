#!/usr/bin/env bash


REPO="form3tech-oss/terraform-bundler"
WORK_DIR="$(git rev-parse --show-toplevel)"
BUNDLE_FILE_NAME="$(ls $WORK_DIR/output/*.zip)"
BUNDLE_SHA=$(shasum -a256 $BUNDLE_FILE_NAME| awk '{print $1}')
BUNDLE_VERSION=$(echo $BUNDLE_FILE_NAME | cut -d '_' -f 2 )

ENV_FILE=$(cat .env)
BODY=${ENV_FILE//$'\n'/<br />}
BODY="SHA=$BUNDLE_SHA<br />$BODY"

# Publish Github Release
echo "Publishing Github Release $BUNDLE_VERSION"

payload=$(cat  << EOF
{
    "tag_name": "$BUNDLE_VERSION",
    "name": "$BUNDLE_VERSION",
    "body": "$BODY",
    "draft": false
}
EOF
)

response=$(
  curl --data "$payload" \
       "https://api.github.com/repos/$REPO/releases?access_token=$GITHUB_TOKEN"
)

upload_url="$(echo "$response" | jq -r .upload_url | sed -e "s/{?name,label}//")"

response=$(
    curl --header "Content-Type:application/octet-stream" \
         --data-binary "@$BUNDLE_FILE_NAME" \
         "$upload_url?name=$(basename "$BUNDLE_FILE_NAME")&access_token=$GITHUB_TOKEN"
)
BUNDLE_DOWNLOAD_URL="$(echo "$response" | jq -r .browser_download_url)"

# Install bundle in TFE
echo "Installing Bundle $BUNDLE_VERSION on TFE with file $BUNDLE_DOWNLOAD_URL"

payload=$(cat  << EOF
{
    "data": {
        "type": "terraform-versions",
        "attributes": {
          "version": "$BUNDLE_VERSION",
          "url": "$BUNDLE_DOWNLOAD_URL",
          "sha": "$BUNDLE_SHA",
          "official": false,
          "enabled": true,
          "beta": false
        }
    }
}
EOF
)

curl \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data "$payload" \
  $TFE_ADDRESS/api/v2/admin/terraform-versions