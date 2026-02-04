# Contributing to YoloX Model Hosting

Thank you for your interest in contributing to this project!

## How to Contribute

### Reporting Issues

- Use GitHub Issues to report bugs or request features
- Include detailed steps to reproduce any bugs
- Provide your Azure region and subscription type if relevant

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Adding New Models

To add support for additional model variants:

1. Add the model URL and metadata to `scripts/deploy-models.ps1` and `scripts/deploy-models.sh`
2. Update the `templates/catalog-template.json` with the new model entry
3. Update the README.md with the new model information
4. Test the deployment in your own Azure subscription

### Code Style

- PowerShell scripts should follow [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines)
- Bash scripts should pass [ShellCheck](https://www.shellcheck.net/)
- ARM templates should validate with `az deployment group validate`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
