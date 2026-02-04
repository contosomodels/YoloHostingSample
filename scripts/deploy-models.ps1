<#
.SYNOPSIS
    YoloX Model Deployment Script for Azure Blob Storage

.DESCRIPTION
    Downloads YoloX model files from HuggingFace and uploads them to Azure Blob Storage.
    Creates a model catalog JSON file for client applications.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group containing the storage account.

.PARAMETER StorageAccountName
    The name of the Azure Storage Account to upload models to.

.PARAMETER ContainerName
    The name of the blob container (default: models).

.PARAMETER Publisher
    The publisher name for the model catalog (default: YourOrganization).

.EXAMPLE
    .\deploy-models.ps1 -ResourceGroupName "my-rg" -StorageAccountName "mystorageaccount"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "models",

    [Parameter(Mandatory = $false)]
    [string]$Publisher = "YourOrganization"
)

$ErrorActionPreference = "Stop"

# Model definitions
$Models = @{
    "qnn-npu" = @{
        Url = "https://huggingface.co/qualcomm/Yolo-X/resolve/f7d92bb30d876f4c7dd485b4d30776583b8fbae4/Yolo-X_w8a8.onnx.zip?download=true"
        Filename = "Yolo-X_w8a8.onnx"
        ExecutionProvider = "QNNExecutionProvider"
        IsZip = $true
    }
    "vitis-ai" = @{
        Url = "https://huggingface.co/amd/yolox-s/resolve/7c14fb63e32a65d92d173b2119790442f6b2bfc7/yolox-s-int8.onnx?download=true"
        Filename = "yolox-s-int8.onnx"
        ExecutionProvider = "VitisAIExecutionProvider"
        IsZip = $false
    }
    "cpu" = @{
        Url = "https://huggingface.co/qualcomm/Yolo-X/resolve/f7d92bb30d876f4c7dd485b4d30776583b8fbae4/Yolo-X_float.onnx.zip?download=true"
        Filename = "Yolo-X_float.onnx"
        ExecutionProvider = "CPUExecutionProvider"
        IsZip = $true
    }
}

Write-Host "=== YoloX Model Deployment Script ===" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Storage Account: $StorageAccountName"
Write-Host "Container: $ContainerName"
Write-Host ""

# Create temp directory
$TempDir = Join-Path $env:TEMP "yolox-deploy-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Using temp directory: $TempDir" -ForegroundColor Yellow

try {
    # Get storage account context
    Write-Host "Getting storage account context..." -ForegroundColor Yellow
    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    $Context = $StorageAccount.Context

    # Ensure container exists
    $Container = Get-AzStorageContainer -Name $ContainerName -Context $Context -ErrorAction SilentlyContinue
    if (-not $Container) {
        Write-Host "Creating container: $ContainerName" -ForegroundColor Yellow
        New-AzStorageContainer -Name $ContainerName -Context $Context -Permission Blob | Out-Null
    }

    # Initialize catalog
    $Catalog = @{
        models = @()
        generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        publisher = $Publisher
        version = "1.0.0"
    }

    # Process each model
    foreach ($ModelKey in $Models.Keys) {
        $Model = $Models[$ModelKey]
        
        Write-Host ""
        Write-Host "Processing model: $ModelKey" -ForegroundColor Green
        Write-Host "  URL: $($Model.Url)"
        Write-Host "  Filename: $($Model.Filename)"
        Write-Host "  Execution Provider: $($Model.ExecutionProvider)"

        # Determine download path
        if ($Model.IsZip) {
            $DownloadPath = Join-Path $TempDir "$($Model.Filename -replace '\.onnx$', '.zip')"
        } else {
            $DownloadPath = Join-Path $TempDir $Model.Filename
        }

        # Download the file
        Write-Host "  Downloading..." -ForegroundColor Yellow
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Model.Url -OutFile $DownloadPath -UseBasicParsing
        $ProgressPreference = 'Continue'

        # Extract if ZIP
        $UploadPath = Join-Path $TempDir $Model.Filename
        if ($Model.IsZip) {
            Write-Host "  Extracting ZIP archive..." -ForegroundColor Yellow
            $ExtractDir = Join-Path $TempDir "extract-$ModelKey"
            Expand-Archive -Path $DownloadPath -DestinationPath $ExtractDir -Force
            
            # Find the .onnx file
            $OnnxFile = Get-ChildItem -Path $ExtractDir -Filter "*.onnx" -Recurse | Select-Object -First 1
            if ($OnnxFile) {
                Copy-Item -Path $OnnxFile.FullName -Destination $UploadPath -Force
            }
            
            Remove-Item -Path $DownloadPath -Force
            Remove-Item -Path $ExtractDir -Recurse -Force
        }

        # Verify file exists
        if (-not (Test-Path $UploadPath)) {
            Write-Host "  Error: Could not find $($Model.Filename) after extraction." -ForegroundColor Red
            continue
        }

        # Get file size
        $FileSize = (Get-Item $UploadPath).Length
        Write-Host "  File size: $FileSize bytes" -ForegroundColor Yellow

        # Upload to Azure Blob Storage
        Write-Host "  Uploading to Azure Blob Storage..." -ForegroundColor Yellow
        Set-AzStorageBlobContent `
            -File $UploadPath `
            -Container $ContainerName `
            -Blob $Model.Filename `
            -Context $Context `
            -Properties @{ ContentType = "application/octet-stream" } `
            -Force | Out-Null

        Write-Host "  ✓ Upload complete" -ForegroundColor Green

        # Add to catalog
        $CatalogEntry = @{
            id = "yolox-$ModelKey"
            name = "YoloX"
            version = "1.0.0"
            publisher = $Publisher
            executionProviders = @(
                @{ name = $Model.ExecutionProvider }
            )
            license = "MIT"
            files = @(
                @{
                    name = $Model.Filename
                    url = "/$ContainerName/$($Model.Filename)"
                    size = $FileSize
                }
            )
        }
        $Catalog.models += $CatalogEntry
    }

    # Save and upload catalog
    $CatalogPath = Join-Path $TempDir "catalog.json"
    $Catalog | ConvertTo-Json -Depth 10 | Set-Content -Path $CatalogPath -Encoding UTF8

    Write-Host ""
    Write-Host "Uploading model catalog..." -ForegroundColor Yellow
    Set-AzStorageBlobContent `
        -File $CatalogPath `
        -Container $ContainerName `
        -Blob "catalog.json" `
        -Context $Context `
        -Properties @{ ContentType = "application/json" } `
        -Force | Out-Null

    Write-Host "✓ Catalog uploaded" -ForegroundColor Green

    # Output summary
    Write-Host ""
    Write-Host "=== Deployment Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Storage Blob URL:"
    Write-Host "  https://$StorageAccountName.blob.core.windows.net/$ContainerName/catalog.json"
    Write-Host ""
    Write-Host "Model files uploaded:"
    foreach ($ModelKey in $Models.Keys) {
        $Model = $Models[$ModelKey]
        Write-Host "  - $($Model.Filename) ($($Model.ExecutionProvider))"
    }
    Write-Host ""
    Write-Host "Note: If using CDN, allow a few minutes for propagation." -ForegroundColor Yellow

} finally {
    # Cleanup
    Write-Host ""
    Write-Host "Cleaning up temp directory..." -ForegroundColor Yellow
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
