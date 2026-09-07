create extension if not exists pgcrypto;

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  number integer not null unique,
  correct_age integer not null check (correct_age between 0 and 120),
  created_at timestamptz not null default now()
);
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  participant_name text not null check (char_length(trim(participant_name)) between 1 and 100),
  correct_count integer not null,
  total_questions integer not null,
  submitted_at timestamptz not null default now()
);
create table if not exists public.guesses (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  guess integer not null check (guess between 0 and 120)
);
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.quiz_settings (
  id integer primary key check (id=1),
  title text not null default 'How Old Was Mom?',
  subtitle text not null default 'Walk around the room, find each numbered photo, and guess Mom''s age.',
  tolerance integer not null default 0 check (tolerance between 0 and 20)
);
insert into public.quiz_settings(id) values (1) on conflict (id) do nothing;

alter table public.questions enable row level security;
alter table public.submissions enable row level security;
alter table public.guesses enable row level security;
alter table public.admins enable row level security;
alter table public.quiz_settings enable row level security;

-- If these policies already exist, skip this policy section and use the migration
-- section at the bottom instead. This block is intended for a fresh project.
create policy "admins can read questions" on public.questions for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can insert questions" on public.questions for insert to authenticated with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can update questions" on public.questions for update to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can delete questions" on public.questions for delete to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can read submissions" on public.submissions for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can read guesses" on public.guesses for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can read own admin row" on public.admins for select to authenticated using (user_id=auth.uid());
create policy "admins can read settings" on public.quiz_settings for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
create policy "admins can update settings" on public.quiz_settings for update to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));

-- Public views expose no correct answers.
drop view if exists public.public_questions;
create view public.public_questions as select id, number from public.questions;
grant select on public.public_questions to anon, authenticated;

drop view if exists public.public_settings;
create view public.public_settings as select id, title, subtitle from public.quiz_settings;
grant select on public.public_settings to anon, authenticated;

revoke all on public.questions from anon;
revoke all on public.submissions from anon;
revoke all on public.guesses from anon;
revoke all on public.admins from anon;
revoke all on public.quiz_settings from anon;

create or replace function public.submit_quiz(participant_name text, answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare submission_id uuid; total integer; correct integer; tolerance integer; item jsonb;
begin
  if char_length(trim(participant_name)) < 1 or char_length(trim(participant_name)) > 100 then raise exception 'Invalid participant name'; end if;
  select count(*) into total from public.questions;
  if total = 0 then raise exception 'The quiz is not set up yet'; end if;
  if jsonb_array_length(answers) <> total then raise exception 'Please answer every photo'; end if;
  if (select count(distinct (a->>'question_id')) from jsonb_array_elements(answers) a) <> total then raise exception 'Invalid answer list'; end if;
  select qs.tolerance into tolerance from public.quiz_settings qs where qs.id=1;
  select count(*) into correct
  from jsonb_array_elements(answers) a
  join public.questions q on q.id=(a->>'question_id')::uuid
  where abs((a->>'guess')::integer-q.correct_age) <= tolerance;
  insert into public.submissions(participant_name,correct_count,total_questions) values(trim(participant_name),correct,total) returning id into submission_id;
  for item in select * from jsonb_array_elements(answers) loop
    insert into public.guesses(submission_id,question_id,guess) values(submission_id,(item->>'question_id')::uuid,(item->>'guess')::integer);
  end loop;
  return jsonb_build_object('correct',correct,'total',total);
end; $$;
grant execute on function public.submit_quiz(text,jsonb) to anon, authenticated;

-- MIGRATION FOR THE PROJECT YOU ALREADY CREATED:
-- If you already ran the original schema in Supabase, do NOT run the fresh policy
-- statements above again. Instead run only the statements below after creating the
-- new quiz_settings table and views. The policy names above already exist.
