#!/usr/bin/env bash

set -eou pipefail

# This name should be unique, e.g, 'my-name-zsfd342'
# Use lowercase letters, numbers and hyphens (-)
NAME=''

if [[ $NAME == '' ]]; then
  echo "Please edit the NAME variable in the script"
  exit 1
fi

LOCATION='westeurope'
RESOURCE_GROUP_NAME="$NAME-rg"
STORAGE_ACCOUNT_NAME="${NAME//-/}" # remove all '-'
APPLICATION_INSIGHT_NAME="$NAME-ai"
FUNCTION_APP_NAME="$NAME-funcapp"
KEYVAULT_NAME="$NAME-kv"
COMPUTER_VISION_NAME="$NAME-cv"
SPEECH_SERVICE_NAME="$NAME-speech"

# create resource group
az group create \
  --name "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION"

# create storage account for function app
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --sku "Standard_LRS" \
  --allow-blob-public-access "false" \
  --https-only "true" \
  --min-tls-version "TLS1_2"

# setup static website
az storage blob service-properties update \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --static-website \
  --404-document 404.html --index-document index.html

# install app insights extension
az extension add \
  --name "application-insights"

# create app insights
az monitor app-insights component create \
  --app "$APPLICATION_INSIGHT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --application-type "web"

# create function app
az functionapp create \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --consumption-plan-location "$LOCATION" \
  --storage-account "$STORAGE_ACCOUNT_NAME" \
  --app-insights "$APPLICATION_INSIGHT_NAME" \
  --assign-identity '[system]' \
  --functions-version "3" \
  --os-type "Linux" \
  --runtime "python" \
  --runtime-version "3.8"

# add keyvault
az keyvault create \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION"

# give function app access to keyvault keys
funcapp_object_id=$( \
  az functionapp identity show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query 'principalId' \
    --output tsv \
)

az keyvault set-policy \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --object-id "$funcapp_object_id" \
  --secret-permissions get list

# set CORS rules for functionapp
az functionapp cors remove \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --allowed-origins

az functionapp cors add \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --allowed-origins "*" # '*' is generally not very secure, but works for a demo

# add computer vision
az cognitiveservices account create \
  --kind "ComputerVision" \
  --name "$COMPUTER_VISION_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --sku "F0"

# get computer vision key
computer_vision_key=$( \
  az cognitiveservices account keys list \
    --name "$COMPUTER_VISION_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query 'key1' \
    --output tsv \
)

# ... and put the key in the keyvault
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "computer-vision-access-key" \
  --description "ComputerVision access key" \
  --value "$computer_vision_key"

# add speech
az cognitiveservices account create \
  --kind "SpeechServices" \
  --name "$SPEECH_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --sku "F0"

# get speech key
speech_service_key=$( \
  az cognitiveservices account keys list \
    --name "$SPEECH_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query 'key1' \
    --output tsv \
)

# ... and put the key in the keyvault
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "speech-service-access-key" \
  --description "SpeechService access key" \
  --value "$speech_service_key"

# set app settings
computer_vision_endpoint=$(\
  az cognitiveservices account show \
    --name "$COMPUTER_VISION_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.endpoint" \
    --output tsv \
)

# '@Microsoft.KeyVault(...)' syntax is used to read secrets from keyvault as appsettings
appsettings=(
  "ComputerVisionEndpoint=$computer_vision_endpoint"
  "ComputerVisionAccountKey=@Microsoft.KeyVault(VaultName=$KEYVAULT_NAME;SecretName=computer-vision-access-key)"
  "SpeechKey=@Microsoft.KeyVault(VaultName=$KEYVAULT_NAME;SecretName=speech-service-access-key)"
  "SpeechLocation=$LOCATION"
)

az functionapp config appsettings set \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --settings "${appsettings[@]}"

# deploy the code to function app
(cd src && func azure functionapp publish "$FUNCTION_APP_NAME")

# deploy static assets to storage account
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --source ./src/static/ \
  --destination '$web'
