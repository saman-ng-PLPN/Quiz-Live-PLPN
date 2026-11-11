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

-- ผู้ดูแลระบบ: เห็น/แก้/ลบได้ทุกชุดคำถาม
-- เพิ่มคนแรกด้วย SQL:  insert into app_admins (email) values ('อีเมล@princgroup.com');
-- คนต่อไปเพิ่มจากหน้าเว็บได้
create table if not exists public.app_admins (
  email      text primary key check (email = lower(email)),
  added_by   text,
  created_at timestamptz not null default now()
);
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_staff()
     and exists (select 1 from app_admins where email = lower(auth.jwt() ->> 'email'))
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

-- v2: รูปหน้าปก / สีคำตอบต่อข้อ / รูปในตัวเลือก
alter table public.quizzes   add column if not exists cover_url text;
-- v3: ส่วนตัว (false) / แชร์ให้ทุกแผนก (true)
alter table public.quizzes   add column if not exists shared boolean not null default false;
-- v4: รูปประจำตัวผู้เล่น (รหัสรูปจาก avatars.js)
alter table public.players   add column if not exists avatar text;
alter table public.sessions  add column if not exists cover_url text;
alter table public.questions add column if not exists colors jsonb;          -- ["#rrggbb", ...] ต่อตัวเลือก
alter table public.questions add column if not exists choice_images jsonb;   -- ["url" | "", ...] ต่อตัวเลือก

-- ---------------------------------------------------------------------
-- 2) สิทธิ์ (RLS) — ผู้เล่นไม่ต้องล็อกอิน เข้าถึงผ่านฟังก์ชันเท่านั้น
-- ---------------------------------------------------------------------
alter table public.app_config enable row level security;
alter table public.app_admins enable row level security;
alter table public.quizzes    enable row level security;
alter table public.questions  enable row level security;
alter table public.sessions   enable row level security;
alter table public.players    enable row level security;
alter table public.answers    enable row level security;

revoke all on public.app_admins from anon, authenticated;
revoke all on public.app_config, public.quizzes, public.questions,
              public.sessions, public.players, public.answers from anon;
-- ให้สิทธิ์ชัดเจน (ใช้ได้แม้ปิด "Automatically expose new tables")
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.quizzes, public.questions to authenticated;
grant select, delete on public.sessions to authenticated;
grant select on public.players, public.answers to authenticated;

drop policy if exists quizzes_read   on public.quizzes;
drop policy if exists quizzes_insert on public.quizzes;
drop policy if exists quizzes_update on public.quizzes;
drop policy if exists quizzes_delete on public.quizzes;
create policy quizzes_read   on public.quizzes for select to authenticated
  using (public.is_staff() and (owner_id = auth.uid() or shared or public.is_admin()));
create policy quizzes_insert on public.quizzes for insert to authenticated
  with check (public.is_staff() and owner_id = auth.uid());
create policy quizzes_update on public.quizzes for update to authenticated
  using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
create policy quizzes_delete on public.quizzes for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

drop policy if exists questions_read  on public.questions;
drop policy if exists questions_write on public.questions;
-- เห็นคำถามได้เมื่อเห็นชุดคำถามนั้น (ตามสิทธิ์ของ quizzes)
create policy questions_read on public.questions for select to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id));
create policy questions_write on public.questions for all to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id and (q.owner_id = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.quizzes q where q.id = quiz_id and (q.owner_id = auth.uid() or public.is_admin())));

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
drop function if exists public.save_quiz(uuid, text, text, text, jsonb);
drop function if exists public.save_quiz(uuid, text, text, text, jsonb, text);
create or replace function public.save_quiz(
  p_id uuid, p_title text, p_department text, p_description text, p_questions jsonb,
  p_cover text default null, p_shared boolean default false
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if p_id is null then
    insert into quizzes (title, department, description, cover_url, shared)
    values (trim(p_title), trim(coalesce(p_department, '')), coalesce(p_description, ''), nullif(p_cover, ''),
            coalesce(p_shared, false))
    returning id into v_id;
  else
    update quizzes set title = trim(p_title), department = trim(coalesce(p_department, '')),
                       description = coalesce(p_description, ''), cover_url = nullif(p_cover, ''),
                       shared = coalesce(p_shared, false), updated_at = now()
     where id = p_id and (owner_id = auth.uid() or public.is_admin())
    returning id into v_id;
    if v_id is null then raise exception 'ไม่มีสิทธิ์แก้ไขชุดคำถามนี้'; end if;
    delete from questions where quiz_id = v_id;
  end if;

  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, (t.ord - 1)::int, trim(t.q ->> 'text'), nullif(t.q ->> 'image_url', ''),
         t.q -> 'choices', (t.q ->> 'correct_index')::int, coalesce((t.q ->> 'time_limit')::int, 20),
         case when jsonb_typeof(t.q -> 'colors') = 'array'
               and not exists (select 1 from jsonb_array_elements_text(t.q -> 'colors') c
                                where c !~ '^#[0-9a-fA-F]{6}$')
              then t.q -> 'colors' end,
         case when jsonb_typeof(t.q -> 'choice_images') = 'array' then t.q -> 'choice_images' end
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
  insert into quizzes (title, department, description, cover_url)
  values (left(v_src.title || ' (สำเนา)', 200), v_src.department, v_src.description, v_src.cover_url)
  returning id into v_id;
  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, position, text, image_url, choices, correct_index, time_limit, colors, choice_images
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
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;

  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices,
           'correct', correct_index, 'time', time_limit,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n
    from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;

  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url)
  values (p_quiz_id, auth.uid(), v_quiz.title, v_pin, v_qs, v_n, v_quiz.cover_url)
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
drop function if exists public.join_game(text, text);
create or replace function public.join_game(p_pin text, p_nickname text, p_avatar text default null)
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
  insert into players (session_id, nickname, avatar)
  values (s.id, v_name, case when p_avatar ~ '^[a-z0-9-]{1,30}$' then p_avatar end) returning * into p;
  return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id,
                            'nickname', p.nickname, 'avatar', p.avatar, 'title', s.title);
end $$;

create or replace function public.player_state(p_player uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; a answers; v_rank int; v_n int; r jsonb;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then return jsonb_build_object('status', 'kicked'); end if;
  select * into s from sessions where id = p.session_id;

  r := jsonb_build_object('status', s.status, 'title', s.title, 'index', s.current_index,
                          'total', s.total_questions, 'nickname', p.nickname, 'avatar', p.avatar, 'score', p.score,
                          'cover_url', s.cover_url);
  if s.current_index >= 0 then
    q := s.questions -> s.current_index;
    select * into a from answers where player_id = p.id and question_index = s.current_index;
  end if;

  if s.status = 'question' then
    r := r || jsonb_build_object(
      'question', q ->> 'text', 'image_url', q ->> 'image_url', 'choices', q -> 'choices',
      'colors', q -> 'colors', 'images', q -> 'images', 'time', (q ->> 'time')::int,
      'remaining', greatest(0, extract(epoch from s.question_ends_at - now())),
      'answered', a.id is not null, 'my_choice', a.choice);
  elsif s.status in ('reveal', 'ended') then
    select count(*) + 1 into v_rank from players where session_id = s.id and score > p.score;
    select count(*) into v_n from players where session_id = s.id;
    r := r || jsonb_build_object('rank', v_rank, 'players', v_n);
    if s.status = 'reveal' then
      r := r || jsonb_build_object(
        'question', q ->> 'text', 'choices', q -> 'choices', 'correct', (q ->> 'correct')::int,
        'colors', q -> 'colors', 'images', q -> 'images',
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

-- จัดการรายชื่อผู้ดูแลระบบ (เฉพาะผู้ดูแล)
create or replace function public.list_admins()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  return coalesce((select jsonb_agg(email order by email) from app_admins), '[]'::jsonb);
end $$;

create or replace function public.add_admin(p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text := lower(trim(coalesce(p_email, '')));
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  if v !~ ('^[^@\s]+@' || replace(lower((select allowed_domain from app_config where id = 1)), '.', '\.') || '$') then
    raise exception 'ต้องเป็นอีเมล @%', (select allowed_domain from app_config where id = 1);
  end if;
  insert into app_admins (email, added_by) values (v, lower(auth.jwt() ->> 'email')) on conflict do nothing;
  return public.list_admins();
end $$;

create or replace function public.remove_admin(p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  if (select count(*) from app_admins) <= 1 then raise exception 'ต้องมีผู้ดูแลระบบอย่างน้อย 1 คน'; end if;
  delete from app_admins where email = lower(trim(p_email));
  return public.list_admins();
end $$;

-- ใช้กับ Apps Script กันโปรเจกต์ถูกพัก
create or replace function public.ping()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'quizzes', (select count(*) from quizzes), 'at', now())
$$;

-- สิทธิ์เรียกฟังก์ชัน
revoke execute on function public.save_quiz(uuid, text, text, text, jsonb, text, boolean),
                           public.list_admins(), public.add_admin(text), public.remove_admin(text),
                           public.duplicate_quiz(uuid), public.create_session(uuid),
                           public.host_next(uuid), public.host_reveal(uuid),
                           public.host_end(uuid), public.host_kick(uuid)
  from public, anon;
grant execute on function public.save_quiz(uuid, text, text, text, jsonb, text, boolean),
                          public.list_admins(), public.add_admin(text), public.remove_admin(text), public.is_admin(),
                          public.duplicate_quiz(uuid), public.create_session(uuid),
                          public.host_next(uuid), public.host_reveal(uuid),
                          public.host_end(uuid), public.host_kick(uuid)
  to authenticated;
grant execute on function public.join_game(text, text, text), public.player_state(uuid, uuid),
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

-- =====================================================================
-- 7) v5: แบบทดสอบ Pre-test / Post-test
--    รอบอบรม (trainings) ผูกกับชุดคำถาม 1 ชุด มี Pre และ Post เปิด/ปิดแยกกัน
--    ผู้ทำไม่ต้องล็อกอิน ระบุตัวด้วย รหัสพนักงาน + ชื่อ + แผนก
-- =====================================================================
create table if not exists public.departments (
  name text primary key check (char_length(name) between 1 and 120),
  sort int not null default 0
);

create table if not exists public.trainings (
  id          uuid primary key default gen_random_uuid(),
  quiz_id     uuid references public.quizzes(id) on delete set null,
  owner_id    uuid not null default auth.uid(),
  owner_email text not null default coalesce(auth.jwt() ->> 'email', ''),
  title       text not null check (char_length(title) between 1 and 200),
  code        text not null unique,
  pass_percent int not null default 80 check (pass_percent between 0 and 100),
  pre_open    boolean not null default false,
  post_open   boolean not null default false,
  questions   jsonb not null,           -- สำเนาคำถาม ณ ตอนสร้างรอบ (มีเฉลย)
  total       int not null,
  cover_url   text,
  created_at  timestamptz not null default now()
);

create table if not exists public.test_submissions (
  id           bigserial primary key,
  training_id  uuid not null references public.trainings(id) on delete cascade,
  phase        text not null check (phase in ('pre', 'post')),
  emp_id       text not null check (char_length(emp_id) between 1 and 30),
  full_name    text not null check (char_length(full_name) between 1 and 120),
  department   text not null default '',
  answers      jsonb not null,          -- ตัวเลือกที่ตอบ เรียงตามข้อ
  score        int not null,
  total        int not null,
  submitted_at timestamptz not null default now(),
  unique (training_id, phase, emp_id)
);
-- v6: แผนกที่ใช้ในแต่ละรอบ (null = ทุกแผนกจากรายชื่อหลัก)
alter table public.trainings add column if not exists departments jsonb;
create index if not exists test_submissions_training_idx on public.test_submissions (training_id, phase);

alter table public.departments      enable row level security;
alter table public.trainings        enable row level security;
alter table public.test_submissions enable row level security;
revoke all on public.departments, public.trainings, public.test_submissions from anon;
revoke all on public.departments from authenticated;
grant select, update, delete on public.trainings to authenticated;
grant select, delete on public.test_submissions to authenticated;

drop policy if exists trainings_owner on public.trainings;
create policy trainings_owner on public.trainings for select to authenticated
  using (owner_id = auth.uid() or public.is_admin());
drop policy if exists trainings_owner_upd on public.trainings;
create policy trainings_owner_upd on public.trainings for update to authenticated
  using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
drop policy if exists trainings_owner_del on public.trainings;
create policy trainings_owner_del on public.trainings for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

drop policy if exists submissions_owner on public.test_submissions;
create policy submissions_owner on public.test_submissions for select to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id));
drop policy if exists submissions_owner_del on public.test_submissions;
create policy submissions_owner_del on public.test_submissions for delete to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id));

-- รายชื่อแผนก (ทุกคนอ่านได้ / ผู้ดูแลแก้ได้)
create or replace function public.list_departments()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(name order by sort, name), '[]'::jsonb) from departments
$$;
create or replace function public.set_departments(p_names jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  delete from departments where true;   -- Supabase บังคับให้ DELETE มี WHERE
  insert into departments (name, sort)
  select distinct on (trim(n)) trim(n), min(ord) over (partition by trim(n))
    from jsonb_array_elements_text(coalesce(p_names, '[]'::jsonb)) with ordinality as t(n, ord)
   where trim(n) <> '';
  return public.list_departments();
end $$;

-- สร้างรอบอบรมจากชุดคำถาม (สิทธิ์เหมือนการเปิดห้องเกม)
create or replace function public.create_training(p_quiz_id uuid, p_title text, p_pass int default 80)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_code text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;
  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices, 'correct', correct_index,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from trainings where code = v_code);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into trainings (quiz_id, title, code, pass_percent, questions, total, cover_url)
  values (p_quiz_id, left(coalesce(nullif(trim(p_title), ''), v_quiz.title), 200), v_code,
          least(100, greatest(0, coalesce(p_pass, 80))), v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end $$;

-- ข้อมูลแบบทดสอบสำหรับผู้ทำ (ไม่มีเฉลย / ส่งคำถามเฉพาะตอนเปิดอยู่)
create or replace function public.test_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  return jsonb_build_object(
    'title', t.title, 'cover_url', t.cover_url, 'total', t.total,
    'pre_open', t.pre_open, 'post_open', t.post_open, 'pass_percent', t.pass_percent,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'questions', case when t.pre_open or t.post_open then
      (select jsonb_agg(jsonb_build_object('text', q ->> 'text', 'image_url', q ->> 'image_url',
              'choices', q -> 'choices', 'colors', q -> 'colors', 'images', q -> 'images') order by o)
         from jsonb_array_elements(t.questions) with ordinality as x(q, o)) end);
end $$;

create or replace function public.submit_test(
  p_code text, p_phase text, p_emp_id text, p_name text, p_dept text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v_score int := 0; i int; v_ans int; v_pre test_submissions;
        v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_name text := trim(coalesce(p_name, ''));
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  if p_phase not in ('pre', 'post') then raise exception 'ระบุ Pre หรือ Post'; end if;
  if (p_phase = 'pre' and not t.pre_open) or (p_phase = 'post' and not t.post_open) then
    raise exception 'แบบทดสอบ %-test ปิดรับแล้ว', initcap(p_phase);
  end if;
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> t.total then
    raise exception 'กรุณาตอบให้ครบทุกข้อ';
  end if;
  for i in 0 .. t.total - 1 loop
    if jsonb_typeof(p_answers -> i) <> 'number' then raise exception 'กรุณาตอบให้ครบทุกข้อ'; end if;
    v_ans := (p_answers ->> i)::int;
    if v_ans = (t.questions -> i ->> 'correct')::int then v_score := v_score + 1; end if;
  end loop;
  begin
    insert into test_submissions (training_id, phase, emp_id, full_name, department, answers, score, total)
    values (t.id, p_phase, v_emp, left(v_name, 120), left(trim(coalesce(p_dept, '')), 120), p_answers, v_score, t.total);
  exception when unique_violation then
    raise exception 'รหัสพนักงาน % ส่ง %-test ของรอบนี้ไปแล้ว', v_emp, initcap(p_phase);
  end;
  if p_phase = 'pre' then return jsonb_build_object('ok', true, 'phase', 'pre'); end if;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp;
  return jsonb_build_object('ok', true, 'phase', 'post', 'score', v_score, 'total', t.total,
    'percent', round(100.0 * v_score / t.total), 'pass', 100.0 * v_score / t.total >= t.pass_percent,
    'pass_percent', t.pass_percent, 'pre_score', v_pre.score,
    'correct', (select jsonb_agg((q ->> 'correct')::int order by o) from jsonb_array_elements(t.questions) with ordinality x(q, o)));
end $$;

revoke execute on function public.set_departments(jsonb), public.create_training(uuid, text, int) from public, anon;
grant execute on function public.set_departments(jsonb), public.create_training(uuid, text, int) to authenticated;
grant execute on function public.list_departments(), public.test_info(text),
                          public.submit_test(text, text, text, text, text, jsonb) to anon, authenticated;

-- =====================================================================
-- 8) v7: โรงพยาบาล · สอบ Post-test ซ้ำจนผ่าน · สลับข้อ · แบบประเมิน (ไม่ระบุตัวตน)
-- =====================================================================
create table if not exists public.hospitals (
  name text primary key check (char_length(name) between 1 and 120),
  sort int not null default 0
);
alter table public.hospitals enable row level security;
revoke all on public.hospitals from anon, authenticated;
insert into public.hospitals (name, sort)
select n, s from (values ('ป.แพทย์ 1', 1), ('ป.แพทย์ 2', 2)) v(n, s)
 where not exists (select 1 from public.hospitals);

create or replace function public.list_hospitals()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(name order by sort, name), '[]'::jsonb) from hospitals
$$;
create or replace function public.set_hospitals(p_names jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  delete from hospitals where true;
  insert into hospitals (name, sort)
  select distinct on (trim(n)) trim(n), min(ord) over (partition by trim(n))
    from jsonb_array_elements_text(coalesce(p_names, '[]'::jsonb)) with ordinality as t(n, ord)
   where trim(n) <> '';
  return public.list_hospitals();
end $$;

-- รหัส 6 หลักสำหรับแบบประเมินแบบเดี่ยว
create or replace function public.gen_survey_code() returns text
language plpgsql volatile security definer set search_path = public as $$
declare c text; i int := 0;
begin
  loop
    c := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from surveys where code = c);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ'; end if;
  end loop;
  return c;
end $$;

create table if not exists public.surveys (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  owner_email text not null default coalesce(auth.jwt() ->> 'email', ''),
  title       text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  items       jsonb not null default '[]'::jsonb,   -- [{id, type: section|scale|text, text, required}]
  shared      boolean not null default false,
  code        text unique,
  open        boolean not null default false,       -- เปิดรับแบบเดี่ยว (?s=รหัส)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.surveys alter column code set default public.gen_survey_code();

-- คำตอบแบบประเมิน: ไม่มีข้อมูลผู้ตอบ ไม่มีเวลาละเอียด (เก็บแค่วันที่) เพื่อจับคู่ย้อนกลับไม่ได้
create table if not exists public.survey_responses (
  id           uuid primary key default gen_random_uuid(),
  survey_id    uuid not null references public.surveys(id) on delete cascade,
  training_id  uuid references public.trainings(id) on delete cascade,
  answers      jsonb not null,                          -- {item_id: ค่า}
  submitted_on date not null default ((now() at time zone 'Asia/Bangkok')::date)
);
create index if not exists survey_responses_idx on public.survey_responses (survey_id, training_id);

-- บันทึกว่าใคร "ทำแล้ว" (แยกจากคำตอบ ไม่มีเวลา)
create table if not exists public.survey_done (
  training_id uuid not null references public.trainings(id) on delete cascade,
  emp_id      text not null,
  primary key (training_id, emp_id)
);

alter table public.trainings add column if not exists survey_id uuid references public.surveys(id) on delete set null;
alter table public.trainings add column if not exists shuffle boolean not null default true;
alter table public.trainings add column if not exists retake  boolean not null default true;

alter table public.test_submissions add column if not exists hospital text not null default '';
alter table public.test_submissions add column if not exists attempt  int  not null default 1;
alter table public.test_submissions drop constraint if exists test_submissions_training_id_phase_emp_id_key;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'test_submissions_attempt_key') then
    alter table public.test_submissions add constraint test_submissions_attempt_key unique (training_id, phase, emp_id, attempt);
  end if;
end $$;

alter table public.surveys          enable row level security;
alter table public.survey_responses enable row level security;
alter table public.survey_done      enable row level security;
revoke all on public.surveys, public.survey_responses, public.survey_done from anon;
grant select, insert, update, delete on public.surveys to authenticated;
grant select, delete on public.survey_responses to authenticated;
grant select on public.survey_done to authenticated;

drop policy if exists surveys_read on public.surveys;
create policy surveys_read on public.surveys for select to authenticated
  using (public.is_staff() and (owner_id = auth.uid() or shared or public.is_admin()));
drop policy if exists surveys_insert on public.surveys;
create policy surveys_insert on public.surveys for insert to authenticated
  with check (public.is_staff() and owner_id = auth.uid());
drop policy if exists surveys_update on public.surveys;
create policy surveys_update on public.surveys for update to authenticated
  using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
drop policy if exists surveys_delete on public.surveys;
create policy surveys_delete on public.surveys for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

-- เห็นคำตอบได้: เจ้าของแบบประเมิน / ผู้ดูแล / เจ้าของรอบอบรมที่ผูกไว้
drop policy if exists responses_read on public.survey_responses;
create policy responses_read on public.survey_responses for select to authenticated
  using (exists (select 1 from public.surveys s where s.id = survey_id and (s.owner_id = auth.uid() or public.is_admin()))
         or (training_id is not null and exists (select 1 from public.trainings t where t.id = training_id)));
drop policy if exists responses_delete on public.survey_responses;
create policy responses_delete on public.survey_responses for delete to authenticated
  using (exists (select 1 from public.surveys s where s.id = survey_id and (s.owner_id = auth.uid() or public.is_admin()))
         or (training_id is not null and exists (select 1 from public.trainings t where t.id = training_id)));
drop policy if exists done_read on public.survey_done;
create policy done_read on public.survey_done for select to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id));

-- ตรวจและทำความสะอาดคำตอบแบบประเมิน (ใช้ภายใน)
create or replace function public.clean_survey_answers(p_items jsonb, p_ans jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare it jsonb; v jsonb; out jsonb := '{}'::jsonb; k text; n int := 0;
begin
  if jsonb_typeof(p_ans) <> 'object' then raise exception 'ข้อมูลแบบประเมินไม่ถูกต้อง'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    k := it ->> 'id'; v := p_ans -> k;
    if it ->> 'type' = 'scale' then
      n := n + 1;
      if v is null or jsonb_typeof(v) = 'null' then
        if coalesce((it ->> 'required')::boolean, false) then raise exception 'กรุณาให้คะแนนให้ครบทุกข้อ'; end if;
      elsif jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not in (1, 2, 3, 4, 5) then
        raise exception 'คะแนนต้องอยู่ระหว่าง 1–5';
      else out := out || jsonb_build_object(k, (v #>> '{}')::int); end if;
    elsif it ->> 'type' = 'text' then
      if v is not null and jsonb_typeof(v) = 'string' and trim(v #>> '{}') <> '' then
        out := out || jsonb_build_object(k, left(trim(v #>> '{}'), 2000));
      elsif coalesce((it ->> 'required')::boolean, false) then raise exception 'กรุณาตอบข้อความให้ครบ'; end if;
    end if;
  end loop;
  return out;
end $$;

-- ข้อมูลแบบทดสอบสำหรับผู้ทำ (ไม่มีเฉลย)
create or replace function public.test_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; sv surveys;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  select * into sv from surveys where id = t.survey_id;
  return jsonb_build_object(
    'title', t.title, 'cover_url', t.cover_url, 'total', t.total,
    'pre_open', t.pre_open, 'post_open', t.post_open, 'pass_percent', t.pass_percent,
    'shuffle', t.shuffle, 'retake', t.retake,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'hospitals', public.list_hospitals(),
    'survey', case when sv.id is not null then jsonb_build_object('title', sv.title, 'description', sv.description, 'items', sv.items) end,
    'questions', case when t.pre_open or t.post_open then
      (select jsonb_agg(jsonb_build_object('text', q ->> 'text', 'image_url', q ->> 'image_url',
              'choices', q -> 'choices', 'colors', q -> 'colors', 'images', q -> 'images') order by o)
         from jsonb_array_elements(t.questions) with ordinality as x(q, o)) end);
end $$;

-- สถานะของผู้สอบ (ใช้ QR เดียว พาไปขั้นตอนที่ถูกต้อง)
create or replace function public.test_status(p_code text, p_emp_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; v_emp text := upper(trim(coalesce(p_emp_id, ''))); last test_submissions; first test_submissions;
        v_pre test_submissions; v_n int; v_passed boolean; v_wrong jsonb;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  select count(*) into v_n from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp;
  select * into last  from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt desc limit 1;
  select * into first from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt limit 1;
  v_passed := last.id is not null and 100.0 * last.score / last.total >= t.pass_percent;
  if last.id is not null and not v_passed then
    select coalesce(jsonb_agg(o - 1), '[]'::jsonb) into v_wrong
      from jsonb_array_elements(t.questions) with ordinality x(q, o)
     where (last.answers ->> (o - 1)::int) is distinct from (q ->> 'correct');
  end if;
  return jsonb_build_object(
    'pre_done', v_pre.id is not null, 'pre_score', v_pre.score,
    'post_attempts', v_n, 'post_passed', v_passed,
    'survey_done', exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp),
    'has_survey', t.survey_id is not null,
    'score', last.score, 'total', t.total, 'first_score', first.score,
    'percent', case when last.id is not null then round(100.0 * last.score / t.total) end,
    -- คำตอบเดิมและข้อที่ผิด ส่งเฉพาะตอนยังไม่ผ่าน (กันการดึงคำตอบของคนที่ผ่านแล้ว)
    'last_answers', case when not v_passed then last.answers end,
    'wrong', v_wrong);
end $$;

-- ส่งแบบทดสอบ (Post-test สอบซ้ำได้จนผ่าน ถ้าเปิด retake)
drop function if exists public.submit_test(text, text, text, text, text, jsonb);
create or replace function public.submit_test(
  p_code text, p_phase text, p_emp_id text, p_name text, p_hospital text, p_dept text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v_score int := 0; i int; v_ans int; v_pre test_submissions; v_att int; v_last test_submissions;
        v_pass boolean; v_wrong jsonb := '[]'::jsonb;
        v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_name text := trim(coalesce(p_name, ''));
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  if p_phase not in ('pre', 'post') then raise exception 'ระบุ Pre หรือ Post'; end if;
  if (p_phase = 'pre' and not t.pre_open) or (p_phase = 'post' and not t.post_open) then
    raise exception 'แบบทดสอบ %-test ปิดรับแล้ว', initcap(p_phase);
  end if;
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> t.total then
    raise exception 'กรุณาตอบให้ครบทุกข้อ';
  end if;
  for i in 0 .. t.total - 1 loop
    if jsonb_typeof(p_answers -> i) <> 'number' then raise exception 'กรุณาตอบให้ครบทุกข้อ'; end if;
    v_ans := (p_answers ->> i)::int;
    if v_ans = (t.questions -> i ->> 'correct')::int then v_score := v_score + 1;
    else v_wrong := v_wrong || to_jsonb(i); end if;
  end loop;

  perform pg_advisory_xact_lock(hashtext(t.id::text || p_phase || v_emp));
  select * into v_last from test_submissions where training_id = t.id and phase = p_phase and emp_id = v_emp
   order by attempt desc limit 1;
  if v_last.id is not null then
    if p_phase = 'pre' then raise exception 'รหัสพนักงาน % ส่ง Pre-test ของรอบนี้ไปแล้ว', v_emp; end if;
    if 100.0 * v_last.score / v_last.total >= t.pass_percent then raise exception 'ท่านสอบ Post-test ผ่านแล้ว'; end if;
    if not t.retake then raise exception 'รหัสพนักงาน % ส่ง Post-test ของรอบนี้ไปแล้ว', v_emp; end if;
  end if;
  v_att := coalesce(v_last.attempt, 0) + 1;
  insert into test_submissions (training_id, phase, emp_id, full_name, hospital, department, answers, score, total, attempt)
  values (t.id, p_phase, v_emp, left(v_name, 120), left(trim(coalesce(p_hospital, '')), 120),
          left(trim(coalesce(p_dept, '')), 120), p_answers, v_score, t.total, v_att);

  if p_phase = 'pre' then return jsonb_build_object('ok', true, 'phase', 'pre'); end if;
  v_pass := 100.0 * v_score / t.total >= t.pass_percent;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  return jsonb_build_object('ok', true, 'phase', 'post', 'score', v_score, 'total', t.total, 'attempt', v_att,
    'percent', round(100.0 * v_score / t.total), 'pass', v_pass, 'pass_percent', t.pass_percent,
    'retake', t.retake, 'pre_score', v_pre.score,
    'wrong', case when v_pass then '[]'::jsonb else v_wrong end,
    'need_survey', v_pass and t.survey_id is not null
                   and not exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp));
end $$;

-- แบบประเมินหลัง Post-test (ต้องสอบผ่านแล้ว · ทำได้ครั้งเดียว · คำตอบไม่ผูกกับผู้ตอบ)
create or replace function public.submit_training_survey(p_code text, p_emp_id text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; sv surveys; v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_clean jsonb;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  select * into sv from surveys where id = t.survey_id;
  if sv.id is null then raise exception 'รอบนี้ไม่มีแบบประเมิน'; end if;
  if not exists (select 1 from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp
                   and 100.0 * score / total >= t.pass_percent) then
    raise exception 'ทำแบบประเมินได้หลังสอบ Post-test ผ่านแล้ว';
  end if;
  v_clean := public.clean_survey_answers(sv.items, p_answers);
  begin
    insert into survey_done (training_id, emp_id) values (t.id, v_emp);
  exception when unique_violation then raise exception 'ท่านทำแบบประเมินของรอบนี้แล้ว'; end;
  insert into survey_responses (survey_id, training_id, answers) values (sv.id, t.id, v_clean);
  return jsonb_build_object('ok', true);
end $$;

-- แบบประเมินแบบเดี่ยว (?s=รหัส)
create or replace function public.survey_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sv surveys;
begin
  select * into sv from surveys where code = trim(p_code);
  if sv.id is null then raise exception 'ไม่พบแบบประเมินนี้'; end if;
  return jsonb_build_object('title', sv.title, 'description', sv.description, 'open', sv.open,
                            'items', case when sv.open then sv.items end);
end $$;
create or replace function public.submit_open_survey(p_code text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare sv surveys;
begin
  select * into sv from surveys where code = trim(p_code);
  if sv.id is null then raise exception 'ไม่พบแบบประเมินนี้'; end if;
  if not sv.open then raise exception 'แบบประเมินนี้ปิดรับแล้ว'; end if;
  insert into survey_responses (survey_id, answers) values (sv.id, public.clean_survey_answers(sv.items, p_answers));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.clean_survey_answers(jsonb, jsonb), public.gen_survey_code() from public, anon;
grant execute on function public.gen_survey_code() to authenticated;
revoke execute on function public.set_hospitals(jsonb) from public, anon;
grant execute on function public.set_hospitals(jsonb) to authenticated;
grant execute on function public.list_hospitals(), public.test_info(text), public.test_status(text, text),
  public.submit_test(text, text, text, text, text, text, jsonb), public.submit_training_survey(text, text, jsonb),
  public.survey_info(text), public.submit_open_survey(text, jsonb) to anon, authenticated;

-- =====================================================================
-- 9) v7: Pre-test แบบเกม (เล่นพร้อมกันทั้งห้อง) → ผลบันทึกเป็น Pre-test ของรอบอบรม
--    - ผู้เล่นเข้าห้องด้วย รหัสพนักงาน + ชื่อ + โรงพยาบาล + แผนก
--    - ระหว่างเกมไม่เฉลยข้อที่ถูก (บอกแค่จำนวนคนตอบถูก/ผิด) · เกมปกติยังเฉลยเหมือนเดิม
--    - จบเกมแล้วบันทึกเป็น Pre-test (นับจำนวนข้อที่ถูก ไม่ใช่คะแนนความเร็ว)
--    - คนที่มาไม่ทัน ทำ Pre-test แบบทำเองย้อนหลังได้ (เปิดสวิตช์ Pre-test ในหน้ารอบ)
-- =====================================================================
alter table public.sessions alter column quiz_id drop not null;
alter table public.sessions add column if not exists training_id uuid references public.trainings(id) on delete set null;
create index if not exists sessions_training_idx on public.sessions (training_id) where training_id is not null;

alter table public.players add column if not exists emp_id     text;
alter table public.players add column if not exists full_name  text;
alter table public.players add column if not exists hospital   text;
alter table public.players add column if not exists department text;
create unique index if not exists players_session_emp on public.players (session_id, emp_id) where emp_id is not null;

-- ที่มาของผล: self = ทำเองผ่านลิงก์ / game = จากเกม Pre-test
alter table public.test_submissions add column if not exists source text not null default 'self';

-- เก็บเวลาต่อข้อไว้ในสำเนาคำถามของรอบด้วย (ใช้ตอนเปิดเป็นเกม)
create or replace function public.create_training(p_quiz_id uuid, p_title text, p_pass int default 80)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_code text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;
  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices, 'correct', correct_index,
           'time', time_limit, 'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from trainings where code = v_code);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into trainings (quiz_id, title, code, pass_percent, questions, total, cover_url)
  values (p_quiz_id, left(coalesce(nullif(trim(p_title), ''), v_quiz.title), 200), v_code,
          least(100, greatest(0, coalesce(p_pass, 80))), v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end $$;

-- เปิดห้องเกม Pre-test จากรอบอบรม (ถ้ามีห้องที่ยังไม่จบ จะกลับเข้าห้องเดิม)
create or replace function public.create_pre_game(p_training uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; s sessions; v_qs jsonb; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into t from trainings where id = p_training;
  if t.id is null or not (t.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'ไม่พบรอบนี้ หรือไม่มีสิทธิ์';
  end if;
  select * into s from sessions where training_id = t.id and status <> 'ended' order by created_at desc limit 1;
  if s.id is not null then
    if s.host_id <> auth.uid() then
      raise exception 'มีห้องเกม Pre-test ของรอบนี้เปิดอยู่แล้ว (PIN %) โดยผู้จัดอีกคน', s.pin;
    end if;
    return jsonb_build_object('session_id', s.id, 'pin', s.pin, 'resumed', true);
  end if;

  -- ลำดับข้อตรงกับรอบอบรมเสมอ (ใช้ตรวจคะแนน Pre-test) · รอบเก่าที่ไม่มีเวลาต่อข้อ ใช้เวลาจากชุดคำถาม หรือ 20 วินาที
  select jsonb_agg(x.q || jsonb_build_object('time', least(120, greatest(5, coalesce(
           (x.q ->> 'time')::int,
           (select time_limit from questions where quiz_id = t.quiz_id order by position offset (x.o - 1) limit 1),
           20)))) order by x.o)
    into v_qs from jsonb_array_elements(t.questions) with ordinality as x(q, o);
  if v_qs is null then raise exception 'รอบนี้ยังไม่มีคำถาม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url, training_id)
  values (t.quiz_id, auth.uid(), t.title, v_pin, v_qs, jsonb_array_length(v_qs), t.cover_url, t.id)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- ข้อมูลห้องก่อนเข้าร่วม: เกมปกติ (ใส่ชื่อเล่น) หรือ Pre-test (ใส่รหัสพนักงาน)
create or replace function public.game_info(p_pin text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s sessions; t trainings;
begin
  select * into s from sessions where pin = trim(p_pin) and status <> 'ended' order by created_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบห้องเกมนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  if s.training_id is null then return jsonb_build_object('mode', 'game', 'title', s.title); end if;
  select * into t from trainings where id = s.training_id;
  return jsonb_build_object('mode', 'pre', 'title', s.title, 'status', s.status, 'cover_url', s.cover_url,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'hospitals', public.list_hospitals());
end $$;

-- เข้าห้องเกม Pre-test ด้วยรหัสพนักงาน
create or replace function public.join_pre_game(
  p_pin text, p_emp_id text, p_name text, p_hospital text, p_dept text, p_avatar text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; p players; v_nick text;
        v_emp  text := upper(trim(coalesce(p_emp_id, '')));
        v_name text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  if char_length(v_emp) > 30 then raise exception 'รหัสพนักงานยาวเกินไป'; end if;
  select * into s from sessions where pin = trim(p_pin) and status <> 'ended' order by created_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบห้องเกมนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  if s.training_id is null then raise exception 'ห้องนี้เป็นเกมทั่วไป ไม่ต้องใช้รหัสพนักงาน'; end if;

  perform pg_advisory_xact_lock(hashtext(s.id::text || v_emp));
  -- เข้าซ้ำด้วยรหัส+ชื่อเดิม (เปลี่ยนเครื่อง/ล้างเบราว์เซอร์) → กลับเป็นผู้เล่นเดิม
  select * into p from players where session_id = s.id and emp_id = v_emp;
  if p.id is not null then
    if lower(coalesce(p.full_name, '')) <> lower(v_name) then
      raise exception 'รหัสพนักงาน % อยู่ในห้องนี้แล้ว', v_emp;
    end if;
    return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id, 'mode', 'pre',
                              'nickname', p.nickname, 'avatar', p.avatar, 'title', s.title);
  end if;
  if exists (select 1 from test_submissions where training_id = s.training_id and phase = 'pre' and emp_id = v_emp) then
    raise exception 'รหัสพนักงาน % ทำ Pre-test ของรอบนี้แล้ว', v_emp;
  end if;
  if s.status <> 'lobby' then
    raise exception 'เกมเริ่มไปแล้ว — แจ้งผู้จัดเพื่อทำ Pre-test แบบทำเองหลังจบเกม';
  end if;
  if (select count(*) from players where session_id = s.id) >= 300 then raise exception 'ห้องนี้เต็มแล้ว'; end if;

  v_nick := left(v_name, 30);
  if exists (select 1 from players where session_id = s.id and lower(nickname) = lower(v_nick)) then
    v_nick := left(v_name, greatest(1, 30 - char_length(v_emp) - 3)) || ' (' || right(v_emp, 26) || ')';
  end if;
  insert into players (session_id, nickname, avatar, emp_id, full_name, hospital, department)
  values (s.id, v_nick, case when p_avatar ~ '^[a-z0-9-]{1,30}$' then p_avatar end, v_emp, left(v_name, 120),
          left(trim(coalesce(p_hospital, '')), 120), left(trim(coalesce(p_dept, '')), 120))
  returning * into p;
  return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id, 'mode', 'pre',
                            'nickname', p.nickname, 'avatar', p.avatar, 'title', s.title);
end $$;

-- เกมปกติ: ใส่ชื่อเล่น (ห้อง Pre-test ต้องเข้าด้วยรหัสพนักงานผ่าน join_pre_game)
create or replace function public.join_game(p_pin text, p_nickname text, p_avatar text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; v_name text := trim(coalesce(p_nickname, '')); p players;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 30 then
    raise exception 'กรุณาใส่ชื่อ 1-30 ตัวอักษร';
  end if;
  select * into s from sessions
   where pin = trim(p_pin) and status <> 'ended' order by created_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบห้องเกมนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  if s.training_id is not null then
    raise exception 'ห้องนี้เป็น Pre-test ต้องเข้าด้วยรหัสพนักงาน — รีเฟรชหน้าแล้วใส่ PIN อีกครั้ง';
  end if;
  if (select count(*) from players where session_id = s.id) >= 300 then
    raise exception 'ห้องนี้เต็มแล้ว';
  end if;
  if exists (select 1 from players where session_id = s.id and lower(nickname) = lower(v_name)) then
    raise exception 'ชื่อนี้มีคนใช้แล้ว ลองชื่ออื่น';
  end if;
  insert into players (session_id, nickname, avatar)
  values (s.id, v_name, case when p_avatar ~ '^[a-z0-9-]{1,30}$' then p_avatar end) returning * into p;
  return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id, 'mode', 'game',
                            'nickname', p.nickname, 'avatar', p.avatar, 'title', s.title);
end $$;

-- จบเกม Pre-test: บันทึกผลของผู้เล่นที่ตอบอย่างน้อย 1 ข้อเป็น Pre-test (ใช้ภายใน)
-- คะแนน = จำนวนข้อที่ถูก · ข้อที่ไม่ได้ตอบนับเป็นผิด · คนที่มีผล Pre-test อยู่แล้วจะไม่ถูกเขียนทับ
create or replace function public.finish_pre_game(p_session uuid)
returns int language plpgsql security definer set search_path = public as $$
declare s sessions; v_n int;
begin
  select * into s from sessions where id = p_session;
  if s.training_id is null or not exists (select 1 from trainings where id = s.training_id) then return 0; end if;
  insert into test_submissions (training_id, phase, emp_id, full_name, hospital, department,
                                answers, score, total, attempt, source)
  select s.training_id, 'pre', p.emp_id, left(coalesce(p.full_name, p.nickname), 120),
         coalesce(p.hospital, ''), coalesce(p.department, ''),
         (select jsonb_agg(a.choice order by g.i)
            from generate_series(0, s.total_questions - 1) as g(i)
            left join answers a on a.player_id = p.id and a.question_index = g.i),
         (select count(*) from answers a where a.player_id = p.id and a.is_correct),
         s.total_questions, 1, 'game'
    from players p
   where p.session_id = s.id and p.emp_id is not null
     and exists (select 1 from answers a where a.player_id = p.id)
     and not exists (select 1 from test_submissions x
                      where x.training_id = s.training_id and x.phase = 'pre' and x.emp_id = p.emp_id)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ข้อถัดไป / จบเกม — ถ้าเป็นเกม Pre-test บันทึกผลตอนจบ
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
    return jsonb_build_object('status', 'ended', 'saved', public.finish_pre_game(p_session));
  end if;
  v_time := (s.questions -> v_idx ->> 'time')::int;
  update sessions
     set status = 'question', current_index = v_idx,
         question_started_at = now(), question_ends_at = now() + make_interval(secs => v_time)
   where id = p_session;
  return jsonb_build_object('status', 'question', 'index', v_idx, 'remaining', v_time);
end $$;

create or replace function public.host_end(p_session uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update sessions set status = 'ended' where id = p_session and host_id = auth.uid() and status <> 'ended';
  if found then perform public.finish_pre_game(p_session); end if;
end $$;

-- สถานะผู้เล่น: เกม Pre-test ไม่ส่งข้อที่ถูก ส่งแค่จำนวนคนตอบถูก/ทั้งหมด
create or replace function public.player_state(p_player uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; a answers; v_rank int; v_n int; r jsonb; v_pre boolean;
        v_right int; v_ans int;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then return jsonb_build_object('status', 'kicked'); end if;
  select * into s from sessions where id = p.session_id;
  v_pre := s.training_id is not null;

  r := jsonb_build_object('status', s.status, 'title', s.title, 'index', s.current_index,
                          'total', s.total_questions, 'nickname', p.nickname, 'avatar', p.avatar, 'score', p.score,
                          'cover_url', s.cover_url, 'mode', case when v_pre then 'pre' else 'game' end);
  if s.current_index >= 0 then
    q := s.questions -> s.current_index;
    select * into a from answers where player_id = p.id and question_index = s.current_index;
  end if;

  if s.status = 'question' then
    r := r || jsonb_build_object(
      'question', q ->> 'text', 'image_url', q ->> 'image_url', 'choices', q -> 'choices',
      'colors', q -> 'colors', 'images', q -> 'images', 'time', (q ->> 'time')::int,
      'remaining', greatest(0, extract(epoch from s.question_ends_at - now())),
      'answered', a.id is not null, 'my_choice', a.choice);
  elsif s.status in ('reveal', 'ended') then
    select count(*) + 1 into v_rank from players where session_id = s.id and score > p.score;
    select count(*) into v_n from players where session_id = s.id;
    r := r || jsonb_build_object('rank', v_rank, 'players', v_n);
    if s.status = 'reveal' then
      r := r || jsonb_build_object(
        'question', q ->> 'text', 'choices', q -> 'choices',
        'correct', case when v_pre then null else (q ->> 'correct')::int end,
        'colors', q -> 'colors', 'images', q -> 'images',
        'answered', a.id is not null, 'my_choice', a.choice,
        'is_correct', coalesce(a.is_correct, false), 'points', p.last_points);
      if v_pre then
        select count(*) filter (where is_correct), count(*) into v_right, v_ans
          from answers where session_id = s.id and question_index = s.current_index;
        r := r || jsonb_build_object('room_right', v_right, 'room_answered', v_ans);
      end if;
    elsif v_pre then
      select count(*) filter (where is_correct), count(*) into v_right, v_ans from answers where player_id = p.id;
      r := r || jsonb_build_object('my_right', v_right, 'my_answered', v_ans);
    end if;
  end if;
  return r;
end $$;

revoke execute on function public.finish_pre_game(uuid) from public, anon, authenticated;
revoke execute on function public.create_pre_game(uuid) from public, anon;
grant execute on function public.create_pre_game(uuid) to authenticated;
grant execute on function public.game_info(text), public.join_pre_game(text, text, text, text, text, text)
  to anon, authenticated;

-- =====================================================================
-- 10) v8: ชุดหลักสูตร — สร้างหลายรุ่นในครั้งเดียว (เช่น เช้า/บ่าย หรือ รุ่น 1–8)
--     แต่ละรุ่นเป็นรอบ Pre/Post แยกกัน (QR / สวิตช์ / เกม Pre-test ของตัวเอง)
--     รายงานรวมหลายรอบดูได้ที่หน้าเว็บ (เลือกทั้งชุด หรือเลือกรอบเองก็ได้)
-- =====================================================================
alter table public.trainings add column if not exists series_id   uuid;
alter table public.trainings add column if not exists series      text;
alter table public.trainings add column if not exists round_label text;
alter table public.trainings add column if not exists round_no    int;
create index if not exists trainings_series_idx on public.trainings (series_id) where series_id is not null;

-- p_labels: ["รุ่น 1","รุ่น 2",...] หรือ [""] = รอบเดียว
-- p_settings: {"survey_id": uuid|null, "shuffle": bool, "retake": bool}
create or replace function public.create_training_series(
  p_quiz_id uuid, p_series text, p_labels jsonb, p_pass int default 80, p_settings jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_series text := left(trim(coalesce(p_series, '')), 150); v_sid uuid; v_n int; v_label text; v_i int := 0;
        r jsonb; v_out jsonb := '[]'::jsonb; v_survey uuid; v_multi boolean;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if v_series = '' then raise exception 'กรุณาใส่ชื่อหลักสูตร'; end if;
  if jsonb_typeof(p_labels) <> 'array' then raise exception 'รายชื่อรุ่นไม่ถูกต้อง'; end if;
  v_n := jsonb_array_length(p_labels);
  if v_n < 1 or v_n > 40 then raise exception 'สร้างได้ 1–40 รุ่นต่อครั้ง'; end if;
  v_multi := v_n > 1;

  v_survey := nullif(p_settings ->> 'survey_id', '')::uuid;
  if v_survey is not null and not exists (select 1 from surveys where id = v_survey
       and (owner_id = auth.uid() or shared or public.is_admin())) then
    raise exception 'ไม่พบแบบประเมินที่เลือก';
  end if;

  v_sid := case when v_multi then gen_random_uuid() end;
  for v_label in select left(trim(x), 100) from jsonb_array_elements_text(p_labels) as t(x) loop
    v_i := v_i + 1;
    if v_multi and v_label = '' then v_label := 'รุ่น ' || v_i; end if;
    r := public.create_training(p_quiz_id,
           case when v_label = '' then v_series else v_series || ' · ' || v_label end, p_pass);
    update trainings
       set series_id = v_sid, series = case when v_multi then v_series end,
           round_label = nullif(v_label, ''), round_no = case when v_multi then v_i end,
           survey_id = v_survey,
           shuffle = coalesce((p_settings ->> 'shuffle')::boolean, true),
           retake  = coalesce((p_settings ->> 'retake')::boolean, true)
     where id = (r ->> 'id')::uuid;
    v_out := v_out || jsonb_build_object('id', r ->> 'id', 'code', r ->> 'code', 'label', v_label);
  end loop;
  return jsonb_build_object('series_id', v_sid, 'rounds', v_out);
end $$;

revoke execute on function public.create_training_series(uuid, text, jsonb, int, jsonb) from public, anon;
grant execute on function public.create_training_series(uuid, text, jsonb, int, jsonb) to authenticated;

-- =====================================================================
-- 11) v9: ข้อเขียน (ไม่คิดคะแนน) — เก็บคำตอบไว้ในรายงาน แต่ไม่นำมาคิดผล
--     - ใช้ได้ในแบบทดสอบ Pre/Post (ผู้ทำพิมพ์คำตอบเอง ต้องตอบทุกข้อ)
--     - เกม (ทั้งเกมปกติและเกม Pre-test) ข้ามข้อเขียนให้อัตโนมัติ
--     - คะแนนเต็ม (total) = จำนวนข้อปรนัย
-- =====================================================================
alter table public.questions add column if not exists kind text not null default 'choice';
alter table public.questions alter column correct_index drop not null;
do $$ declare c record; begin
  for c in select conname from pg_constraint
            where conrelid = 'public.questions'::regclass and contype = 'c'
              and (pg_get_constraintdef(oid) ilike '%choices%' or pg_get_constraintdef(oid) ilike '%correct_index%'
                   or pg_get_constraintdef(oid) ilike '%kind%')
  loop execute format('alter table public.questions drop constraint %I', c.conname); end loop;
end $$;
alter table public.questions add constraint questions_shape_chk check (
  (kind = 'text' and correct_index is null and jsonb_typeof(choices) = 'array')
  or (kind = 'choice' and jsonb_typeof(choices) = 'array' and jsonb_array_length(choices) between 2 and 4
      and correct_index is not null and correct_index >= 0 and correct_index < jsonb_array_length(choices)));

create or replace function public.save_quiz(
  p_id uuid, p_title text, p_department text, p_description text, p_questions jsonb,
  p_cover text default null, p_shared boolean default false
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) q
                  where coalesce(q ->> 'kind', 'choice') <> 'text') then
    raise exception 'ต้องมีข้อปรนัย (มีตัวเลือก) อย่างน้อย 1 ข้อ';
  end if;
  if p_id is null then
    insert into quizzes (title, department, description, cover_url, shared)
    values (trim(p_title), trim(coalesce(p_department, '')), coalesce(p_description, ''), nullif(p_cover, ''),
            coalesce(p_shared, false))
    returning id into v_id;
  else
    update quizzes set title = trim(p_title), department = trim(coalesce(p_department, '')),
                       description = coalesce(p_description, ''), cover_url = nullif(p_cover, ''),
                       shared = coalesce(p_shared, false), updated_at = now()
     where id = p_id and (owner_id = auth.uid() or public.is_admin())
    returning id into v_id;
    if v_id is null then raise exception 'ไม่มีสิทธิ์แก้ไขชุดคำถามนี้'; end if;
    delete from questions where quiz_id = v_id;
  end if;

  insert into questions (quiz_id, position, kind, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, (t.ord - 1)::int, k, trim(t.q ->> 'text'), nullif(t.q ->> 'image_url', ''),
         case when k = 'text' then '[]'::jsonb else t.q -> 'choices' end,
         case when k = 'text' then null else (t.q ->> 'correct_index')::int end,
         coalesce((t.q ->> 'time_limit')::int, 20),
         case when k = 'choice' and jsonb_typeof(t.q -> 'colors') = 'array'
               and not exists (select 1 from jsonb_array_elements_text(t.q -> 'colors') c
                                where c !~ '^#[0-9a-fA-F]{6}$')
              then t.q -> 'colors' end,
         case when k = 'choice' and jsonb_typeof(t.q -> 'choice_images') = 'array' then t.q -> 'choice_images' end
    from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) with ordinality as t(q, ord),
         lateral (select case when t.q ->> 'kind' = 'text' then 'text' else 'choice' end as k) kk;
  return v_id;
end $$;

create or replace function public.duplicate_quiz(p_id uuid)
returns uuid language plpgsql security invoker set search_path = public as $$
declare v_src quizzes; v_id uuid;
begin
  select * into v_src from quizzes where id = p_id;
  if v_src.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  insert into quizzes (title, department, description, cover_url)
  values (left(v_src.title || ' (สำเนา)', 200), v_src.department, v_src.description, v_src.cover_url)
  returning id into v_id;
  insert into questions (quiz_id, position, kind, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, position, kind, text, image_url, choices, correct_index, time_limit, colors, choice_images
    from questions where quiz_id = p_id;
  return v_id;
end $$;

-- เกมปกติ: ข้ามข้อเขียน
create or replace function public.create_session(p_quiz_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;

  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices,
           'correct', correct_index, 'time', time_limit,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n
    from questions where quiz_id = p_quiz_id and kind <> 'text';
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีข้อปรนัยสำหรับเล่นเกม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;

  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url)
  values (p_quiz_id, auth.uid(), v_quiz.title, v_pin, v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- รอบอบรม: เก็บข้อเขียนไว้ในสำเนาคำถาม (kind = text) · total = จำนวนข้อปรนัย
create or replace function public.create_training(p_quiz_id uuid, p_title text, p_pass int default 80)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_code text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;
  select jsonb_agg(case when kind = 'text'
             then jsonb_build_object('kind', 'text', 'text', text, 'image_url', image_url, 'choices', '[]'::jsonb)
             else jsonb_build_object('text', text, 'image_url', image_url, 'choices', choices, 'correct', correct_index,
                    'time', time_limit, 'colors', colors, 'images', choice_images) end order by position),
         count(*) filter (where kind <> 'text')
    into v_qs, v_n from questions where quiz_id = p_quiz_id;
  if coalesce(v_n, 0) = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีข้อปรนัย'; end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from trainings where code = v_code);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into trainings (quiz_id, title, code, pass_percent, questions, total, cover_url)
  values (p_quiz_id, left(coalesce(nullif(trim(p_title), ''), v_quiz.title), 200), v_code,
          least(100, greatest(0, coalesce(p_pass, 80))), v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end $$;

create or replace function public.test_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; sv surveys;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  select * into sv from surveys where id = t.survey_id;
  return jsonb_build_object(
    'title', t.title, 'cover_url', t.cover_url, 'total', t.total, 'count', jsonb_array_length(t.questions),
    'pre_open', t.pre_open, 'post_open', t.post_open, 'pass_percent', t.pass_percent,
    'shuffle', t.shuffle, 'retake', t.retake,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'hospitals', public.list_hospitals(),
    'survey', case when sv.id is not null then jsonb_build_object('title', sv.title, 'description', sv.description, 'items', sv.items) end,
    'questions', case when t.pre_open or t.post_open then
      (select jsonb_agg(jsonb_build_object('kind', coalesce(q ->> 'kind', 'choice'), 'text', q ->> 'text', 'image_url', q ->> 'image_url',
              'choices', q -> 'choices', 'colors', q -> 'colors', 'images', q -> 'images') order by o)
         from jsonb_array_elements(t.questions) with ordinality as x(q, o)) end);
end $$;

create or replace function public.test_status(p_code text, p_emp_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; v_emp text := upper(trim(coalesce(p_emp_id, ''))); last test_submissions; first test_submissions;
        v_pre test_submissions; v_n int; v_passed boolean; v_wrong jsonb;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  select count(*) into v_n from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp;
  select * into last  from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt desc limit 1;
  select * into first from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt limit 1;
  v_passed := last.id is not null and 100.0 * last.score / last.total >= t.pass_percent;
  if last.id is not null and not v_passed then
    select coalesce(jsonb_agg(o - 1), '[]'::jsonb) into v_wrong
      from jsonb_array_elements(t.questions) with ordinality x(q, o)
     where coalesce(q ->> 'kind', 'choice') <> 'text'
       and (last.answers ->> (o - 1)::int) is distinct from (q ->> 'correct');
  end if;
  return jsonb_build_object(
    'pre_done', v_pre.id is not null, 'pre_score', v_pre.score,
    'post_attempts', v_n, 'post_passed', v_passed,
    'survey_done', exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp),
    'has_survey', t.survey_id is not null,
    'score', last.score, 'total', t.total, 'first_score', first.score,
    'percent', case when last.id is not null then round(100.0 * last.score / t.total) end,
    'last_answers', case when not v_passed then last.answers end,
    'wrong', v_wrong);
end $$;

create or replace function public.submit_test(
  p_code text, p_phase text, p_emp_id text, p_name text, p_hospital text, p_dept text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v_score int := 0; i int; v_n int; v_ans int; v_pre test_submissions; v_att int; v_last test_submissions;
        v_pass boolean; v_wrong jsonb := '[]'::jsonb; v_clean jsonb := '[]'::jsonb; q jsonb; v_txt text;
        v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_name text := trim(coalesce(p_name, ''));
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  if p_phase not in ('pre', 'post') then raise exception 'ระบุ Pre หรือ Post'; end if;
  if (p_phase = 'pre' and not t.pre_open) or (p_phase = 'post' and not t.post_open) then
    raise exception 'แบบทดสอบ %-test ปิดรับแล้ว', initcap(p_phase);
  end if;
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  v_n := jsonb_array_length(t.questions);
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> v_n then
    raise exception 'กรุณาตอบให้ครบทุกข้อ';
  end if;
  for i in 0 .. v_n - 1 loop
    q := t.questions -> i;
    if q ->> 'kind' = 'text' then
      v_txt := case when jsonb_typeof(p_answers -> i) = 'string' then trim(p_answers ->> i) else '' end;
      if v_txt = '' then raise exception 'กรุณาตอบข้อเขียนให้ครบ'; end if;
      v_clean := v_clean || to_jsonb(left(v_txt, 2000));
    else
      if jsonb_typeof(p_answers -> i) <> 'number' then raise exception 'กรุณาตอบให้ครบทุกข้อ'; end if;
      v_ans := (p_answers ->> i)::int;
      v_clean := v_clean || to_jsonb(v_ans);
      if v_ans = (q ->> 'correct')::int then v_score := v_score + 1;
      else v_wrong := v_wrong || to_jsonb(i); end if;
    end if;
  end loop;

  perform pg_advisory_xact_lock(hashtext(t.id::text || p_phase || v_emp));
  select * into v_last from test_submissions where training_id = t.id and phase = p_phase and emp_id = v_emp
   order by attempt desc limit 1;
  if v_last.id is not null then
    if p_phase = 'pre' then raise exception 'รหัสพนักงาน % ส่ง Pre-test ของรอบนี้ไปแล้ว', v_emp; end if;
    if 100.0 * v_last.score / v_last.total >= t.pass_percent then raise exception 'ท่านสอบ Post-test ผ่านแล้ว'; end if;
    if not t.retake then raise exception 'รหัสพนักงาน % ส่ง Post-test ของรอบนี้ไปแล้ว', v_emp; end if;
  end if;
  v_att := coalesce(v_last.attempt, 0) + 1;
  insert into test_submissions (training_id, phase, emp_id, full_name, hospital, department, answers, score, total, attempt)
  values (t.id, p_phase, v_emp, left(v_name, 120), left(trim(coalesce(p_hospital, '')), 120),
          left(trim(coalesce(p_dept, '')), 120), v_clean, v_score, t.total, v_att);

  if p_phase = 'pre' then return jsonb_build_object('ok', true, 'phase', 'pre'); end if;
  v_pass := 100.0 * v_score / t.total >= t.pass_percent;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  return jsonb_build_object('ok', true, 'phase', 'post', 'score', v_score, 'total', t.total, 'attempt', v_att,
    'percent', round(100.0 * v_score / t.total), 'pass', v_pass, 'pass_percent', t.pass_percent,
    'retake', t.retake, 'pre_score', v_pre.score,
    'wrong', case when v_pass then '[]'::jsonb else v_wrong end,
    'need_survey', v_pass and t.survey_id is not null
                   and not exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp));
end $$;

-- เกม Pre-test: ข้ามข้อเขียน (จำเลขข้อของรอบไว้ใน ti เพื่อบันทึกผลให้ตรงข้อ)
create or replace function public.create_pre_game(p_training uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; s sessions; v_qs jsonb; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into t from trainings where id = p_training;
  if t.id is null or not (t.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'ไม่พบรอบนี้ หรือไม่มีสิทธิ์';
  end if;
  select * into s from sessions where training_id = t.id and status <> 'ended' order by created_at desc limit 1;
  if s.id is not null then
    if s.host_id <> auth.uid() then
      raise exception 'มีห้องเกม Pre-test ของรอบนี้เปิดอยู่แล้ว (PIN %) โดยผู้จัดอีกคน', s.pin;
    end if;
    return jsonb_build_object('session_id', s.id, 'pin', s.pin, 'resumed', true);
  end if;

  select jsonb_agg(x.q || jsonb_build_object('ti', x.o - 1, 'time', least(120, greatest(5, coalesce(
           (x.q ->> 'time')::int,
           (select time_limit from questions where quiz_id = t.quiz_id order by position offset (x.o - 1) limit 1),
           20)))) order by x.o)
    into v_qs from jsonb_array_elements(t.questions) with ordinality as x(q, o)
   where coalesce(x.q ->> 'kind', 'choice') <> 'text';
  if v_qs is null then raise exception 'รอบนี้ยังไม่มีข้อปรนัย'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url, training_id)
  values (t.quiz_id, auth.uid(), t.title, v_pin, v_qs, jsonb_array_length(v_qs), t.cover_url, t.id)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- จบเกม Pre-test: คำตอบเรียงตามข้อของรอบ (ข้อเขียน = null) · คะแนนเต็ม = จำนวนข้อปรนัยของรอบ
create or replace function public.finish_pre_game(p_session uuid)
returns int language plpgsql security definer set search_path = public as $$
declare s sessions; t trainings; v_n int;
begin
  select * into s from sessions where id = p_session;
  if s.training_id is null then return 0; end if;
  select * into t from trainings where id = s.training_id;
  if t.id is null then return 0; end if;
  insert into test_submissions (training_id, phase, emp_id, full_name, hospital, department,
                                answers, score, total, attempt, source)
  select t.id, 'pre', p.emp_id, left(coalesce(p.full_name, p.nickname), 120),
         coalesce(p.hospital, ''), coalesce(p.department, ''),
         (select jsonb_agg(case when x.q ->> 'kind' = 'text' then null else
                   (select to_jsonb(a.choice) from answers a
                     where a.player_id = p.id
                       and a.question_index = coalesce(
                             (select (g.k - 1)::int from jsonb_array_elements(s.questions) with ordinality g(gq, k)
                               where (g.gq ->> 'ti')::int = x.o - 1 limit 1),
                             case when not exists (select 1 from jsonb_array_elements(s.questions) gq where gq ? 'ti')
                                  then (x.o - 1)::int end)) end order by x.o)
            from jsonb_array_elements(t.questions) with ordinality as x(q, o)),
         (select count(*) from answers a where a.player_id = p.id and a.is_correct),
         t.total, 1, 'game'
    from players p
   where p.session_id = s.id and p.emp_id is not null
     and exists (select 1 from answers a where a.player_id = p.id)
     and not exists (select 1 from test_submissions x
                      where x.training_id = s.training_id and x.phase = 'pre' and x.emp_id = p.emp_id)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- =====================================================================
-- 12) v10: 👥 ผู้จัดร่วมของรอบ Pre/Post
--     - เจ้าของรอบ/ผู้ดูแลระบบ ใส่อีเมลพนักงานเป็นผู้จัดร่วมได้ (ต่อรอบ หรือทั้งชุดหลักสูตร)
--     - ผู้จัดร่วม: เห็นรอบนั้น เปิด-ปิด Pre/Post · ตั้งค่า · เกม Pre-test · รายงาน · Excel · ลบผลรายคน
--     - ผู้จัดร่วมลบรอบ / แก้รายชื่อผู้จัดร่วมไม่ได้ · ไม่เห็นงานอื่นของเจ้าของ
-- =====================================================================
alter table public.trainings add column if not exists cohosts text[] not null default '{}';

create or replace function public.is_cohost(p_cohosts text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_staff() and coalesce(lower(auth.jwt() ->> 'email') = any(p_cohosts), false)
$$;

drop policy if exists trainings_owner on public.trainings;
create policy trainings_owner on public.trainings for select to authenticated
  using (owner_id = auth.uid() or public.is_admin() or public.is_cohost(cohosts));
drop policy if exists trainings_owner_upd on public.trainings;
create policy trainings_owner_upd on public.trainings for update to authenticated
  using (owner_id = auth.uid() or public.is_admin() or public.is_cohost(cohosts))
  with check (owner_id = auth.uid() or public.is_admin() or public.is_cohost(cohosts));

-- กันผู้จัดร่วมแก้รายชื่อผู้จัดร่วม / เปลี่ยนเจ้าของ
create or replace function public.trainings_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- งานภายในระบบ
  if (new.cohosts is distinct from old.cohosts or new.owner_id is distinct from old.owner_id
      or new.owner_email is distinct from old.owner_email)
     and not (old.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'เฉพาะเจ้าของรอบหรือผู้ดูแลระบบที่แก้รายชื่อผู้จัดร่วมได้';
  end if;
  return new;
end $$;
drop trigger if exists trainings_guard on public.trainings;
create trigger trainings_guard before update on public.trainings
  for each row execute function public.trainings_guard();

-- ตั้งรายชื่อผู้จัดร่วม (p_series = true → ทุกรุ่นในชุดเดียวกันที่เป็นของเรา)
create or replace function public.set_cohosts(p_training uuid, p_emails jsonb, p_series boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v text[]; v_dom text; v_bad text; v_n int;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into t from trainings where id = p_training;
  if t.id is null or not (t.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'เฉพาะเจ้าของรอบหรือผู้ดูแลระบบ';
  end if;
  if jsonb_typeof(coalesce(p_emails, '[]'::jsonb)) <> 'array' then raise exception 'รายชื่อไม่ถูกต้อง'; end if;
  select lower(allowed_domain) into v_dom from app_config where id = 1;
  select coalesce(array_agg(distinct e), '{}') into v
    from (select lower(trim(x)) e from jsonb_array_elements_text(coalesce(p_emails, '[]'::jsonb)) x) s
   where e <> '' and e <> lower(coalesce(t.owner_email, ''));
  select e into v_bad from unnest(v) e where e !~ ('^[^@\s]+@' || replace(v_dom, '.', '\.') || '$') limit 1;
  if v_bad is not null then raise exception 'ใช้ได้เฉพาะอีเมล @% (%)', v_dom, v_bad; end if;
  if cardinality(v) > 20 then raise exception 'ผู้จัดร่วมได้ไม่เกิน 20 คน'; end if;
  update trainings set cohosts = v
   where (id = t.id or (p_series and t.series_id is not null and series_id = t.series_id))
     and (owner_id = auth.uid() or public.is_admin());
  get diagnostics v_n = row_count;
  return jsonb_build_object('cohosts', to_jsonb(v), 'rounds', v_n);
end $$;
revoke execute on function public.set_cohosts(uuid, jsonb, boolean) from public, anon;
grant execute on function public.set_cohosts(uuid, jsonb, boolean) to authenticated;

-- เกม Pre-test: ผู้จัดร่วมเปิดได้
create or replace function public.create_pre_game(p_training uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; s sessions; v_qs jsonb; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into t from trainings where id = p_training;
  if t.id is null or not (t.owner_id = auth.uid() or public.is_admin() or public.is_cohost(t.cohosts)) then
    raise exception 'ไม่พบรอบนี้ หรือไม่มีสิทธิ์';
  end if;
  select * into s from sessions where training_id = t.id and status <> 'ended' order by created_at desc limit 1;
  if s.id is not null then
    if s.host_id <> auth.uid() then
      raise exception 'มีห้องเกม Pre-test ของรอบนี้เปิดอยู่แล้ว (PIN %) โดยผู้จัดอีกคน', s.pin;
    end if;
    return jsonb_build_object('session_id', s.id, 'pin', s.pin, 'resumed', true);
  end if;

  select jsonb_agg(x.q || jsonb_build_object('ti', x.o - 1, 'time', least(120, greatest(5, coalesce(
           (x.q ->> 'time')::int,
           (select time_limit from questions where quiz_id = t.quiz_id order by position offset (x.o - 1) limit 1),
           20)))) order by x.o)
    into v_qs from jsonb_array_elements(t.questions) with ordinality as x(q, o)
   where coalesce(x.q ->> 'kind', 'choice') <> 'text';
  if v_qs is null then raise exception 'รอบนี้ยังไม่มีข้อปรนัย'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url, training_id)
  values (t.quiz_id, auth.uid(), t.title, v_pin, v_qs, jsonb_array_length(v_qs), t.cover_url, t.id)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- =====================================================================
-- 13) v11: 👥 ผู้ร่วมแก้ไขชุดคำถาม
--     - เจ้าของ/ผู้ดูแล ใส่อีเมลพนักงานเป็นผู้ร่วมแก้ไขได้ (ไม่ต้องแชร์ให้ทุกแผนก)
--     - ผู้ร่วมแก้ไข: เห็นและแก้ชุดนั้น · เปิดเกม · สร้างรอบ Pre/Post
--     - ลบชุด / เปลี่ยนแชร์-ส่วนตัว / แก้รายชื่อผู้ร่วมแก้ไข ทำได้เฉพาะเจ้าของหรือผู้ดูแล
-- =====================================================================
alter table public.quizzes add column if not exists editors text[] not null default '{}';

drop policy if exists quizzes_read on public.quizzes;
create policy quizzes_read on public.quizzes for select to authenticated
  using (public.is_staff() and (owner_id = auth.uid() or shared or public.is_admin() or public.is_cohost(editors)));
drop policy if exists quizzes_update on public.quizzes;
create policy quizzes_update on public.quizzes for update to authenticated
  using (owner_id = auth.uid() or public.is_admin() or public.is_cohost(editors))
  with check (owner_id = auth.uid() or public.is_admin() or public.is_cohost(editors));
drop policy if exists questions_write on public.questions;
create policy questions_write on public.questions for all to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id
                  and (q.owner_id = auth.uid() or public.is_admin() or public.is_cohost(q.editors))))
  with check (exists (select 1 from public.quizzes q where q.id = quiz_id
                  and (q.owner_id = auth.uid() or public.is_admin() or public.is_cohost(q.editors))));

create or replace function public.quizzes_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if (new.editors is distinct from old.editors or new.shared is distinct from old.shared
      or new.owner_id is distinct from old.owner_id or new.owner_email is distinct from old.owner_email)
     and not (old.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'เฉพาะเจ้าของชุดหรือผู้ดูแลระบบที่เปลี่ยนการแชร์/ผู้ร่วมแก้ไขได้';
  end if;
  return new;
end $$;
drop trigger if exists quizzes_guard on public.quizzes;
create trigger quizzes_guard before update on public.quizzes
  for each row execute function public.quizzes_guard();

create or replace function public.set_quiz_editors(p_quiz uuid, p_emails jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q quizzes; v text[]; v_dom text; v_bad text;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into q from quizzes where id = p_quiz;
  if q.id is null or not (q.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'เฉพาะเจ้าของชุดหรือผู้ดูแลระบบ';
  end if;
  if jsonb_typeof(coalesce(p_emails, '[]'::jsonb)) <> 'array' then raise exception 'รายชื่อไม่ถูกต้อง'; end if;
  select lower(allowed_domain) into v_dom from app_config where id = 1;
  select coalesce(array_agg(distinct e), '{}') into v
    from (select lower(trim(x)) e from jsonb_array_elements_text(coalesce(p_emails, '[]'::jsonb)) x) s
   where e <> '' and e <> lower(coalesce(q.owner_email, ''));
  select e into v_bad from unnest(v) e where e !~ ('^[^@\s]+@' || replace(v_dom, '.', '\.') || '$') limit 1;
  if v_bad is not null then raise exception 'ใช้ได้เฉพาะอีเมล @% (%)', v_dom, v_bad; end if;
  if cardinality(v) > 20 then raise exception 'ผู้ร่วมแก้ไขได้ไม่เกิน 20 คน'; end if;
  update quizzes set editors = v where id = q.id;
  return to_jsonb(v);
end $$;
revoke execute on function public.set_quiz_editors(uuid, jsonb) from public, anon;
grant execute on function public.set_quiz_editors(uuid, jsonb) to authenticated;


-- เปิดเกม / สร้างรอบ: ผู้ร่วมแก้ไขทำได้แม้ชุดเป็นแบบส่วนตัว
create or replace function public.create_session(p_quiz_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin() or public.is_cohost(v_quiz.editors)) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;

  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices,
           'correct', correct_index, 'time', time_limit,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n
    from questions where quiz_id = p_quiz_id and kind <> 'text';
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีข้อปรนัยสำหรับเล่นเกม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;

  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url)
  values (p_quiz_id, auth.uid(), v_quiz.title, v_pin, v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

create or replace function public.create_training(p_quiz_id uuid, p_title text, p_pass int default 80)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_code text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin() or public.is_cohost(v_quiz.editors)) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;
  select jsonb_agg(case when kind = 'text'
             then jsonb_build_object('kind', 'text', 'text', text, 'image_url', image_url, 'choices', '[]'::jsonb)
             else jsonb_build_object('text', text, 'image_url', image_url, 'choices', choices, 'correct', correct_index,
                    'time', time_limit, 'colors', colors, 'images', choice_images) end order by position),
         count(*) filter (where kind <> 'text')
    into v_qs, v_n from questions where quiz_id = p_quiz_id;
  if coalesce(v_n, 0) = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีข้อปรนัย'; end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from trainings where code = v_code);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into trainings (quiz_id, title, code, pass_percent, questions, total, cover_url)
  values (p_quiz_id, left(coalesce(nullif(trim(p_title), ''), v_quiz.title), 200), v_code,
          least(100, greatest(0, coalesce(p_pass, 80))), v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end $$;

-- บันทึกชุดคำถาม: ผู้ร่วมแก้ไขบันทึกได้ (การแชร์เปลี่ยนได้เฉพาะเจ้าของ — ดู quizzes_guard)
create or replace function public.save_quiz(
  p_id uuid, p_title text, p_department text, p_description text, p_questions jsonb,
  p_cover text default null, p_shared boolean default false
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) q
                  where coalesce(q ->> 'kind', 'choice') <> 'text') then
    raise exception 'ต้องมีข้อปรนัย (มีตัวเลือก) อย่างน้อย 1 ข้อ';
  end if;
  if p_id is null then
    insert into quizzes (title, department, description, cover_url, shared)
    values (trim(p_title), trim(coalesce(p_department, '')), coalesce(p_description, ''), nullif(p_cover, ''),
            coalesce(p_shared, false))
    returning id into v_id;
  else
    update quizzes set title = trim(p_title), department = trim(coalesce(p_department, '')),
                       description = coalesce(p_description, ''), cover_url = nullif(p_cover, ''),
                       shared = coalesce(p_shared, false), updated_at = now()
     where id = p_id and (owner_id = auth.uid() or public.is_admin() or public.is_cohost(editors))
    returning id into v_id;
    if v_id is null then raise exception 'ไม่มีสิทธิ์แก้ไขชุดคำถามนี้'; end if;
    delete from questions where quiz_id = v_id;
  end if;

  insert into questions (quiz_id, position, kind, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, (t.ord - 1)::int, k, trim(t.q ->> 'text'), nullif(t.q ->> 'image_url', ''),
         case when k = 'text' then '[]'::jsonb else t.q -> 'choices' end,
         case when k = 'text' then null else (t.q ->> 'correct_index')::int end,
         coalesce((t.q ->> 'time_limit')::int, 20),
         case when k = 'choice' and jsonb_typeof(t.q -> 'colors') = 'array'
               and not exists (select 1 from jsonb_array_elements_text(t.q -> 'colors') c
                                where c !~ '^#[0-9a-fA-F]{6}$')
              then t.q -> 'colors' end,
         case when k = 'choice' and jsonb_typeof(t.q -> 'choice_images') = 'array' then t.q -> 'choice_images' end
    from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) with ordinality as t(q, ord),
         lateral (select case when t.q ->> 'kind' = 'text' then 'text' else 'choice' end as k) kk;
  return v_id;
end $$;


-- =====================================================================
-- 14) v12: เฉลยผิดหลังเริ่มอบรม — ให้คะแนนได้มากกว่า 1 ตัวเลือกในรอบที่มีผลสอบแล้ว
--     สำเนาคำถามของรอบใส่ "also": [เลขตัวเลือกที่ให้คะแนนเพิ่ม] (0 = ก, 1 = ข, ...)
--     ตรวจคะแนนใหม่ของผลที่ส่งแล้ว: select public.rescore_training('<training id>');
-- =====================================================================
create or replace function public.test_status(p_code text, p_emp_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; v_emp text := upper(trim(coalesce(p_emp_id, ''))); last test_submissions; first test_submissions;
        v_pre test_submissions; v_n int; v_passed boolean; v_wrong jsonb;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  select count(*) into v_n from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp;
  select * into last  from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt desc limit 1;
  select * into first from test_submissions where training_id = t.id and phase = 'post' and emp_id = v_emp order by attempt limit 1;
  v_passed := last.id is not null and 100.0 * last.score / last.total >= t.pass_percent;
  if last.id is not null and not v_passed then
    select coalesce(jsonb_agg(o - 1), '[]'::jsonb) into v_wrong
      from jsonb_array_elements(t.questions) with ordinality x(q, o)
     where coalesce(q ->> 'kind', 'choice') <> 'text'
       and (last.answers ->> (o - 1)::int) is distinct from (q ->> 'correct')
       and not (coalesce(q -> 'also', '[]'::jsonb) @> coalesce(last.answers -> (o - 1)::int, 'null'::jsonb)
                and jsonb_typeof(last.answers -> (o - 1)::int) = 'number');
  end if;
  return jsonb_build_object(
    'pre_done', v_pre.id is not null, 'pre_score', v_pre.score,
    'post_attempts', v_n, 'post_passed', v_passed,
    'survey_done', exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp),
    'has_survey', t.survey_id is not null,
    'score', last.score, 'total', t.total, 'first_score', first.score,
    'percent', case when last.id is not null then round(100.0 * last.score / t.total) end,
    'last_answers', case when not v_passed then last.answers end,
    'wrong', v_wrong);
end $$;

create or replace function public.submit_test(
  p_code text, p_phase text, p_emp_id text, p_name text, p_hospital text, p_dept text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v_score int := 0; i int; v_n int; v_ans int; v_pre test_submissions; v_att int; v_last test_submissions;
        v_pass boolean; v_wrong jsonb := '[]'::jsonb; v_clean jsonb := '[]'::jsonb; q jsonb; v_txt text;
        v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_name text := trim(coalesce(p_name, ''));
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  if p_phase not in ('pre', 'post') then raise exception 'ระบุ Pre หรือ Post'; end if;
  if (p_phase = 'pre' and not t.pre_open) or (p_phase = 'post' and not t.post_open) then
    raise exception 'แบบทดสอบ %-test ปิดรับแล้ว', initcap(p_phase);
  end if;
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  v_n := jsonb_array_length(t.questions);
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> v_n then
    raise exception 'กรุณาตอบให้ครบทุกข้อ';
  end if;
  for i in 0 .. v_n - 1 loop
    q := t.questions -> i;
    if q ->> 'kind' = 'text' then
      v_txt := case when jsonb_typeof(p_answers -> i) = 'string' then trim(p_answers ->> i) else '' end;
      if v_txt = '' then raise exception 'กรุณาตอบข้อเขียนให้ครบ'; end if;
      v_clean := v_clean || to_jsonb(left(v_txt, 2000));
    else
      if jsonb_typeof(p_answers -> i) <> 'number' then raise exception 'กรุณาตอบให้ครบทุกข้อ'; end if;
      v_ans := (p_answers ->> i)::int;
      v_clean := v_clean || to_jsonb(v_ans);
      if v_ans = (q ->> 'correct')::int or coalesce(q -> 'also', '[]'::jsonb) @> to_jsonb(v_ans) then v_score := v_score + 1;
      else v_wrong := v_wrong || to_jsonb(i); end if;
    end if;
  end loop;

  perform pg_advisory_xact_lock(hashtext(t.id::text || p_phase || v_emp));
  select * into v_last from test_submissions where training_id = t.id and phase = p_phase and emp_id = v_emp
   order by attempt desc limit 1;
  if v_last.id is not null then
    if p_phase = 'pre' then raise exception 'รหัสพนักงาน % ส่ง Pre-test ของรอบนี้ไปแล้ว', v_emp; end if;
    if 100.0 * v_last.score / v_last.total >= t.pass_percent then raise exception 'ท่านสอบ Post-test ผ่านแล้ว'; end if;
    if not t.retake then raise exception 'รหัสพนักงาน % ส่ง Post-test ของรอบนี้ไปแล้ว', v_emp; end if;
  end if;
  v_att := coalesce(v_last.attempt, 0) + 1;
  insert into test_submissions (training_id, phase, emp_id, full_name, hospital, department, answers, score, total, attempt)
  values (t.id, p_phase, v_emp, left(v_name, 120), left(trim(coalesce(p_hospital, '')), 120),
          left(trim(coalesce(p_dept, '')), 120), v_clean, v_score, t.total, v_att);

  if p_phase = 'pre' then return jsonb_build_object('ok', true, 'phase', 'pre'); end if;
  v_pass := 100.0 * v_score / t.total >= t.pass_percent;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp order by attempt limit 1;
  return jsonb_build_object('ok', true, 'phase', 'post', 'score', v_score, 'total', t.total, 'attempt', v_att,
    'percent', round(100.0 * v_score / t.total), 'pass', v_pass, 'pass_percent', t.pass_percent,
    'retake', t.retake, 'pre_score', v_pre.score,
    'wrong', case when v_pass then '[]'::jsonb else v_wrong end,
    'need_survey', v_pass and t.survey_id is not null
                   and not exists (select 1 from survey_done where training_id = t.id and emp_id = v_emp));
end $$;

create or replace function public.rescore_training(p_training uuid)
returns int language plpgsql security definer set search_path = public as $$
declare t trainings; v_n int;
begin
  select * into t from trainings where id = p_training;
  if t.id is null then raise exception 'ไม่พบรอบนี้'; end if;
  if auth.uid() is not null and not (t.owner_id = auth.uid() or public.is_admin()) then
    raise exception 'เฉพาะเจ้าของรอบหรือผู้ดูแลระบบ';
  end if;
  update test_submissions s set score = (
      select count(*) from jsonb_array_elements(t.questions) with ordinality x(q, o)
       where coalesce(q ->> 'kind', 'choice') <> 'text'
         and jsonb_typeof(s.answers -> (o - 1)::int) = 'number'
         and ((s.answers ->> (o - 1)::int)::int = (q ->> 'correct')::int
              or coalesce(q -> 'also', '[]'::jsonb) @> (s.answers -> (o - 1)::int))),
      total = t.total
   where s.training_id = t.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke execute on function public.rescore_training(uuid) from public, anon;
grant execute on function public.rescore_training(uuid) to authenticated;

-- =====================================================================
-- 15) v13: รายชื่อผู้จองอบรม (roster) — Apps Script ส่งข้อมูลมาอัปเดตเอง
--     - หน้า Pre/Post: ใส่รหัสพนักงาน → เติมชื่อ-แผนกจากรายชื่อผู้จอง · จองรุ่นอื่นไว้ → เตือนก่อนทำ
--     - ค้นได้เฉพาะรอบที่ผูก roster ไว้ (trainings.roster) และกำลังเปิดรับ Pre/Post เท่านั้น
--     - คีย์สำหรับ Apps Script: app_config.roster_key (อ่านไม่ได้จากหน้าเว็บ)
--       ตั้ง/เปลี่ยนคีย์: update app_config set roster_key = '<คีย์ยาว>' where id = 1;
-- =====================================================================
alter table public.app_config add column if not exists roster_key text;
alter table public.trainings add column if not exists roster text;

create table if not exists public.roster (
  source     text not null,
  emp_key    text not null,               -- รหัสพนักงานแบบเทียบได้ (ตัวพิมพ์ใหญ่ ตัด 0 นำหน้า)
  emp_id     text not null,
  full_name  text not null default '',
  dept       text not null default '',
  slot       text not null default '',    -- เช่น "11 พ.ย. เช้า" (ตรงกับชื่อรุ่น)
  slot_text  text not null default '',    -- เช่น "11 พฤศจิกายน 2569 10:00 น."
  updated_at timestamptz not null default now(),
  primary key (source, emp_key)
);
alter table public.roster enable row level security;
revoke all on public.roster from anon, authenticated;
grant select on public.roster to authenticated;
drop policy if exists roster_admin_read on public.roster;
create policy roster_admin_read on public.roster for select to authenticated using (public.is_admin());

create or replace function public.roster_norm(p text) returns text
language sql immutable as $$ select ltrim(upper(regexp_replace(coalesce(p, ''), '\s', '', 'g')), '0') $$;

-- Apps Script เรียก: แทนที่รายชื่อทั้งหมดของ source นั้น
create or replace function public.sync_roster(p_key text, p_source text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_key text; v_n int;
begin
  select roster_key into v_key from app_config where id = 1;
  if v_key is null or length(v_key) < 24 or p_key is distinct from v_key then raise exception 'คีย์ไม่ถูกต้อง'; end if;
  if coalesce(trim(p_source), '') = '' or jsonb_typeof(p_rows) <> 'array' then raise exception 'ข้อมูลไม่ถูกต้อง'; end if;
  if jsonb_array_length(p_rows) > 20000 then raise exception 'รายชื่อมากเกินไป'; end if;
  delete from roster where source = trim(p_source);
  insert into roster (source, emp_key, emp_id, full_name, dept, slot, slot_text)
  select distinct on (public.roster_norm(r ->> 'emp_id'))
         trim(p_source), public.roster_norm(r ->> 'emp_id'), left(trim(r ->> 'emp_id'), 30),
         left(trim(coalesce(r ->> 'full_name', '')), 120), left(trim(coalesce(r ->> 'dept', '')), 120),
         left(trim(coalesce(r ->> 'slot', '')), 60), left(trim(coalesce(r ->> 'slot_text', '')), 120)
    from jsonb_array_elements(p_rows) with ordinality x(r, o)
   where public.roster_norm(r ->> 'emp_id') <> ''
   order by public.roster_norm(r ->> 'emp_id'), o desc;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'rows', v_n, 'at', now());
end $$;
revoke execute on function public.sync_roster(text, text, jsonb) from public;
grant execute on function public.sync_roster(text, text, jsonb) to anon, authenticated;

-- หน้า Pre/Post: ค้นจากรหัสพนักงาน (เฉพาะรอบที่ผูก roster และกำลังเปิดรับ)
create or replace function public.roster_lookup(p_code text, p_emp text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; r roster; v_label text;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null or t.roster is null or not (t.pre_open or t.post_open) then return null; end if;
  if public.roster_norm(p_emp) = '' then return null; end if;
  select * into r from roster where source = t.roster and emp_key = public.roster_norm(p_emp);
  if r.emp_key is null then return jsonb_build_object('found', false); end if;
  v_label := coalesce(t.round_label, t.title);
  return jsonb_build_object('found', true, 'emp_id', r.emp_id, 'full_name', r.full_name, 'dept', r.dept,
    'slot', r.slot, 'slot_text', r.slot_text,
    'this_round', r.slot = '' or position(r.slot in v_label) > 0);
end $$;
revoke execute on function public.roster_lookup(text, text) from public;
grant execute on function public.roster_lookup(text, text) to anon, authenticated;

-- test_info: บอกหน้าเว็บว่ารอบนี้มีรายชื่อผู้จองให้ค้น
create or replace function public.test_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings; sv surveys;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  select * into sv from surveys where id = t.survey_id;
  return jsonb_build_object(
    'title', t.title, 'cover_url', t.cover_url, 'total', t.total, 'count', jsonb_array_length(t.questions),
    'pre_open', t.pre_open, 'post_open', t.post_open, 'pass_percent', t.pass_percent,
    'shuffle', t.shuffle, 'retake', t.retake, 'roster', t.roster is not null,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'hospitals', public.list_hospitals(),
    'survey', case when sv.id is not null then jsonb_build_object('title', sv.title, 'description', sv.description, 'items', sv.items) end,
    'questions', case when t.pre_open or t.post_open then
      (select jsonb_agg(jsonb_build_object('kind', coalesce(q ->> 'kind', 'choice'), 'text', q ->> 'text', 'image_url', q ->> 'image_url',
              'choices', q -> 'choices', 'colors', q -> 'colors', 'images', q -> 'images') order by o)
         from jsonb_array_elements(t.questions) with ordinality as x(q, o)) end);
end $$;
