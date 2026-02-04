# YoloX Model Hosting on Azure CDN

This repository enables one-click deployment of YoloX ONNX models to Azure CDN, allowing client applications to dynamically fetch the appropriate model variant based on their device's execution provider.

## Available Models

| Model | Execution Provider | Source |
|-------|-------------------|--------|
| Yolo-X_w8a8.onnx | QNN NPU EP | [Qualcomm HuggingFace](https://huggingface.co/qualcomm/Yolo-X) |
| yolox-s-int8.onnx | Vitis AI EP | [AMD HuggingFace](https://huggingface.co/amd/yolox-s) |
| Yolo-X_float.onnx | CPU EP | [Qualcomm HuggingFace](https://huggingface.co/qualcomm/Yolo-X) |

## Deploy to Azure

Click the button below to deploy the CDN infrastructure and models to your Azure subscription:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcontosomodels%2FYoloHostingSample%2Fmain%2Fazuredeploy.json)

> **Note:** Replace `contosomodels` in the button URL with your GitHub username after forking this repository.

## What Gets Deployed

- **Azure Storage Account** - Blob storage for model files with static website hosting
- **Azure CDN Profile** - Global content delivery for low-latency model access
- **Azure CDN Endpoint** - Configured endpoint pointing to the storage account
- **Model Files** - Downloaded from HuggingFace and uploaded to blob storage
- **Model Catalog** - JSON manifest describing available models and their locations

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Client App    │────▶│    Azure CDN    │────▶│ Azure Storage   │
│                 │     │    Endpoint     │     │  (Blob/Static)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                                              │
         │  1. GET /models/catalog.json                 │
         │◀─────────────────────────────────────────────│
         │                                              │
         │  2. GET /models/{model-file}.onnx            │
         │◀─────────────────────────────────────────────│
```

## Model Catalog

After deployment, your CDN will serve a `catalog.json` at:
```
https://<your-cdn-endpoint>.azureedge.net/models/catalog.json
```

Example catalog structure:
```json
{
  "models": [
    {
      "id": "yolox-cpu",
      "name": "YoloX",
      "version": "1.0.0",
      "publisher": "YourOrganization",
      "executionProviders": [{ "name": "CPUExecutionProvider" }],
      "license": "MIT",
      "files": [{ "name": "Yolo-X_float.onnx", "url": "/models/Yolo-X_float.onnx" }]
    }
  ]
}
```

## Client Usage

```javascript
// Fetch the model catalog
const response = await fetch('https://<your-cdn>.azureedge.net/models/catalog.json');
const catalog = await response.json();

// Find model for your execution provider
const model = catalog.models.find(m => 
  m.executionProviders.some(ep => ep.name === 'CPUExecutionProvider')
);

// Download the model file
const modelUrl = `https://<your-cdn>.azureedge.net${model.files[0].url}`;
const modelData = await fetch(modelUrl);
```

## Post-Deployment Setup

After the ARM template deploys, you need to run the model upload script:

### Using Azure Cloud Shell (Recommended)

1. Open [Azure Cloud Shell](https://shell.azure.com)
2. Clone this repository:
   ```bash
   git clone https://github.com/contosomodels/YoloHostingSample.git
   cd YoloHostingSample
   ```
3. Run the deployment script:
   ```bash
   chmod +x scripts/deploy-models.sh
   ./scripts/deploy-models.sh -g <resource-group-name> -s <storage-account-name>
   ```

### Using Local PowerShell

```powershell
.\scripts\deploy-models.ps1 -ResourceGroupName "<resource-group-name>" -StorageAccountName "<storage-account-name>"
```

## Configuration

You can customize the deployment by modifying `azuredeploy.parameters.json`:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storageAccountName` | Name of the storage account | `yoloxmodels` + unique suffix |
| `cdnProfileName` | Name of the CDN profile | `yolox-cdn` |
| `cdnEndpointName` | Name of the CDN endpoint | `yolox-models` |
| `location` | Azure region for deployment | `eastus` |

## License

This project is licensed under the MIT License. The model files are subject to their respective licenses from Qualcomm and AMD.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
