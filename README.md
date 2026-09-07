# Mom's Birthday Quiz

Mobile-first birthday photo guessing game for GitHub Pages + Supabase.

The photos are physical prints around the room. The website stores photo numbers, secret correct ages, guesses, and results, but does not host the photos.

## Design

- Base color: `#083026`
- Complimentary gold: `#d6b46a`
- Background uses a faint gold-on-green Ganesha pattern derived from the supplied reference image.

## Admin

Public quiz: `/`
Admin login: `/KASHLondon`

The admin can:
- Set the title/subtitle
- Set the acceptable age buffer (for example, `1` means ±1 year counts as correct)
- Add/edit/delete numbered photos
- Set correct ages
- View the leaderboard

The admin path is intentionally obscure, but Supabase authentication and RLS are the real security boundary.

## Supabase

For a fresh project, run `supabase/schema.sql`.

For the project that already has the original tables/policies from the setup walkthrough, use the migration SQL below instead of re-running the policy creation statements. See `supabase/migration.sql`.

Create an admin user in **Authentication > Users > Add user**, then insert that user's UUID into `public.admins`:

```sql
insert into public.admins(user_id) values ('YOUR-USER-UUID');
```

## Local test

```bash
npm install
npm run dev
```

## GitHub Pages

The Supabase project URL and publishable key are in `src/config.js`. The publishable key is intended for browser use. Never put a Supabase secret/service-role key there.

Enable GitHub Pages in repository Settings > Pages and select **GitHub Actions** as the source.


## Full admin customization

The admin can configure:
- Quiz title and subtitle
- Any age tolerance from 0 to 120 years
- Whether every photo must be answered
- Whether the participant sees their score immediately
- Whether a public leaderboard is shown after submission
- Photo/question numbering
- Correct age for each printed photo
- Add/delete questions

Run `supabase/migration.sql` in the SQL Editor after the original schema/policy setup.

After creating the Supabase Auth user, add that user's UUID to `public.admins`:

```sql
insert into public.admins(user_id) values ('YOUR-AUTH-USER-UUID');
```
