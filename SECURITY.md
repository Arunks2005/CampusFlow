# Security policy

CampusFlow is an academic prototype. Do not use it with real personal, location, camera, or vehicle-identifying information until the deployment has been reviewed and secured for that use.

## Reporting a concern

Do not open a public issue containing credentials, personal information, plate numbers, or exploit details. Contact the project maintainers privately and include a concise description and steps to reproduce.

## Secrets and data

- Never commit Supabase secret/service-role keys, sensor tokens, OAuth client secrets, signing keys, passwords, or private certificates.
- Supabase publishable keys are client-facing identifiers, not a substitute for Row Level Security. Review RLS, grants, and callable RPC functions before deployment.
- Rotate any credential that was committed or otherwise exposed. Removing it from the latest source does not erase it from Git history.
- Do not commit camera footage, images of people, real number plates, or database exports.

## Camera features

The webcam simulator should process frames locally and send aggregate counts only. Any real deployment needs appropriate notice/consent, access restrictions, retention controls, and institutional/legal review. Vehicle plates are identifying data; do not collect real plates in this prototype without an approved data-handling plan.
