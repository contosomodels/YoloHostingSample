#!/bin/bash

# =============================================================================
# YoloX Model Deployment Script
# Downloads model files from HuggingFace and uploads them to Azure Blob Storage
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
STORAGE_ACCOUNT=""
CONTAINER_NAME="models"
PUBLISHER="YourOrganization"

# Model definitions
declare -A MODELS
MODELS["qnn-npu"]="https://huggingface.co/qualcomm/Yolo-X/resolve/f7d92bb30d876f4c7dd485b4d30776583b8fbae4/Yolo-X_w8a8.onnx.zip?download=true|Yolo-X_w8a8.onnx|QNNExecutionProvider|zip"
MODELS["vitis-ai"]="https://huggingface.co/amd/yolox-s/resolve/7c14fb63e32a65d92d173b2119790442f6b2bfc7/yolox-s-int8.onnx?download=true|yolox-s-int8.onnx|VitisAIExecutionProvider|onnx"
MODELS["cpu"]="https://huggingface.co/qualcomm/Yolo-X/resolve/f7d92bb30d876f4c7dd485b4d30776583b8fbae4/Yolo-X_float.onnx.zip?download=true|Yolo-X_float.onnx|CPUExecutionProvider|zip"

# Function to display usage
usage() {
    echo "Usage: $0 -g <resource-group> -s <storage-account> [-c <container>] [-p <publisher>]"
    echo ""
    echo "Options:"
    echo "  -g    Azure Resource Group name (required)"
    echo "  -s    Azure Storage Account name (required)"
    echo "  -c    Blob container name (default: models)"
    echo "  -p    Publisher name for catalog (default: YourOrganization)"
    echo "  -h    Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "g:s:c:p:h" opt; do
    case $opt in
        g) RESOURCE_GROUP="$OPTARG" ;;
        s) STORAGE_ACCOUNT="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        p) PUBLISHER="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ] || [ -z "$STORAGE_ACCOUNT" ]; then
    echo -e "${RED}Error: Resource group and storage account are required.${NC}"
    usage
fi

echo -e "${GREEN}=== YoloX Model Deployment Script ===${NC}"
echo "Resource Group: $RESOURCE_GROUP"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}Using temp directory: $TEMP_DIR${NC}"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up temp directory...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Get storage account key
echo -e "${YELLOW}Getting storage account key...${NC}"
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT" \
    --query "[0].value" -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    echo -e "${RED}Error: Could not retrieve storage account key.${NC}"
    exit 1
fi

# Initialize catalog
CATALOG_FILE="$TEMP_DIR/catalog.json"
echo '{"models":[]}' > "$CATALOG_FILE"

# Process each model
for model_key in "${!MODELS[@]}"; do
    IFS='|' read -r url filename ep filetype <<< "${MODELS[$model_key]}"
    
    echo ""
    echo -e "${GREEN}Processing model: $model_key${NC}"
    echo "  URL: $url"
    echo "  Filename: $filename"
    echo "  Execution Provider: $ep"
    echo "  File Type: $filetype"
    
    # Download the file
    echo -e "${YELLOW}  Downloading...${NC}"
    if [ "$filetype" == "zip" ]; then
        DOWNLOAD_FILE="$TEMP_DIR/${filename%.onnx}.zip"
    else
        DOWNLOAD_FILE="$TEMP_DIR/$filename"
    fi
    
    curl -L -o "$DOWNLOAD_FILE" "$url" --progress-bar
    
    # Extract if ZIP
    UPLOAD_FILE="$TEMP_DIR/$filename"
    if [ "$filetype" == "zip" ]; then
        echo -e "${YELLOW}  Extracting ZIP archive...${NC}"
        unzip -o "$DOWNLOAD_FILE" -d "$TEMP_DIR"
        
        # Find the .onnx file in extracted contents
        EXTRACTED_ONNX=$(find "$TEMP_DIR" -name "*.onnx" -type f | head -1)
        if [ -n "$EXTRACTED_ONNX" ] && [ "$EXTRACTED_ONNX" != "$UPLOAD_FILE" ]; then
            mv "$EXTRACTED_ONNX" "$UPLOAD_FILE"
        fi
        
        rm -f "$DOWNLOAD_FILE"
    fi
    
    # Verify file exists
    if [ ! -f "$UPLOAD_FILE" ]; then
        echo -e "${RED}  Error: Could not find $filename after extraction.${NC}"
        continue
    fi
    
    # Get file size
    FILE_SIZE=$(stat -f%z "$UPLOAD_FILE" 2>/dev/null || stat -c%s "$UPLOAD_FILE" 2>/dev/null)
    echo -e "${YELLOW}  File size: $FILE_SIZE bytes${NC}"
    
    # Upload to Azure Blob Storage
    echo -e "${YELLOW}  Uploading to Azure Blob Storage...${NC}"
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER_NAME" \
        --name "$filename" \
        --file "$UPLOAD_FILE" \
        --content-type "application/octet-stream" \
        --overwrite
    
    echo -e "${GREEN}  ✓ Upload complete${NC}"
    
    # Add to catalog
    MODEL_ENTRY=$(cat <<EOF
{
    "id": "yolox-$model_key",
    "name": "YoloX",
    "version": "1.0.0",
    "publisher": "$PUBLISHER",
    "executionProviders": [{"name": "$ep"}],
    "license": "MIT",
    "files": [{"name": "$filename", "url": "/$CONTAINER_NAME/$filename", "size": $FILE_SIZE}]
}
EOF
)
    
    # Update catalog JSON
    jq --argjson model "$MODEL_ENTRY" '.models += [$model]' "$CATALOG_FILE" > "$CATALOG_FILE.tmp"
    mv "$CATALOG_FILE.tmp" "$CATALOG_FILE"
done

# Add metadata to catalog
FINAL_CATALOG=$(jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg pub "$PUBLISHER" \
    '. + {"generatedAt": $ts, "publisher": $pub, "version": "1.0.0"}' "$CATALOG_FILE")
echo "$FINAL_CATALOG" > "$CATALOG_FILE"

# Upload catalog
echo ""
echo -e "${YELLOW}Uploading model catalog...${NC}"
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --container-name "$CONTAINER_NAME" \
    --name "catalog.json" \
    --file "$CATALOG_FILE" \
    --content-type "application/json" \
    --overwrite

echo -e "${GREEN}✓ Catalog uploaded${NC}"

# Get CDN endpoint
echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Storage Blob URL:"
echo "  https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME/catalog.json"
echo ""
echo "Model files uploaded:"
for model_key in "${!MODELS[@]}"; do
    IFS='|' read -r url filename ep filetype <<< "${MODELS[$model_key]}"
    echo "  - $filename ($ep)"
done
echo ""
echo -e "${YELLOW}Note: If using CDN, allow a few minutes for propagation.${NC}"
