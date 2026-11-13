# Contributing to CampusFlow

Thanks for contributing. Coordinate feature ownership with the team before editing shared files or database objects.

## Workflow

1. Create a branch from the current default branch: `feature/short-description` or `fix/short-description`.
2. Keep changes focused and avoid committing generated files, model weights, local settings, credentials, camera footage, or personal data.
3. Run `flutter analyze` after Flutter changes. For simulator changes, run `python -m py_compile tools/sensor_simulator.py` and review the required environment variables.
4. Open a pull request that explains the change, how it was checked, and whether it needs a database migration or dashboard configuration.
5. Ask another team member to review before merging.

## Database changes

Describe schema and policy changes in a reviewed, versioned SQL migration before applying them to a shared Supabase project. Keep RLS enabled on exposed tables and never add a service-role/secret key to client code or repository history.

## UI changes

Prefer the existing theme, reusable widgets, and feature-based folders. Keep loading, empty, error, and offline states understandable and accessible.
