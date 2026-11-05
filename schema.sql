-- =====================================================================
--  Quiz Live — ระบบเกมตอบคำถามแบบเล่นพร้อมกัน (Supabase)
--  วิธีใช้: เปิด Supabase > SQL Editor > New query > วางทั้งไฟล์ > Run
--  รันซ้ำได้ (ไม่ลบข้อมูลเดิม)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0) ตั้งค่าระบบ: โดเมนอีเมลที่อนุญาตให้สร้าง/จัดเกม
--    เปลี่ยนได้ภายหลัง: update app_config set allowed_domain = 'xxx.com';
-- ---------------------------------------------------------------------
create table if not exists public.app_config (
  id int primary key default 1 check (id = 1),
  allowed_domain text not null default 'princgroup.com'
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') like ('%@' || lower((select allowed_domain from app_config where id = 1))),
    false)
$$;

-- ---------------------------------------------------------------------
-- 1) ตาราง
-- ---------------------------------------------------------------------
create table if not exists public.quizzes (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  owner_email text not null default coalesce(auth.jwt() ->> 'email', ''),
  department  text not null default '',
  title       text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.questions (
  id            uuid primary key default gen_random_uuid(),
  quiz_id       uuid not null references public.quizzes(id) on delete cascade,
  position      int  not null default 0,
  text          text not null check (char_length(text) between 1 and 500),
  image_url     text,
  choices       jsonb not null check (jsonb_typeof(choices) = 'array'
                                      and jsonb_array_length(choices) between 2 and 4),
  correct_index int  not null check (correct_index >= 0 and correct_index < jsonb_array_length(choices)),
  time_limit    int  not null default 20 check (time_limit between 5 and 120)
);
create index if not exists questions_quiz_idx on public.questions (quiz_id, position);

-- รอบการเล่น (เก็บสำเนาคำถามไว้ แก้ชุดคำถามระหว่างเล่นก็ไม่กระทบ)
create table if not exists public.sessions (
  id                  uuid primary key default gen_random_uuid(),
  quiz_id             uuid not null references public.quizzes(id) on delete cascade,
  host_id             uuid not null default auth.uid(),
  title               text not null,
  pin                 text not null,
  status              text not null default 'lobby'
                      check (status in ('lobby', 'question', 'reveal', 'ended')),
  current_index       int  not null default -1,
  questions           jsonb not null,
  total_questions     int  not null,
  question_started_at timestamptz,
  question_ends_at    timestamptz,
  created_at          timestamptz not null default now()
);
create unique index if not exists sessions_active_pin on public.sessions (pin) where status <> 'ended';

create table if not exists public.players (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions(id) on delete cascade,
  nickname    text not null check (char_length(nickname) between 1 and 30),
  token       uuid not null default gen_random_uuid(),
  score       int  not null default 0,
  last_points int  not null default 0,
  joined_at   timestamptz not null default now(),
  unique (session_id, nickname)
);

create table if not exists public.answers (
  id             bigserial primary key,
  session_id     uuid not null references public.sessions(id) on delete cascade,
  player_id      uuid not null references public.players(id) on delete cascade,
  question_index int  not null,
  choice         int  not null,
  is_correct     boolean not null,
  points         int  not null,
  answered_at    timestamptz not null default now(),
  unique (player_id, question_index)
);
create index if not exists answers_session_idx on public.answers (session_id, question_index);

-- ---------------------------------------------------------------------
-- 2) สิทธิ์ (RLS) — ผู้เล่นไม่ต้องล็อกอิน เข้าถึงผ่านฟังก์ชันเท่านั้น
-- ---------------------------------------------------------------------
alter table public.app_config enable row level security;
alter table public.quizzes    enable row level security;
alter table public.questions  enable row level security;
alter table public.sessions   enable row level security;
alter table public.players    enable row level security;
alter table public.answers    enable row level security;

revoke all on public.app_config, public.quizzes, public.questions,
              public.sessions, public.players, public.answers from anon;

drop policy if exists quizzes_read   on public.quizzes;
drop policy if exists quizzes_insert on public.quizzes;
drop policy if exists quizzes_update on public.quizzes;
drop policy if exists quizzes_delete on public.quizzes;
create policy quizzes_read   on public.quizzes for select to authenticated using (public.is_staff());
create policy quizzes_insert on public.quizzes for insert to authenticated
  with check (public.is_staff() and owner_id = auth.uid());
create policy quizzes_update on public.quizzes for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy quizzes_delete on public.quizzes for delete to authenticated using (owner_id = auth.uid());

drop policy if exists questions_read  on public.questions;
drop policy if exists questions_write on public.questions;
create policy questions_read on public.questions for select to authenticated using (public.is_staff());
create policy questions_write on public.questions for all to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id and q.owner_id = auth.uid()))
  with check (exists (select 1 from public.quizzes q where q.id = quiz_id and q.owner_id = auth.uid()));

drop policy if exists sessions_host on public.sessions;
create policy sessions_host on public.sessions for select to authenticated using (host_id = auth.uid());
drop policy if exists sessions_host_delete on public.sessions;
create policy sessions_host_delete on public.sessions for delete to authenticated using (host_id = auth.uid());

drop policy if exists players_host on public.players;
create policy players_host on public.players for select to authenticated
  using (exists (select 1 from public.sessions s where s.id = session_id and s.host_id = auth.uid()));

drop policy if exists answers_host on public.answers;
create policy answers_host on public.answers for select to authenticated
  using (exists (select 1 from public.sessions s where s.id = session_id and s.host_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 3) ฟังก์ชันฝั่งผู้จัด
-- ---------------------------------------------------------------------

-- บันทึกชุดคำถามทั้งชุดในครั้งเดียว (p_id = null คือสร้างใหม่)
create or replace function public.save_quiz(
  p_id uuid, p_title text, p_department text, p_description text, p_questions jsonb
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if p_id is null then
    insert into quizzes (title, department, description)
    values (trim(p_title), trim(coalesce(p_department, '')), coalesce(p_description, ''))
    returning id into v_id;
  else
    update quizzes set title = trim(p_title), department = trim(coalesce(p_department, '')),
                       description = coalesce(p_description, ''), updated_at = now()
     where id = p_id and owner_id = auth.uid()
    returning id into v_id;
    if v_id is null then raise exception 'ไม่มีสิทธิ์แก้ไขชุดคำถามนี้'; end if;
    delete from questions where quiz_id = v_id;
  end if;

  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit)
  select v_id, (t.ord - 1)::int, trim(t.q ->> 'text'), nullif(t.q ->> 'image_url', ''),
         t.q -> 'choices', (t.q ->> 'correct_index')::int, coalesce((t.q ->> 'time_limit')::int, 20)
    from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) with ordinality as t(q, ord);
  return v_id;
end $$;

-- คัดลอกชุดคำถามของแผนกอื่นมาเป็นของตัวเอง
create or replace function public.duplicate_quiz(p_id uuid)
returns uuid language plpgsql security invoker set search_path = public as $$
declare v_src quizzes; v_id uuid;
begin
  select * into v_src from quizzes where id = p_id;
  if v_src.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  insert into quizzes (title, department, description)
  values (left(v_src.title || ' (สำเนา)', 200), v_src.department, v_src.description)
  returning id into v_id;
  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit)
  select v_id, position, text, image_url, choices, correct_index, time_limit
    from questions where quiz_id = p_id;
  return v_id;
end $$;

-- เปิดห้องเกม ได้รหัส PIN 6 หลัก
create or replace function public.create_session(p_quiz_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;

  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices,
           'correct', correct_index, 'time', time_limit) order by position), count(*)
    into v_qs, v_n
    from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;

  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions)
  values (p_quiz_id, auth.uid(), v_quiz.title, v_pin, v_qs, v_n)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- ไปข้อถัดไป (จากหน้ารอ หรือหลังเฉลย) — ถ้าหมดข้อจะจบเกม
create or replace function public.host_next(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; v_idx int; v_time int;
begin
  select * into s from sessions where id = p_session and host_id = auth.uid() for update;
  if s.id is null then raise exception 'ไม่พบห้องเกม หรือไม่มีสิทธิ์'; end if;
  if s.status = 'question' then raise exception 'ต้องเฉลยข้อนี้ก่อน'; end if;
  if s.status = 'ended' then return jsonb_build_object('status', 'ended'); end if;

  v_idx := s.current_index + 1;
  if v_idx >= s.total_questions then
    update sessions set status = 'ended' where id = p_session;
    return jsonb_build_object('status', 'ended');
  end if;
  v_time := (s.questions -> v_idx ->> 'time')::int;
  update sessions
     set status = 'question', current_index = v_idx,
         question_started_at = now(), question_ends_at = now() + make_interval(secs => v_time)
   where id = p_session;
  return jsonb_build_object('status', 'question', 'index', v_idx, 'remaining', v_time);
end $$;

-- เฉลย: บวกคะแนนของข้อนี้เข้าคะแนนรวม
create or replace function public.host_reveal(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions;
begin
  select * into s from sessions where id = p_session and host_id = auth.uid() for update;
  if s.id is null then raise exception 'ไม่พบห้องเกม หรือไม่มีสิทธิ์'; end if;
  if s.status <> 'question' then return jsonb_build_object('status', s.status); end if;

  update players p
     set score = p.score + coalesce(a.points, 0), last_points = coalesce(a.points, 0)
    from players pl
    left join answers a on a.player_id = pl.id and a.question_index = s.current_index
   where pl.session_id = p_session and p.id = pl.id;

  update sessions set status = 'reveal' where id = p_session;
  return jsonb_build_object('status', 'reveal');
end $$;

create or replace function public.host_end(p_session uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update sessions set status = 'ended' where id = p_session and host_id = auth.uid();
end $$;

create or replace function public.host_kick(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from players p using sessions s
   where p.id = p_player and s.id = p.session_id and s.host_id = auth.uid();
end $$;

-- ---------------------------------------------------------------------
-- 4) ฟังก์ชันฝั่งผู้เล่น (ไม่ต้องล็อกอิน ใช้ player_id + token)
-- ---------------------------------------------------------------------
create or replace function public.join_game(p_pin text, p_nickname text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; v_name text := trim(coalesce(p_nickname, '')); p players;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 30 then
    raise exception 'กรุณาใส่ชื่อ 1-30 ตัวอักษร';
  end if;
  select * into s from sessions
   where pin = trim(p_pin) and status <> 'ended' order by created_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบห้องเกมนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  if (select count(*) from players where session_id = s.id) >= 300 then
    raise exception 'ห้องนี้เต็มแล้ว';
  end if;
  if exists (select 1 from players where session_id = s.id and lower(nickname) = lower(v_name)) then
    raise exception 'ชื่อนี้มีคนใช้แล้ว ลองชื่ออื่น';
  end if;
  insert into players (session_id, nickname) values (s.id, v_name) returning * into p;
  return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id,
                            'nickname', p.nickname, 'title', s.title);
end $$;

create or replace function public.player_state(p_player uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; a answers; v_rank int; v_n int; r jsonb;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then return jsonb_build_object('status', 'kicked'); end if;
  select * into s from sessions where id = p.session_id;

  r := jsonb_build_object('status', s.status, 'title', s.title, 'index', s.current_index,
                          'total', s.total_questions, 'nickname', p.nickname, 'score', p.score);
  if s.current_index >= 0 then
    q := s.questions -> s.current_index;
    select * into a from answers where player_id = p.id and question_index = s.current_index;
  end if;

  if s.status = 'question' then
    r := r || jsonb_build_object(
      'question', q ->> 'text', 'image_url', q ->> 'image_url', 'choices', q -> 'choices',
      'time', (q ->> 'time')::int,
      'remaining', greatest(0, extract(epoch from s.question_ends_at - now())),
      'answered', a.id is not null, 'my_choice', a.choice);
  elsif s.status in ('reveal', 'ended') then
    select count(*) + 1 into v_rank from players where session_id = s.id and score > p.score;
    select count(*) into v_n from players where session_id = s.id;
    r := r || jsonb_build_object('rank', v_rank, 'players', v_n);
    if s.status = 'reveal' then
      r := r || jsonb_build_object(
        'question', q ->> 'text', 'choices', q -> 'choices', 'correct', (q ->> 'correct')::int,
        'answered', a.id is not null, 'my_choice', a.choice,
        'is_correct', coalesce(a.is_correct, false), 'points', p.last_points);
    end if;
  end if;
  return r;
end $$;

-- ส่งคำตอบ: ถูกได้ 500-1000 คะแนน ตอบเร็วยิ่งได้มาก
create or replace function public.submit_answer(p_player uuid, p_token uuid, p_choice int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; v_correct boolean; v_frac numeric; v_points int; v_id bigint;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then raise exception 'ไม่พบผู้เล่น'; end if;
  select * into s from sessions where id = p.session_id;
  if s.status <> 'question' then raise exception 'หมดเวลาตอบข้อนี้แล้ว'; end if;
  if now() > s.question_ends_at + interval '1 second' then raise exception 'หมดเวลาตอบข้อนี้แล้ว'; end if;

  q := s.questions -> s.current_index;
  if p_choice < 0 or p_choice >= jsonb_array_length(q -> 'choices') then
    raise exception 'ตัวเลือกไม่ถูกต้อง';
  end if;
  v_correct := p_choice = (q ->> 'correct')::int;
  v_frac := least(1, greatest(0,
              extract(epoch from now() - s.question_started_at) / (q ->> 'time')::numeric));
  v_points := case when v_correct then round(1000 * (1 - v_frac / 2))::int else 0 end;

  insert into answers (session_id, player_id, question_index, choice, is_correct, points)
  values (s.id, p.id, s.current_index, p_choice, v_correct, v_points)
  on conflict (player_id, question_index) do nothing
  returning id into v_id;
  if v_id is null then raise exception 'ส่งคำตอบข้อนี้ไปแล้ว'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ใช้กับ Apps Script กันโปรเจกต์ถูกพัก
create or replace function public.ping()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'quizzes', (select count(*) from quizzes), 'at', now())
$$;

-- สิทธิ์เรียกฟังก์ชัน
revoke execute on function public.save_quiz(uuid, text, text, text, jsonb),
                           public.duplicate_quiz(uuid), public.create_session(uuid),
                           public.host_next(uuid), public.host_reveal(uuid),
                           public.host_end(uuid), public.host_kick(uuid)
  from public, anon;
grant execute on function public.save_quiz(uuid, text, text, text, jsonb),
                          public.duplicate_quiz(uuid), public.create_session(uuid),
                          public.host_next(uuid), public.host_reveal(uuid),
                          public.host_end(uuid), public.host_kick(uuid)
  to authenticated;
grant execute on function public.join_game(text, text), public.player_state(uuid, uuid),
                          public.submit_answer(uuid, uuid, int), public.ping(), public.is_staff()
  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Realtime: หน้าจอใหญ่ฟังคนเข้าห้อง / คนตอบ / คะแนน
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'players') then
    alter publication supabase_realtime add table public.players;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'answers') then
    alter publication supabase_realtime add table public.answers;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6) ที่เก็บรูปประกอบคำถาม
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('quiz-images', 'quiz-images', true)
on conflict (id) do nothing;

drop policy if exists quiz_images_upload on storage.objects;
create policy quiz_images_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'quiz-images' and public.is_staff()
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists quiz_images_delete on storage.objects;
create policy quiz_images_delete on storage.objects for delete to authenticated
  using (bucket_id = 'quiz-images' and (storage.foldername(name))[1] = auth.uid()::text);
