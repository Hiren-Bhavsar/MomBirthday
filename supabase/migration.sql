-- Run this after the original schema/policies.

create table if not exists public.quiz_settings (
  id integer primary key check (id=1),
  title text not null default 'How Old Was Mom?',
  subtitle text not null default 'Walk around the room, find each numbered photo, and guess Mom''s age.',
  tolerance integer not null default 0 check (tolerance between 0 and 120),
  show_score boolean not null default true,
  show_leaderboard boolean not null default false,
  require_all boolean not null default true
);

insert into public.quiz_settings(id) values (1) on conflict (id) do nothing;

-- ADMIN-CONTROLLED THEME COLORS
alter table public.quiz_settings add column if not exists green text not null default '#083026';
alter table public.quiz_settings add column if not exists gold text not null default '#e4b93f';
alter table public.quiz_settings add column if not exists cream text not null default '#f8f3e7';
alter table public.quiz_settings add column if not exists ink text not null default '#17352d';


alter table public.quiz_settings add column if not exists show_score boolean not null default true;
alter table public.quiz_settings add column if not exists show_leaderboard boolean not null default false;
alter table public.quiz_settings add column if not exists require_all boolean not null default true;
alter table public.quiz_settings enable row level security;

drop policy if exists "admins can read settings" on public.quiz_settings;
create policy "admins can read settings" on public.quiz_settings for select to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
drop policy if exists "admins can update settings" on public.quiz_settings;
create policy "admins can update settings" on public.quiz_settings for update to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));

drop policy if exists "Admins can delete questions" on public.questions;
create policy "Admins can delete questions" on public.questions for delete to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));

-- PER-PHOTO SUBTITLES
alter table public.questions add column if not exists subtitle text not null default 'Mom was';

update public.questions set subtitle = 'Mom was' where subtitle is null or trim(subtitle) = '';

 drop view if exists public.public_questions;
create view public.public_questions as select id, number, subtitle from public.questions;
grant select on public.public_questions to anon, authenticated;

drop view if exists public.public_settings;
create view public.public_settings as select id, title, subtitle, show_score, show_leaderboard, require_all, green, gold, cream, ink from public.quiz_settings;
grant select on public.public_settings to anon, authenticated;

drop view if exists public.public_leaderboard;
create view public.public_leaderboard as select id, participant_name, correct_count, total_questions, submitted_at from public.submissions;
grant select on public.public_leaderboard to anon, authenticated;

create or replace function public.submit_quiz(participant_name text, answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  submission_id uuid;
  total integer;
  correct integer;
  tolerance integer;
  require_all_answers boolean;
  item jsonb;
begin
  if char_length(trim(participant_name)) < 1 or char_length(trim(participant_name)) > 100 then raise exception 'Invalid participant name'; end if;
  select count(*) into total from public.questions;
  if total = 0 then raise exception 'The quiz is not set up yet'; end if;
  select qs.tolerance, qs.require_all into tolerance, require_all_answers from public.quiz_settings qs where qs.id=1;
  if require_all_answers and jsonb_array_length(answers) <> total then raise exception 'Please answer every photo'; end if;
  if jsonb_array_length(answers) < 1 then raise exception 'Please enter at least one guess'; end if;
  if jsonb_array_length(answers) > total then raise exception 'Too many answers'; end if;
  if (select count(distinct (a->>'question_id')) from jsonb_array_elements(answers) a) <> jsonb_array_length(answers) then raise exception 'Duplicate question answers'; end if;
  select count(*) into correct from jsonb_array_elements(answers) a join public.questions q on q.id=(a->>'question_id')::uuid where abs((a->>'guess')::integer-q.correct_age) <= tolerance;
  insert into public.submissions(participant_name,correct_count,total_questions) values(trim(participant_name),correct,jsonb_array_length(answers)) returning id into submission_id;
  for item in select * from jsonb_array_elements(answers) loop
    insert into public.guesses(submission_id,question_id,guess) values(submission_id,(item->>'question_id')::uuid,(item->>'guess')::integer);
  end loop;
  return jsonb_build_object('correct',correct,'total',jsonb_array_length(answers));
end; $$;
grant execute on function public.submit_quiz(text,jsonb) to anon, authenticated;


-- DEVICE LOCK + LEADERBOARD MANAGEMENT
-- Run this after the existing migration. Existing submissions remain valid.
alter table public.submissions add column if not exists device_id uuid;
create unique index if not exists submissions_device_id_unique on public.submissions(device_id) where device_id is not null;

drop policy if exists "admins can delete submissions" on public.submissions;
create policy "admins can delete submissions" on public.submissions for delete to authenticated using (exists(select 1 from public.admins where user_id=auth.uid()));
drop policy if exists "admins can update submissions" on public.submissions;
create policy "admins can update submissions" on public.submissions for update to authenticated using (exists(select 1 from public.admins where user_id=auth.uid())) with check (exists(select 1 from public.admins where user_id=auth.uid()));

create or replace function public.has_device_submitted(device_id uuid)
returns boolean language sql security definer set search_path=public as $$
  select exists(select 1 from public.submissions where submissions.device_id = has_device_submitted.device_id);
$$;
grant execute on function public.has_device_submitted(uuid) to anon, authenticated;

create or replace function public.submit_quiz(participant_name text, answers jsonb, device_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  submission_id uuid;
  total integer;
  correct integer;
  tolerance integer;
  require_all_answers boolean;
  item jsonb;
begin
  if device_id is null then raise exception 'Invalid device'; end if;
  if exists(select 1 from public.submissions where public.submissions.device_id = submit_quiz.device_id) then
    raise exception 'This device has already submitted an entry. Please ask the organizer to remove it if you need to submit again.';
  end if;
  if char_length(trim(participant_name)) < 1 or char_length(trim(participant_name)) > 100 then raise exception 'Invalid participant name'; end if;
  select count(*) into total from public.questions;
  if total = 0 then raise exception 'The quiz is not set up yet'; end if;
  select qs.tolerance, qs.require_all into tolerance, require_all_answers from public.quiz_settings qs where qs.id=1;
  if require_all_answers and jsonb_array_length(answers) <> total then raise exception 'Please answer every photo'; end if;
  if jsonb_array_length(answers) < 1 then raise exception 'Please enter at least one guess'; end if;
  if jsonb_array_length(answers) > total then raise exception 'Too many answers'; end if;
  if (select count(distinct (a->>'question_id')) from jsonb_array_elements(answers) a) <> jsonb_array_length(answers) then raise exception 'Duplicate question answers'; end if;
  if (select count(*) from jsonb_array_elements(answers) a join public.questions q on q.id=(a->>'question_id')::uuid) <> jsonb_array_length(answers) then raise exception 'Invalid question answer'; end if;
  select count(*) into correct from jsonb_array_elements(answers) a join public.questions q on q.id=(a->>'question_id')::uuid where abs((a->>'guess')::integer-q.correct_age) <= tolerance;
  insert into public.submissions(participant_name,correct_count,total_questions,device_id) values(trim(participant_name),correct,jsonb_array_length(answers),device_id) returning id into submission_id;
  for item in select * from jsonb_array_elements(answers) loop
    insert into public.guesses(submission_id,question_id,guess) values(submission_id,(item->>'question_id')::uuid,(item->>'guess')::integer);
  end loop;
  return jsonb_build_object('correct',correct,'total',jsonb_array_length(answers));
exception when unique_violation then
  raise exception 'This device has already submitted an entry. Please ask the organizer to remove it if you need to submit again.';
end; $$;
grant execute on function public.submit_quiz(text,jsonb,uuid) to anon, authenticated;
revoke execute on function public.submit_quiz(text,jsonb) from anon, authenticated;

