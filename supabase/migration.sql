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

drop view if exists public.public_questions;
create view public.public_questions as select id, number from public.questions;
grant select on public.public_questions to anon, authenticated;

drop view if exists public.public_settings;
create view public.public_settings as select id, title, subtitle, show_score, show_leaderboard, require_all from public.quiz_settings;
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
