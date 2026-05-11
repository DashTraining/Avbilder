# Avbilder admin site

Small ASP.NET Core admin app for the Avbilder demo intended for Azure App Service Free teir.

- App Service built-in authentication for sign-in.
- `AdminAllowlist` table for app-level admin authorization.
- Table scans for the demo dataset.
- App Service API upload for preview JPEGs.

Direct-to-Blob upload is a hardening/scaling path beyond this demo.

Setup is documented in `../docs/setup.md`; day-to-day deployment and demo operations are in `../docs/operations.md`.
