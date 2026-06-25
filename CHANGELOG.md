# Change log for SPSUserSync

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml
- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add SECURITY.md file

### Changed

- .gitignore
  - Add patterns for runtime logs (`**/Logs/`, `*_errlog.xml`)
  - Add patterns for local configuration files and secrets (`config/credentials.psd1`, `config/ad-domains.psd1`, `config/*.local.psd1`)
  - Add patterns for JetBrains IDE (`.idea/`)
  - Add patterns for Pester test artifacts
- .github/ISSUE_TEMPLATE/1_bug_report.yml
  - Align version dropdown with current project versions (1.0.x)
  - Align PowerShell version options with supported runtimes (5.1, 7.x)
- README.md
  - Add Requirements section (SharePoint Server 2016/2019/SE, PowerShell 5.1, Farm Admin, AD reachability, farm property bags)
