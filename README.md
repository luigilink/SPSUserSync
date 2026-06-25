# SPSUserSync

![Latest release date](https://img.shields.io/github/release-date/luigilink/spsusersync.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/spsusersync/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/spsusersync.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Description

SPSUserSync is a PowerShell toolkit to sync SharePoint Server User Information Lists and User Profiles across multi-forest AD environments — an alternative to the built-in User Profile AD Import.

It's compatible with all supported versions for SharePoint OnPremises (2016 to Subscription Edition).

[Download the latest release, Click here!](https://github.com/luigilink/spsusersync/releases/latest)

## Requirements

- SharePoint Server **2016**, **2019**, or **Subscription Edition**
- **PowerShell 5.1** (Windows PowerShell) on every SharePoint server in scope
- **Farm Administrator** rights for the account running the scripts
- Network reachability to every Active Directory forest you want to synchronize (LDAP/389 or LDAPS/636)
- Farm property bags `APP_CODE` and `ENV_NAME` defined at farm level (used to route the generated JSON between application farms and the User Profile Service farm)

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSUserSync Wiki](https://github.com/luigilink/spsusersync/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
