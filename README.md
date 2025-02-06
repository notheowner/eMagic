# eMagic | A module for mapping ATVs with some binaries and useful functions.

## Description

Based on the original eMagisk by emi and later on maintained by Astu but without loading 100 bash-completions and functions that are not needed on an ATV.
## The idea
The MITM healthcheck is intended to be very basic.\
If mitm is kill, make it un-kill :)
Anything else should in theory be handled by the MITM app.

## Issues
Any problems or concerns, raise an issue or pull request.
* As of now only Cosmog is supported by the healthcheck.

## Releases
Github actions build based on latest commit in main branch.\
As Magisk modules are simple zip files. You can just zip the repo with any personal changes you want.
```console
zip -r emagic.zip . -x ".git/*" "build.sh" ".gitignore" "*zip" ".github/*"
```
